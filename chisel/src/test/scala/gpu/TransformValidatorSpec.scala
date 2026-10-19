package gpu

import chisel3._
import org.scalatest.funspec.AnyFunSpec
import testutil.StableChiselSim

class TransformValidatorSpec extends AnyFunSpec with StableChiselSim {
  it("validates explicit source dimensions and complete rectangles before dispatch") {
    simulate(new CommandValidator(enableTransformBlit = true)) { dut =>
      def check(width: Int = 2, height: Int = 2, flags: Int = 0,
                srcWidth: Int = 2, srcHeight: Int = 2,
                src: BigInt = GpuMemoryMap.DenseAssets, dst: BigInt = GpuMemoryMap.FramebufferA,
                srcStride: BigInt = 16, dstStride: BigInt = 16, error: Int = 0): Unit = {
        val c = dut.io.command
        c.op.poke(7)
        c.srcAddr.poke(src)
        c.dstAddr.poke(dst)
        c.widthPixels.poke(width)
        c.heightPixels.poke(height)
        c.srcWidthPixels.poke(srcWidth)
        c.srcHeightPixels.poke(srcHeight)
        c.srcStride.poke(srcStride)
        c.dstStride.poke(dstStride)
        c.color.poke(0)
        c.colorKey.poke(0)
        c.alpha.poke(255)
        c.flags.poke(flags)
        c.tag.poke(0)
        withClue(s"output=${width}x$height source=${srcWidth}x$srcHeight flags=$flags src=$src dst=$dst: ") {
          dut.io.error.expect(error)
          dut.io.valid.expect(error == 0)
        }
      }
      check()
      check(flags = GpuTransformFlags.Mask)
      check(width = 5, height = 3, srcWidth = 3, srcHeight = 2)
      check(width = 3, height = 2, srcWidth = 4, srcHeight = 3)
      check(width = 0, error = GpuError.ZeroSize)
      check(height = 0, error = GpuError.ZeroSize)
      check(srcWidth = 0, error = GpuError.ZeroSize)
      check(srcHeight = 0, error = GpuError.ZeroSize)
      check(flags = 32)
      check(flags = 51)
      check(flags = 64, error = 10)
      check(flags = 0x8000, error = 10)
      check(flags = 12, error = 10)
      check(flags = 4, error = 10)
      check(flags = 8, error = 10)
      check(src = GpuMemoryMap.DenseAssets + 1, error = GpuError.MisalignedAddress)
      check(dst = GpuMemoryMap.FramebufferA + 1, error = GpuError.MisalignedAddress)
      check(srcStride = 5, error = GpuError.MisalignedAddress)
      check(dstStride = 5, error = GpuError.MisalignedAddress)
      check(srcWidth = 4, srcStride = 6, error = GpuError.StrideTooSmall)
      check(dstStride = 2, error = GpuError.StrideTooSmall)
      check(srcHeight = 1, srcStride = 3, error = GpuError.MisalignedAddress)
      check(height = 1, srcStride = 5, error = GpuError.MisalignedAddress)
      check(height = 1, dstStride = 5, error = GpuError.MisalignedAddress)
      check(src = GpuMemoryMap.FramebufferA - 2, error = GpuError.AddressRange)
      check(dst = GpuMemoryMap.FramebufferA - 2, error = GpuError.AddressRange)
      check(srcWidth = 4, srcHeight = 4, src = GpuMemoryMap.DdrEndExclusive - 20, srcStride = 8,
        error = GpuError.AddressRange)
      check(dst = GpuMemoryMap.DdrEndExclusive - 16, error = GpuError.AddressRange)
      check(srcStride = BigInt("fffffffe", 16), error = GpuError.AddressRange)
      check(dstStride = BigInt("fffffffe", 16), error = GpuError.AddressRange)
      check(width = 1, height = 1, srcWidth = 1, srcHeight = 1,
        src = GpuMemoryMap.DdrEndExclusive - 2, srcStride = 2)
      check(width = 1, height = 1, dst = GpuMemoryMap.DdrEndExclusive - 2, dstStride = 2)
      check(width = 1, height = 1, srcWidth = 65535, srcHeight = 1, srcStride = 131070, dstStride = 2)
      check(width = 1, height = 1, srcWidth = 1, srcHeight = 65535, srcStride = 2, dstStride = 2)
      check(width = 65535, height = 1, srcWidth = 1, srcHeight = 1, srcStride = 2, dstStride = 131070)
      check(src = GpuMemoryMap.FramebufferA, dst = GpuMemoryMap.FramebufferA,
        error = GpuError.OverlappingCopy)
      check(srcWidth = 4, srcHeight = 4, src = GpuMemoryMap.FramebufferA, dst = GpuMemoryMap.FramebufferA + 24,
        srcStride = 8, error = GpuError.OverlappingCopy)
      check(src = GpuMemoryMap.FramebufferA + 16, dst = GpuMemoryMap.FramebufferA,
        srcStride = 4, dstStride = 16, error = GpuError.OverlappingCopy)
      check(width = 2, height = 1, src = GpuMemoryMap.FramebufferA,
        srcHeight = 1, dst = GpuMemoryMap.FramebufferA + 4, srcStride = 4, dstStride = 4)
    }
  }

  it("rejects Transform by default while preserving legacy single-row alignment rules") {
    simulate(new CommandValidator) { dut =>
      val c = dut.io.command
      c.op.poke(GpuOpcode.Transform)
      c.srcAddr.poke(GpuMemoryMap.DenseAssets)
      c.dstAddr.poke(GpuMemoryMap.FramebufferA)
      c.widthPixels.poke(1)
      c.heightPixels.poke(1)
      c.srcWidthPixels.poke(1)
      c.srcHeightPixels.poke(1)
      c.srcStride.poke(2)
      c.dstStride.poke(2)
      c.color.poke(0)
      c.colorKey.poke(0)
      c.alpha.poke(255)
      c.flags.poke(0)
      c.tag.poke(0)
      dut.io.error.expect(GpuError.InvalidOpcode)
      dut.io.valid.expect(false)
      c.op.poke(GpuOpcode.Copy)
      c.srcStride.poke(3)
      c.dstStride.poke(3)
      c.srcWidthPixels.poke(0)
      c.srcHeightPixels.poke(0)
      dut.io.error.expect(GpuError.None)
      dut.io.valid.expect(true)
    }
  }
}
