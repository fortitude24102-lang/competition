package gpu

import chisel3._
import chisel3.util._
import org.scalatest.funspec.AnyFunSpec
import org.scalatest.matchers.should.Matchers
import testutil.StableChiselSim

class PixelPipeExtSpec extends AnyFunSpec with StableChiselSim with Matchers {
  it("runs real Copy, Fill, and Alpha RTL and preserves pending pixels across stalls") {
    simulate(new PixelPipeHarness) { dut =>
      dut.io.input.valid.poke(false)
      dut.io.output.ready.poke(false)
      dut.io.input.bits.op.poke(0)
      dut.io.input.bits.foreground.poke(0)
      dut.io.input.bits.background.poke(0)
      dut.io.input.bits.fillColor.poke(0)
      dut.io.input.bits.colorKey.poke(0)
      dut.io.input.bits.alpha.poke(0)
      dut.clock.step()
      val beats = Seq(
        (2, 0xf800, 0x0000, 0x001f, 0, 0xf800, true),
        (1, 0xf800, 0x07e0, 0x0000, 0, 0x07e0, true),
        (4, 0xf800, 0x0000, 0x001f, 128, 0x800f, true),
        (4, 0xffff, 0x0000, 0x1234, 0, 0x1234, true)
      )
      for ((op, fg, fill, background, alpha, pixel, write) <- beats) {
        dut.io.input.valid.poke(true)
        dut.io.input.bits.op.poke(op)
        dut.io.input.bits.foreground.poke(fg)
        dut.io.input.bits.fillColor.poke(fill)
        dut.io.input.bits.background.poke(background)
        dut.io.input.bits.alpha.poke(alpha)
        dut.io.input.ready.expect(true)
        dut.clock.step()
        dut.io.input.valid.poke(false)
        for (_ <- 0 until 3) {
          dut.io.output.valid.expect(true)
          dut.io.output.bits.pixel.expect(pixel)
          dut.io.output.bits.writeEnable.expect(write)
          dut.io.input.ready.expect(false)
          dut.clock.step()
        }
        dut.io.output.ready.poke(true)
        dut.clock.step()
        dut.io.output.valid.expect(false)
        dut.io.output.ready.poke(false)
      }
    }
  }
}
