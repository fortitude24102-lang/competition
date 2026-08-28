package soc

import chisel3._
import org.scalatest.funspec.AnyFunSpec
import org.scalatest.matchers.should.Matchers
import testutil.StableChiselSim

private class VideoAccelHarness(sourcePath: String) extends Module {
  val io = IO(new Bundle {
    val pixelIn = Input(UInt(24.W))
    val pixelInValid = Input(Bool())
    val enable = Input(Bool())
    val mode = Input(UInt(2.W))
    val threshold = Input(UInt(8.W))
    val bypass = Input(Bool())
    val pixelOut = Output(UInt(24.W))
    val pixelOutValid = Output(Bool())
    val busy = Output(Bool())
    val frameDone = Output(Bool())
  })

  private val accelerator = Module(new VideoAccelExt(sourcePath))
  accelerator.clock := clock
  accelerator.reset := reset.asBool
  accelerator.pixel_in := io.pixelIn
  accelerator.pixel_in_valid := io.pixelInValid
  accelerator.enable := io.enable
  accelerator.mode := io.mode
  accelerator.threshold := io.threshold
  accelerator.bypass := io.bypass
  io.pixelOut := accelerator.pixel_out
  io.pixelOutValid := accelerator.pixel_out_valid
  io.busy := accelerator.busy
  io.frameDone := accelerator.frame_done
}

class VideoAccelExtSpec extends AnyFunSpec with StableChiselSim with Matchers {
  describe("VideoAccelExt") {
    it("compiles the real Verilog and processes bypass, gray, and threshold pixels") {
      simulate(new VideoAccelHarness("../rtl/video/VideoAccelTop.v")) { dut =>
        dut.io.pixelIn.poke(0)
        dut.io.pixelInValid.poke(false)
        dut.io.enable.poke(true)
        dut.io.mode.poke(0)
        dut.io.threshold.poke(0x80)
        dut.io.bypass.poke(true)
        dut.clock.step()

        def pulse(mode: Int, threshold: Int, bypass: Boolean, expected: BigInt): Unit = {
          dut.io.mode.poke(mode)
          dut.io.threshold.poke(threshold)
          dut.io.bypass.poke(bypass)
          dut.io.pixelIn.poke(0x336699)
          dut.io.pixelInValid.poke(true)
          dut.io.pixelOutValid.expect(false)
          dut.clock.step()
          dut.io.pixelOutValid.expect(true)
          dut.io.pixelOut.expect(expected)
          dut.io.frameDone.expect(true)
          dut.io.pixelInValid.poke(false)
          dut.clock.step()
          dut.io.pixelOutValid.expect(false)
          dut.io.frameDone.expect(false)
        }

        pulse(mode = 0, threshold = 0x80, bypass = true, expected = 0x336699)
        pulse(mode = 1, threshold = 0x80, bypass = false, expected = 0x666666)
        pulse(mode = 2, threshold = 0x80, bypass = false, expected = 0x000000)
        pulse(mode = 2, threshold = 0x40, bypass = false, expected = 0xffffff)
      }
    }
  }
}
