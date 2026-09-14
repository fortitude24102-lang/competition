package gpu

import chisel3._
import chisel3.util._

/** Queues and validates software commands, then runs dense, sparse, or present engines. */
class RenderEngine extends Module {
  val io = IO(new Bundle {
    val command = Flipped(Decoupled(new GpuCommand))
    val vblank = Input(Bool())
    val perfClear = Input(Bool())
    val underflowPulse = Input(Bool())
    val renderGrant = Input(UInt(2.W))
    val scanoutGrant = Input(UInt(2.W))
    val axi = new Axi4MasterPort
    val completion = Decoupled(new GpuCompletion)
    val busy = Output(Bool())
    val queueLevel = Output(UInt(5.W))
    val queueHighWater = Output(UInt(5.W))
    val queueFull = Output(Bool())
    val queueEmpty = Output(Bool())
    val frontBase = Output(UInt(32.W))
    val backBase = Output(UInt(32.W))
    val swapPending = Output(Bool())
    val perfCycles = Output(UInt(64.W))
    val perfPixels = Output(UInt(64.W))
    val perfReadBytes = Output(UInt(64.W))
    val perfWriteBytes = Output(UInt(64.W))
    val perfStalls = Output(UInt(64.W))
    val perfUnderflows = Output(UInt(64.W))
    val perfRenderGrants = Output(UInt(64.W))
    val perfScanoutGrants = Output(UInt(64.W))
  })

  private val queue = Module(new CommandQueue)
  private val validator = Module(new CommandValidator)
  private val blit = Module(new DenseBlitEngine)
  private val sparse = Module(new SparseBlitEngine)
  private val swap = Module(new FrameSwapController)
  private val pixel = Module(new PixelPipeHarness)
  private val perf = Module(new GpuPerfCounters)
  private val completions = Module(new Arbiter(new GpuCompletion, 4))
  private val completionGap = RegInit(false.B)
  private val headValidated = RegInit(false.B)
  private val headCommand = Reg(new GpuCommand)
  private val headError = Reg(UInt(8.W))

  queue.io.enq <> io.command
  validator.io.command := queue.io.deq.bits
  when(queue.io.deq.valid && !headValidated) {
    headCommand := queue.io.deq.bits
    headError := validator.io.error
    headValidated := true.B
  }

  private val headValid = queue.io.deq.valid && headValidated
  private val dense = headCommand.op === GpuOpcode.Fill.U ||
    headCommand.op === GpuOpcode.Copy.U ||
    headCommand.op === GpuOpcode.ColorKey.U ||
    headCommand.op === GpuOpcode.Alpha.U
  private val present = headCommand.op === GpuOpcode.Present.U
  private val sparseOp = headCommand.op === GpuOpcode.Sparse.U
  private val rejected = headError =/= GpuError.None.U || !(dense || sparseOp || present)

  private val engineIdle = blit.io.command.ready && sparse.io.command.ready && swap.io.present.ready
  completions.io.in(0).valid := headValid && rejected && engineIdle && !completionGap
  completions.io.in(0).bits.tag := headCommand.tag
  completions.io.in(0).bits.error := Mux(
    headError === GpuError.None.U,
    GpuError.InvalidOpcode.U,
    headError
  )

  blit.io.command.valid := headValid && dense && headError === GpuError.None.U &&
    sparse.io.command.ready && swap.io.present.ready && !completionGap
  blit.io.command.bits := headCommand
  sparse.io.command.valid := headValid && sparseOp && headError === GpuError.None.U &&
    blit.io.command.ready && swap.io.present.ready && !completionGap
  sparse.io.command.bits := headCommand
  swap.io.present.valid := headValid && present && headError === GpuError.None.U &&
    blit.io.command.ready && sparse.io.command.ready && !completionGap
  swap.io.present.bits := headCommand
  private val headReady = Mux(
    rejected,
    completions.io.in(0).ready && engineIdle && !completionGap,
    Mux(present, swap.io.present.ready, Mux(sparseOp, sparse.io.command.ready, blit.io.command.ready)) &&
      engineIdle && !completionGap
  )
  queue.io.deq.ready := headValid && headReady
  when(queue.io.deq.fire) { headValidated := false.B }

  completions.io.in(1).valid := blit.io.completion.valid && !completionGap
  completions.io.in(1).bits := blit.io.completion.bits
  blit.io.completion.ready := completions.io.in(1).ready && !completionGap
  completions.io.in(2).valid := sparse.io.completion.valid && !completionGap
  completions.io.in(2).bits := sparse.io.completion.bits
  sparse.io.completion.ready := completions.io.in(2).ready && !completionGap
  completions.io.in(3).valid := swap.io.completion.valid && !completionGap
  completions.io.in(3).bits := swap.io.completion.bits
  swap.io.completion.ready := completions.io.in(3).ready && !completionGap
  io.completion <> completions.io.out
  completionGap := io.completion.fire
  swap.io.vblank := io.vblank
  pixel.io.input <> blit.io.pixelRequest
  blit.io.pixelResult <> pixel.io.output

