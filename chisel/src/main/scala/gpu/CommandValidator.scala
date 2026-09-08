package gpu

import chisel3._

class CommandValidator extends Module {
  val io = IO(new Bundle {
    val command = Input(new GpuCommand)
    val valid = Output(Bool())
    val error = Output(UInt(8.W))
  })

  private val command = io.command
  private val renderOp = command.op >= GpuOpcode.Fill.U && command.op <= GpuOpcode.Sparse.U
  private val denseSourceOp = command.op === GpuOpcode.Copy.U ||
    command.op === GpuOpcode.ColorKey.U || command.op === GpuOpcode.Alpha.U
  private val sourceOp = denseSourceOp || command.op === GpuOpcode.Sparse.U
  private val destinationOp = renderOp || command.op === GpuOpcode.Present.U
  private val legalOpcode = command.op <= GpuOpcode.Max.U

  private val rowBytes = (command.widthPixels << 1).pad(64)
  private val rowsBeforeLast = (command.heightPixels - 1.U).pad(64)
  private val srcEnd = command.srcAddr.pad(64) + rowsBeforeLast * command.srcStride.pad(64) + rowBytes
  private val dstEnd = command.dstAddr.pad(64) + rowsBeforeLast * command.dstStride.pad(64) + rowBytes
  private val ddrBase = GpuMemoryMap.FramebufferA.U(64.W)
  private val ddrEnd = GpuMemoryMap.DdrEndExclusive.U(64.W)

  private val zeroSize = renderOp && (command.widthPixels === 0.U || command.heightPixels === 0.U)
  private val multiRow = command.heightPixels > 1.U
  private val misaligned = (sourceOp && (command.srcAddr(0) || (multiRow && command.srcStride(0)))) ||
    (destinationOp && (command.dstAddr(0) || (multiRow && command.dstStride(0))))
  private val strideTooSmall = (renderOp && command.dstStride < rowBytes) ||
    (denseSourceOp && command.srcStride < rowBytes)
  private val srcOutOfRange = sourceOp &&
    (command.srcAddr.pad(64) < ddrBase || srcEnd > ddrEnd || srcEnd <= command.srcAddr.pad(64))
  private val dstOutOfRange = destinationOp &&
    (command.dstAddr.pad(64) < ddrBase || dstEnd > ddrEnd || dstEnd <= command.dstAddr.pad(64))
  private val overlap = command.op === GpuOpcode.Copy.U &&
    command.srcAddr.pad(64) < dstEnd && command.dstAddr.pad(64) < srcEnd

  io.error := GpuError.None.U
  when(!legalOpcode) {
    io.error := GpuError.InvalidOpcode.U
  }.elsewhen(zeroSize) {
    io.error := GpuError.ZeroSize.U
  }.elsewhen(misaligned) {
    io.error := GpuError.MisalignedAddress.U
  }.elsewhen(strideTooSmall) {
    io.error := GpuError.StrideTooSmall.U
  }.elsewhen(srcOutOfRange || dstOutOfRange) {
    io.error := GpuError.AddressRange.U
  }.elsewhen(overlap) {
    io.error := GpuError.OverlappingCopy.U
  }
  io.valid := io.error === GpuError.None.U
}
