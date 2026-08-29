package soc

import java.nio.file.Paths
import chisel3.simulator.{Randomization, Settings}
import org.scalatest.funspec.AnyFunSpec
import org.scalatest.matchers.should.Matchers
import testutil.StableChiselSim

class SoftwareDriverSpec extends AnyFunSpec with StableChiselSim with Matchers {
  describe("bare-metal C accelerator driver") {
    it("writes and reads back the accelerator registers") {
      val ramImage = Paths.get("../sw/build/driver_test.hex").toAbsolutePath.toString
      val settings = Settings.default[SoCTop].copy(randomization = Randomization.uninitialized)
      simulate(new SoCTop(
        ramInitFile = Some(ramImage),
        videoSourcePath = "../rtl/video/VideoAccelTop.v"
      ), settings = settings) { dut =>
        dut.io.video.pixelIn.poke(0)
        dut.io.video.pixelInValid.poke(false)
        dut.io.uartTx.ready.poke(true)

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

        dut.io.halted.expect(true)
        withClue(s"cycles=$cycles uart=$uartBytes trap=$trapCause") {
          uartBytes shouldBe Vector(80)
          trapCause shouldBe Some(3)
        }
        dut.io.accelEnable.expect(true)
        dut.io.accelMode.expect(2)
        dut.io.accelThreshold.expect(128)
        dut.io.accelBypass.expect(false)
      }
    }
  }
}
