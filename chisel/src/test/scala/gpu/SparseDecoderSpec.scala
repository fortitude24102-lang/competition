package gpu

import chisel3._
import org.scalatest.funspec.AnyFunSpec
import org.scalatest.matchers.should.Matchers
import testutil.StableChiselSim

class SparseDecoderSpec extends AnyFunSpec with StableChiselSim with Matchers {
  private case class Event(x: Int, y: Int, pixel: Int, write: Boolean, rowLast: Boolean)

  private def decode(width: Int, height: Int, words: Seq[BigInt]): (Seq[Event], Boolean) = {
    var result = Seq.empty[Event]
    var failed = false
    simulate(new SparseDecoder) { dut =>
      dut.io.start.valid.poke(true)
      dut.io.start.bits.widthPixels.poke(width)
      dut.io.start.bits.heightPixels.poke(height)
      dut.io.input.valid.poke(false)
      dut.io.input.bits.poke(0)
      dut.io.output.ready.poke(false)
      dut.io.abort.poke(false)
      dut.clock.step()
      dut.io.start.valid.poke(false)

      val random = new scala.util.Random(0x5a125L)
      var inputIndex = 0
      var cycles = 0
      while (cycles < 300 && !dut.io.done.peek().litToBoolean) {
        val offer = inputIndex < words.size && random.nextBoolean()
        dut.io.input.valid.poke(offer)
        if (inputIndex < words.size) dut.io.input.bits.poke(words(inputIndex))
        dut.io.output.ready.poke(random.nextBoolean())

        val inputFire = dut.io.input.valid.peek().litToBoolean && dut.io.input.ready.peek().litToBoolean
        val outputFire = dut.io.output.valid.peek().litToBoolean && dut.io.output.ready.peek().litToBoolean
        if (outputFire) {
          result :+= Event(
            dut.io.output.bits.x.peek().litValue.toInt,
            dut.io.output.bits.y.peek().litValue.toInt,
            dut.io.output.bits.pixel.peek().litValue.toInt,
            dut.io.output.bits.writeEnable.peek().litToBoolean,
            dut.io.output.bits.rowLast.peek().litToBoolean
          )
        }
        dut.clock.step()
        if (inputFire) inputIndex += 1
        cycles += 1
      }
      dut.io.done.expect(true)
      failed = dut.io.error.peek().litToBoolean
    }
    result -> failed
  }

  describe("SparseDecoder") {
    it("decodes odd literal runs, row boundaries, and an all-transparent row under backpressure") {
      val words = Seq(
        BigInt("00030001", 16), // skip 1, run 3
        BigInt("22221111", 16),
        BigInt("00003333", 16), // odd-run padding must be zero
        BigInt("00000001", 16), // trailing skip 1, row end
        BigInt("00000005", 16)  // all-transparent row
      )
      val (events, failed) = decode(width = 5, height = 2, words)
      failed shouldBe false
      events shouldBe Seq(
        Event(1, 0, 0x1111, write = true, rowLast = false),
        Event(2, 0, 0x2222, write = true, rowLast = false),
        Event(3, 0, 0x3333, write = true, rowLast = false),
        Event(5, 0, 0, write = false, rowLast = true),
        Event(5, 1, 0, write = false, rowLast = true)
      )
    }

    it("rejects a run crossing the row, an early row end, and non-zero odd-run padding") {
      decode(5, 1, Seq(BigInt("00020004", 16)))._2 shouldBe true
      decode(5, 1, Seq(BigInt("00000004", 16)))._2 shouldBe true
      decode(1, 1, Seq(BigInt("00010000", 16), BigInt("abcd1234", 16)))._2 shouldBe true
    }
  }
}
