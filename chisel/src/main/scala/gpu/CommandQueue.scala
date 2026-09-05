package gpu

import chisel3._
import chisel3.util._

class CommandQueue(entries: Int = 16) extends Module {
  require(entries == 16, "the frozen command queue depth is 16")

  val io = IO(new Bundle {
    val enq = Flipped(Decoupled(new GpuCommand))
    val deq = Decoupled(new GpuCommand)
    val level = Output(UInt(log2Ceil(entries + 1).W))
    val highWater = Output(UInt(log2Ceil(entries + 1).W))
    val full = Output(Bool())
    val empty = Output(Bool())
  })

  private val queue = Module(new Queue(new GpuCommand, entries, pipe = true))
  queue.io.enq <> io.enq
  io.deq <> queue.io.deq
  io.level := queue.io.count
  io.full := queue.io.count === entries.U
  io.empty := queue.io.count === 0.U

  private val highWater = RegInit(0.U(log2Ceil(entries + 1).W))
  private val nextLevel = queue.io.count + io.enq.fire.asUInt - io.deq.fire.asUInt
  when(nextLevel > highWater) { highWater := nextLevel }
  io.highWater := highWater
}
