package gpu

import chisel3._
import chisel3.util._

class AxiWriteRequest extends Bundle {
  val address = UInt(32.W)
  val beats = UInt(32.W)
}

class AxiWriteBeat extends Bundle {
  val data = UInt(32.W)
  val strb = UInt(4.W)
}

class AxiWriteEngine extends Module {
  val io = IO(new Bundle {
    val request = Flipped(Decoupled(new AxiWriteRequest))
    val data = Flipped(Decoupled(new AxiWriteBeat))
    val axiAw = Decoupled(new Axi4Address)
    val axiW = Decoupled(new Axi4WriteData)
    val axiB = Flipped(Decoupled(new Axi4WriteResponse))
    val done = Output(Bool())
    val error = Output(Bool())
  })

  private val idle :: sendAddress :: sendData :: waitResponse :: Nil = Enum(4)
  private val state = RegInit(idle)
  private val currentAddress = Reg(UInt(32.W))
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

  io.axiAw.valid := state === sendAddress
  io.axiAw.bits.addr := currentAddress
  io.axiAw.bits.id := 0.U
  io.axiAw.bits.len := (burstBeats - 1.U)(7, 0)
  io.axiAw.bits.size := Axi4.WordSize.U
  io.axiAw.bits.burst := Axi4.Incrementing.U
  io.axiAw.bits.lock := false.B
  io.axiAw.bits.cache := 0.U
  io.axiAw.bits.prot := 0.U
  io.axiAw.bits.qos := 0.U
  io.axiAw.bits.region := 0.U

  io.axiW.valid := state === sendData && io.data.valid
  io.axiW.bits.data := io.data.bits.data
  io.axiW.bits.strb := io.data.bits.strb
  io.axiW.bits.last := beatsLeftInBurst === 1.U
  io.data.ready := state === sendData && io.axiW.ready
  io.axiB.ready := state === waitResponse

  when(io.request.fire) {
    currentAddress := Cat(io.request.bits.address(31, 2), 0.U(2.W))
    remainingBeats := io.request.bits.beats
    errorSeen := false.B
    when(io.request.bits.beats === 0.U) {
      doneReg := true.B
      errorReg := false.B
    }.otherwise {
      state := sendAddress
    }
  }

  when(io.axiAw.fire) {
    beatsLeftInBurst := burstBeats(8, 0)
    state := sendData
  }

  when(io.axiW.fire) {
    remainingBeats := remainingBeats - 1.U
    currentAddress := currentAddress + 4.U
    when(beatsLeftInBurst === 1.U) {
      state := waitResponse
    }.otherwise {
      beatsLeftInBurst := beatsLeftInBurst - 1.U
    }
  }

  when(io.axiB.fire) {
    val responseError = io.axiB.bits.resp =/= Axi4.Okay.U || io.axiB.bits.id =/= 0.U
    when(remainingBeats === 0.U) {
      doneReg := true.B
      errorReg := errorSeen || responseError
      errorSeen := false.B
      state := idle
    }.otherwise {
      errorSeen := errorSeen || responseError
      state := sendAddress
    }
  }
}
