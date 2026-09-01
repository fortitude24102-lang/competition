package soc

import java.nio.file.Paths
import chisel3.simulator.{Randomization, Settings}
import org.scalatest.funspec.AnyFunSpec
import org.scalatest.matchers.should.Matchers
import testutil.StableChiselSim

class SoftwareDriverSpec extends AnyFunSpec with StableChiselSim with Matchers {
  private def runImage(imageName: String): (Vector[Int], Option[Int]) = {
    val ramImage = Paths.get(s"../sw/build/$imageName").toAbsolutePath.toString
    val settings = Settings.default[SoCTop].copy(randomization = Randomization.uninitialized)
    var result = (Vector.empty[Int], Option.empty[Int])

    simulate(new SoCTop(
      ramInitFile = Some(ramImage),
      videoSourcePath = "../rtl/video/VideoAccelTop.v"
    ), settings = settings) { dut =>
      dut.io.gpioInput.poke(0)
      dut.io.video.input.valid.poke(false)
      dut.io.video.input.bits.data.poke(0)
      dut.io.video.input.bits.startOfFrame.poke(false)
      dut.io.video.input.bits.endOfLine.poke(false)
      dut.io.video.input.bits.endOfFrame.poke(false)
      dut.io.video.output.ready.poke(true)
      dut.io.uartTx.ready.poke(true)
      dut.io.uartRx.valid.poke(false)
      dut.io.uartRx.bits.poke(0)

      Seq(dut.io.externalImem, dut.io.externalDmem).foreach { bus =>
        bus.req.ready.poke(true)
        bus.resp.valid.poke(true)
        bus.resp.bits.rdata.poke(0)
        bus.resp.bits.error.poke(true)
      }

      var uartBytes = Vector.empty[Int]
      var trapCause = Option.empty[Int]
      var cycles = 0
      while (!dut.io.halted.peek().litToBoolean && cycles < 2000) {
        if (dut.io.uartTx.valid.peek().litToBoolean) {
          uartBytes :+= dut.io.uartTx.bits.peek().litValue.toInt
        }
        if (dut.io.trap.valid.peek().litToBoolean) {
          trapCause = Some(dut.io.trap.cause.peek().litValue.toInt)
        }
        dut.clock.step()
        cycles += 1
      }

      if (dut.io.uartTx.valid.peek().litToBoolean) {
        uartBytes :+= dut.io.uartTx.bits.peek().litValue.toInt
      }

      withClue(s"image=$imageName cycles=$cycles uart=$uartBytes trap=$trapCause") {
        dut.io.halted.expect(true)
        dut.io.accelEnable.expect(true)
        dut.io.accelMode.expect(2)
        dut.io.accelThreshold.expect(128)
        dut.io.accelBypass.expect(false)
      }
      result = (uartBytes, trapCause)
    }
    result
  }

  describe("bare-metal C accelerator driver") {
    it("writes and reads back the accelerator registers") {
      runImage("driver_test.hex") shouldBe (Vector(80), Some(3))
    }

    it("reports F when validation fails") {
      runImage("driver_test_fail.hex") shouldBe (Vector(70), Some(3))
    }
  }
}
