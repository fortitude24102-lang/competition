package gpu

import chisel3._
import chisel3.util._

class AxiReadRequest extends Bundle {
  val address = UInt(32.W)
  val bytes = UInt(32.W)
}

class AxiReadBeat extends Bundle {
  val address = UInt(32.W)
  val data = UInt(32.W)
  val last = Bool()
}

class AxiReadEngine extends Module {
  val io = IO(new Bundle {
    val request = Flipped(Decoupled(new AxiReadRequest))
    val data = Decoupled(new AxiReadBeat)
    val axiAr = Decoupled(new Axi4Address)
    val axiR = Flipped(Decoupled(new Axi4ReadData))
    val done = Output(Bool())
    val error = Output(Bool())
  })

  private val idle :: sendAddress :: receiveData :: Nil = Enum(3)
  private val state = RegInit(idle)
  private val currentAddress = Reg(UInt(32.W))
  private val beatAddress = Reg(UInt(32.W))
  private val remainingBeats = Reg(UInt(32.W))
  private val beatsLeftInBurst = Reg(UInt(9.W))
  private val errorSeen = RegInit(false.B)
  private val doneReg = RegInit(false.B)
  private val errorReg = RegInit(false.B)

  doneReg := false.B
  errorReg := false.B
  io.done := doneReg
  io.error := errorReg

  io.request.ready := state === idle

  private val wordsToBoundary = (4096.U(13.W) - currentAddress(11, 0)) >> 2
  private val cappedRemaining = Mux(remainingBeats > 256.U, 256.U, remainingBeats)
  private val burstBeats = Mux(cappedRemaining > wordsToBoundary, wordsToBoundary, cappedRemaining)

  io.axiAr.valid := state === sendAddress
  io.axiAr.bits.addr := currentAddress
  io.axiAr.bits.id := 0.U
  io.axiAr.bits.len := (burstBeats - 1.U)(7, 0)
  io.axiAr.bits.size := Axi4.WordSize.U
  io.axiAr.bits.burst := Axi4.Incrementing.U
  io.axiAr.bits.lock := false.B
  io.axiAr.bits.cache := 0.U
  io.axiAr.bits.prot := 0.U
  io.axiAr.bits.qos := 0.U
  io.axiAr.bits.region := 0.U

  io.data.valid := state === receiveData && io.axiR.valid
  io.data.bits.address := beatAddress
  io.data.bits.data := io.axiR.bits.data
  io.data.bits.last := remainingBeats === 1.U
  io.axiR.ready := state === receiveData && io.data.ready

  when(io.request.fire) {
    val byteOffset = io.request.bits.address(1, 0)
    val totalBytes = Cat(0.U(1.W), io.request.bits.bytes) + byteOffset
    currentAddress := Cat(io.request.bits.address(31, 2), 0.U(2.W))
    remainingBeats := (totalBytes + 3.U) >> 2
    errorSeen := false.B
    when(io.request.bits.bytes === 0.U) {
      doneReg := true.B
      errorReg := false.B
    }.otherwise {
      state := sendAddress
    }
  }

  when(io.axiAr.fire) {
    beatsLeftInBurst := burstBeats(8, 0)
    beatAddress := currentAddress
    state := receiveData
  }

  when(io.axiR.fire) {
    val expectedLast = beatsLeftInBurst === 1.U
    val beatError = io.axiR.bits.resp =/= Axi4.Okay.U || io.axiR.bits.last =/= expectedLast
    errorSeen := errorSeen || beatError

    when(remainingBeats === 1.U) {
      doneReg := true.B
      errorReg := errorSeen || beatError
      errorSeen := false.B
      state := idle
    }.otherwise {
      remainingBeats := remainingBeats - 1.U
      currentAddress := currentAddress + 4.U
      beatAddress := beatAddress + 4.U
      when(expectedLast) {
        state := sendAddress
      }.otherwise {
        beatsLeftInBurst := beatsLeftInBurst - 1.U
      }
    }
  }
}