  private val useSparse = sparse.io.busy
  io.axi.aw.valid := Mux(useSparse, sparse.io.axi.aw.valid, blit.io.axi.aw.valid)
  io.axi.aw.bits := Mux(useSparse, sparse.io.axi.aw.bits, blit.io.axi.aw.bits)
  sparse.io.axi.aw.ready := io.axi.aw.ready && useSparse
  blit.io.axi.aw.ready := io.axi.aw.ready && !useSparse
  io.axi.w.valid := Mux(useSparse, sparse.io.axi.w.valid, blit.io.axi.w.valid)
  io.axi.w.bits := Mux(useSparse, sparse.io.axi.w.bits, blit.io.axi.w.bits)
  sparse.io.axi.w.ready := io.axi.w.ready && useSparse
  blit.io.axi.w.ready := io.axi.w.ready && !useSparse
  sparse.io.axi.b.valid := io.axi.b.valid && useSparse
  sparse.io.axi.b.bits := io.axi.b.bits
  blit.io.axi.b.valid := io.axi.b.valid && !useSparse
  blit.io.axi.b.bits := io.axi.b.bits
  io.axi.b.ready := Mux(useSparse, sparse.io.axi.b.ready, blit.io.axi.b.ready)
  io.axi.ar.valid := Mux(useSparse, sparse.io.axi.ar.valid, blit.io.axi.ar.valid)
  io.axi.ar.bits := Mux(useSparse, sparse.io.axi.ar.bits, blit.io.axi.ar.bits)
  sparse.io.axi.ar.ready := io.axi.ar.ready && useSparse
  blit.io.axi.ar.ready := io.axi.ar.ready && !useSparse
  sparse.io.axi.r.valid := io.axi.r.valid && useSparse
  sparse.io.axi.r.bits := io.axi.r.bits
  blit.io.axi.r.valid := io.axi.r.valid && !useSparse
  blit.io.axi.r.bits := io.axi.r.bits
  io.axi.r.ready := Mux(useSparse, sparse.io.axi.r.ready, blit.io.axi.r.ready)

  io.busy := !queue.io.empty || headValidated || !blit.io.command.ready || sparse.io.busy ||
    swap.io.pending || io.completion.valid
  private val axiStalled =
    (io.axi.aw.valid && !io.axi.aw.ready) ||
      (io.axi.w.valid && !io.axi.w.ready) ||
      (io.axi.b.valid && !io.axi.b.ready) ||
      (io.axi.ar.valid && !io.axi.ar.ready) ||
      (io.axi.r.valid && !io.axi.r.ready)
  private val pixelStalled =
    (blit.io.pixelRequest.valid && !blit.io.pixelRequest.ready) ||
      (blit.io.pixelResult.valid && !blit.io.pixelResult.ready)
  perf.io.clear := io.perfClear
  perf.io.active := io.busy
  perf.io.pixelDone := blit.io.pixelResult.fire || sparse.io.pixelDone
  perf.io.readBeat := io.axi.r.fire
  perf.io.writeStrobe := Mux(io.axi.w.fire, io.axi.w.bits.strb, 0.U)
  perf.io.stalled := io.busy && (axiStalled || pixelStalled)
  perf.io.underflow := io.underflowPulse
  perf.io.renderGrant := io.renderGrant
  perf.io.scanoutGrant := io.scanoutGrant
  io.perfCycles := perf.io.cycles
  io.perfPixels := perf.io.pixels
  io.perfReadBytes := perf.io.readBytes
  io.perfWriteBytes := perf.io.writeBytes
  io.perfStalls := perf.io.stalls
  io.perfUnderflows := perf.io.underflows
  io.perfRenderGrants := perf.io.renderGrants
  io.perfScanoutGrants := perf.io.scanoutGrants
  dontTouch(perf.io.cycles)
  dontTouch(perf.io.pixels)
  dontTouch(perf.io.readBytes)
  dontTouch(perf.io.writeBytes)
  dontTouch(perf.io.stalls)
  dontTouch(perf.io.underflows)
  dontTouch(perf.io.renderGrants)
  dontTouch(perf.io.scanoutGrants)
  io.queueLevel := queue.io.level
  io.queueHighWater := queue.io.highWater
  io.queueFull := queue.io.full
  io.queueEmpty := queue.io.empty
  io.frontBase := swap.io.frontBase
  io.backBase := swap.io.backBase
  io.swapPending := swap.io.pending
}
