package gpu

import chisel3._
import chisel3.util._

class FrameListRequest extends Bundle {
  val address = UInt(32.W)
  val count = UInt(16.W)
}

/** Transport only: done is NOT render/PRESENT completion. The future batch
  * owner must keep source/template/epoch immutable and retire the pixel queue.
  * ponytail: prefetch one complete <=16KiB list before pixel reads share DDR;
  * a streaming FIFO needs a separate arbitration/deadlock proof first.
  */
class FrameListReader(maxDescriptors: Int = 1024) extends Module {
  require(maxDescriptors > 0 && maxDescriptors <= 1024)
  val io = IO(new Bundle {
    val request = Flipped(Decoupled(new FrameListRequest))
    val descriptor = Decoupled(Vec(4, UInt(32.W)))
    val axiAr = Decoupled(new Axi4Address)
    val axiR = Flipped(Decoupled(new Axi4ReadData))
    val busy = Output(Bool())
    val fetching = Output(Bool())
    val done = Output(Bool())
    val error = Output(UInt(8.W))
    val fetchedBytes = Output(UInt(32.W))
  })
  private val idle :: issue :: loading :: fetch :: latch :: emit :: Nil = Enum(6)
  private val state = RegInit(idle)
  private val reader = Module(new AxiReadEngine(6))
  private val buffer = SyncReadMem(maxDescriptors, Vec(4, UInt(32.W)))
  private val indexBits = math.max(1, log2Ceil(maxDescriptors))
  private val address = Reg(UInt(32.W))
  private val count = Reg(UInt(16.W))
  private val words = RegInit(0.U(13.W))
  private val index = RegInit(0.U(indexBits.W))
  private val remaining = Reg(UInt(16.W))
  private val held = Reg(Vec(4, UInt(32.W)))
  private val done = RegInit(false.B)
  private val error = RegInit(GpuError.None.U(8.W))
  done := false.B
  io.done := done
  io.error := error
  io.busy := state =/= idle
  io.fetching := state === issue || state === loading
  io.fetchedBytes := (words << 2).pad(32)
  io.request.ready := state === idle
  io.descriptor.valid := state === emit
  io.descriptor.bits := held
  io.axiAr <> reader.io.axiAr
  reader.io.axiR <> io.axiR
  reader.io.request.valid := state === issue
  reader.io.request.bits.address := address
  reader.io.request.bits.bytes := count << 4
  reader.io.data.ready := state === loading
  private val end = io.request.bits.address.pad(64) + (io.request.bits.count.pad(64) << 4)
  private val lastByte = end - 1.U
  private val legal = io.request.bits.count > 0.U && io.request.bits.count <= maxDescriptors.U &&
    io.request.bits.address(3,0) === 0.U && io.request.bits.address >= "h02d20000".U &&
    end <= "h02d28000".U(64.W) && io.request.bits.address(31,14) === lastByte(31,14)
  when(io.request.fire) {
    words := 0.U
    index := 0.U
    error := GpuError.None.U
    when(!legal) {
      error := GpuError.AddressRange.U
      done := true.B
    }.otherwise {
      address := io.request.bits.address
      count := io.request.bits.count
      remaining := io.request.bits.count
      state := issue
    }
  }
  when(reader.io.request.fire) { state := loading }
  when(reader.io.data.fire) {
    val lane = words(1,0)
    buffer.write((words >> 2)(indexBits-1,0), VecInit(Seq.fill(4)(reader.io.data.bits.data)),
      VecInit((0 until 4).map(i => lane === i.U)))
    words := words + 1.U
  }
  when(state === loading && reader.io.done) {
    when(reader.io.error) {
      error := GpuError.AxiResponse.U
      done := true.B
      state := idle
    }.otherwise { state := fetch }
  }
  private val data = buffer.read(index, state === fetch)
  when(state === fetch) { state := latch }
  when(state === latch) { held := data; state := emit }
  when(io.descriptor.fire) {
    when(remaining === 1.U) { done := true.B; state := idle }
      .otherwise { index := index + 1.U; remaining := remaining - 1.U; state := fetch }
  }
}
