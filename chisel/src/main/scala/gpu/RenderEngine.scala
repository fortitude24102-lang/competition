package gpu

import chisel3._
import chisel3.util._

/** Queues and validates software commands, then runs the dense renderer. */
class RenderEngine extends Module {
  val io = IO(new Bundle {
    val command = Flipped(Decoupled(new GpuCommand))
    val axi = new Axi4MasterPort
    val completion = Decoupled(new GpuCompletion)
    val busy = Output(Bool())
    val queueLevel = Output(UInt(5.W))
    val queueHighWater = Output(UInt(5.W))
    val queueFull = Output(Bool())
    val queueEmpty = Output(Bool())
  })

  private val queue = Module(new CommandQueue)
  private val validator = Module(new CommandValidator)
  private val blit = Module(new DenseBlitEngine)
  private val pixel = Module(new PixelPipeHarness)
  private val completions = Module(new Arbiter(new GpuCompletion, 2))
  private val completionGap = RegInit(false.B)

  queue.io.enq <> io.command
  validator.io.command := queue.io.deq.bits

  private val implemented = queue.io.deq.bits.op === GpuOpcode.Fill.U ||
    queue.io.deq.bits.op === GpuOpcode.Copy.U
  private val rejected = !validator.io.valid || !implemented

  private val engineIdle = blit.io.command.ready
  completions.io.in(0).valid := queue.io.deq.valid && rejected && engineIdle && !completionGap
  completions.io.in(0).bits.tag := queue.io.deq.bits.tag
  completions.io.in(0).bits.error := Mux(
    validator.io.valid,
    GpuError.InvalidOpcode.U,
    validator.io.error
  )

  blit.io.command.valid := queue.io.deq.valid && !rejected && !completionGap
  blit.io.command.bits := queue.io.deq.bits
  queue.io.deq.ready := Mux(
    rejected,
    completions.io.in(0).ready && engineIdle && !completionGap,
    blit.io.command.ready && !completionGap
  )

  completions.io.in(1).valid := blit.io.completion.valid && !completionGap
  completions.io.in(1).bits := blit.io.completion.bits
  blit.io.completion.ready := completions.io.in(1).ready && !completionGap
  io.completion <> completions.io.out
  completionGap := io.completion.fire
  pixel.io.input <> blit.io.pixelRequest
  blit.io.pixelResult <> pixel.io.output
  io.axi <> blit.io.axi

  io.busy := !queue.io.empty || !blit.io.command.ready || io.completion.valid
  io.queueLevel := queue.io.level
  io.queueHighWater := queue.io.highWater
  io.queueFull := queue.io.full
  io.queueEmpty := queue.io.empty
}
