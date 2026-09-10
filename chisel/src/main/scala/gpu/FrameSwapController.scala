package gpu

import chisel3._
import chisel3.util._

/** Applies one queued PRESENT only on the synchronized vblank pulse. */
class FrameSwapController extends Module {
  val io = IO(new Bundle {
    val present = Flipped(Decoupled(new GpuCommand))
    val vblank = Input(Bool())
    val completion = Decoupled(new GpuCompletion)
    val frontBase = Output(UInt(32.W))
    val backBase = Output(UInt(32.W))
    val pending = Output(Bool())
  })

  private val frontBase = RegInit(GpuMemoryMap.FramebufferA.U(32.W))
  private val backBase = RegInit(GpuMemoryMap.FramebufferB.U(32.W))
  private val pending = RegInit(false.B)
  private val pendingBase = Reg(UInt(32.W))
  private val pendingTag = Reg(UInt(16.W))
  private val completionValid = RegInit(false.B)
  private val completionTag = Reg(UInt(16.W))

  io.present.ready := !pending && !completionValid
  when(io.present.fire) {
    pendingBase := io.present.bits.dstAddr
    pendingTag := io.present.bits.tag
    pending := true.B
  }

  when(pending && io.vblank && !completionValid) {
    when(pendingBase =/= frontBase) {
      backBase := frontBase
      frontBase := pendingBase
    }
    completionTag := pendingTag
    completionValid := true.B
    pending := false.B
  }

  io.completion.valid := completionValid
  io.completion.bits.tag := completionTag
  io.completion.bits.error := GpuError.None.U
  when(io.completion.fire) { completionValid := false.B }

  io.frontBase := frontBase
  io.backBase := backBase
  io.pending := pending
}
