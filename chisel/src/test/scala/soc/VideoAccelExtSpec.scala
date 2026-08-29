package soc

import scala.io.Source
import chisel3._
import chisel3.util._
import org.scalatest.funspec.AnyFunSpec
import org.scalatest.matchers.should.Matchers
import testutil.StableChiselSim

private case class VideoFixtureBeat(
  pixel: BigInt,
  startOfFrame: Boolean,
  endOfLine: Boolean,
  endOfFrame: Boolean,
  expected: BigInt
)

private class VideoAccelHarness(sourcePath: String) extends Module {
  val io = IO(new Bundle {
    val input = Flipped(Decoupled(new StreamBeat(24)))
    val output = Decoupled(new StreamBeat(24))
    val enable = Input(Bool())
    val mode = Input(UInt(2.W))
    val threshold = Input(UInt(8.W))
    val bypass = Input(Bool())
    val busy = Output(Bool())
    val frameDone = Output(Bool())
  })

  private val accelerator = Module(new VideoAccelExt(sourcePath))
  accelerator.clock := clock
  accelerator.reset := reset.asBool
  accelerator.pixel_in := io.input.bits.data
  accelerator.pixel_in_valid := io.input.valid
  io.input.ready := accelerator.pixel_in_ready
  accelerator.pixel_in_start_of_frame := io.input.bits.startOfFrame
  accelerator.pixel_in_end_of_line := io.input.bits.endOfLine
  accelerator.pixel_in_end_of_frame := io.input.bits.endOfFrame
  accelerator.enable := io.enable
  accelerator.mode := io.mode
  accelerator.threshold := io.threshold
  accelerator.bypass := io.bypass
  io.output.bits.data := accelerator.pixel_out
  io.output.valid := accelerator.pixel_out_valid
  accelerator.pixel_out_ready := io.output.ready
  io.output.bits.startOfFrame := accelerator.pixel_out_start_of_frame
  io.output.bits.endOfLine := accelerator.pixel_out_end_of_line
  io.output.bits.endOfFrame := accelerator.pixel_out_end_of_frame
  io.busy := accelerator.busy
  io.frameDone := accelerator.frame_done
}

class VideoAccelExtSpec extends AnyFunSpec with StableChiselSim with Matchers {
  private def loadFixture(): Vector[VideoFixtureBeat] = {
    val source = Source.fromFile("src/test/resources/video/threshold_frame.csv")
    try {
      source.getLines().drop(1).filter(_.nonEmpty).map { line =>
        val fields = line.split(",")
        VideoFixtureBeat(
          pixel = BigInt(fields(0), 16),
          startOfFrame = fields(1) == "1",
          endOfLine = fields(2) == "1",
          endOfFrame = fields(3) == "1",
          expected = BigInt(fields(4), 16)
        )
      }.toVector
    } finally {
      source.close()
    }
  }

  describe("VideoAccelExt") {
    it("preserves every file-driven beat and frame marker under backpressure") {
      val fixture = loadFixture()
      simulate(new VideoAccelHarness("../rtl/video/VideoAccelTop.v")) { dut =>
        dut.io.input.valid.poke(false)
        dut.io.input.bits.data.poke(0)
        dut.io.input.bits.startOfFrame.poke(false)
        dut.io.input.bits.endOfLine.poke(false)
        dut.io.input.bits.endOfFrame.poke(false)
        dut.io.output.ready.poke(true)
        dut.io.enable.poke(true)
        dut.io.mode.poke(2)
        dut.io.threshold.poke(0x80)
        dut.io.bypass.poke(false)
        dut.clock.step()

        var inputIndex = 0
        var outputIndex = 0
        var secondBeatStalls = 0
        var cycles = 0

        while (outputIndex < fixture.length && cycles < 40) {
          if (inputIndex < fixture.length) {
            val beat = fixture(inputIndex)
            dut.io.input.valid.poke(true)
            dut.io.input.bits.data.poke(beat.pixel)
            dut.io.input.bits.startOfFrame.poke(beat.startOfFrame)
            dut.io.input.bits.endOfLine.poke(beat.endOfLine)
            dut.io.input.bits.endOfFrame.poke(beat.endOfFrame)
          } else {
            dut.io.input.valid.poke(false)
          }

          val stallSecond = outputIndex == 1 && secondBeatStalls < 2
          dut.io.output.ready.poke(!stallSecond)

          val inputFire = dut.io.input.valid.peek().litToBoolean &&
            dut.io.input.ready.peek().litToBoolean
          val outputValid = dut.io.output.valid.peek().litToBoolean
          val outputFire = outputValid && dut.io.output.ready.peek().litToBoolean

          if (outputValid) {
            val expected = fixture(outputIndex)
            dut.io.output.bits.data.expect(expected.expected)
            dut.io.output.bits.startOfFrame.expect(expected.startOfFrame)
            dut.io.output.bits.endOfLine.expect(expected.endOfLine)
            dut.io.output.bits.endOfFrame.expect(expected.endOfFrame)
            dut.io.busy.expect(true)
          }

          if (outputValid && !dut.io.output.ready.peek().litToBoolean) {
            secondBeatStalls += 1
          }

          val expectFrameDone = outputFire && fixture(outputIndex).endOfFrame
          if (inputFire) inputIndex += 1
          if (outputFire) outputIndex += 1
          dut.clock.step()
          dut.io.frameDone.expect(expectFrameDone)
          cycles += 1
        }

        withClue(s"cycles=$cycles inputIndex=$inputIndex outputIndex=$outputIndex stalls=$secondBeatStalls") {
          inputIndex shouldBe fixture.length
          outputIndex shouldBe fixture.length
          secondBeatStalls shouldBe 2
        }
      }
    }
  }
}
