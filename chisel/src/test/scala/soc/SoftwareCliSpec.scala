package soc

import java.nio.file.Paths
import chisel3.simulator.{Randomization, Settings}
import org.scalatest.funspec.AnyFunSpec
import org.scalatest.matchers.should.Matchers
import testutil.StableChiselSim

class SoftwareCliSpec extends AnyFunSpec with StableChiselSim with Matchers {
  describe("bare-metal control CLI") {
    it("accepts a threshold command and rejects an out-of-range value") {
      val ramImage = Paths.get("../sw/build/cli.hex").toAbsolutePath.toString
      val settings = Settings.default[SoCTop].copy(randomization = Randomization.uninitialized)

      simulate(new SoCTop(
        ramInitFile = Some(ramImage),
        videoSourcePath = "../rtl/video/VideoAccelTop.v"
      ), settings = settings) { dut =>
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

        var received = Vector.empty[Int]

        def step(): Unit = {
          if (dut.io.uartTx.valid.peek().litToBoolean) {
            received :+= dut.io.uartTx.bits.peek().litValue.toInt
          }
          dut.clock.step()
        }

        def waitForSuffix(suffix: String, limit: Int = 20000): Unit = {
          val expected = suffix.getBytes("US-ASCII").toVector.map(_.toInt)
          var cycles = 0
          while (!received.endsWith(expected) && cycles < limit) {
            step()
            cycles += 1
          }
          withClue(s"suffix=$suffix cycles=$cycles received=${received.map(_.toChar).mkString}") {
            received.endsWith(expected) shouldBe true
          }
        }

        def send(text: String): Unit = {
          text.getBytes("US-ASCII").foreach { byte =>
            dut.io.uartRx.bits.poke(byte & 0xff)
            dut.io.uartRx.valid.poke(true)
            while (!dut.io.uartRx.ready.peek().litToBoolean) step()
            step()
            dut.io.uartRx.valid.poke(false)
          }
        }

        def exchange(command: String, suffix: String): String = {
          received = Vector.empty
          send(command + "\n")
          waitForSuffix(suffix)
          received.map(_.toChar).mkString
        }

        waitForSuffix("READY\n")
        exchange("help", "help status mode threshold bypass enable perf\n")
        exchange("threshold 42", "OK\n")
        dut.io.accelThreshold.expect(42)

        exchange("mode 1", "OK\n")
        dut.io.accelMode.expect(1)
        exchange("bypass off", "OK\n")
        dut.io.accelBypass.expect(false)
        exchange("enable on", "OK\n")
        dut.io.accelEnable.expect(true)

        exchange("status", "enable=1 mode=1 threshold=42 bypass=0\n")
        exchange("perf clear", "OK\n")
        val perf = exchange("perf", "busy=0\n")
        perf should include("cycle=")
        perf should include(" input=0 output=0 frame=0 stall=0 busy=0\n")

        exchange("threshold 999", "ERR\n")
        dut.io.accelThreshold.expect(42)
      }
    }
  }
}
