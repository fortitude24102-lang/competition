package soc

import java.nio.file.Paths
import chisel3.simulator.{Randomization, Settings}
import org.scalatest.funspec.AnyFunSpec
import org.scalatest.matchers.should.Matchers
import testutil.StableChiselSim

class SoCTopSmokeSpec extends AnyFunSpec with StableChiselSim with Matchers {
  describe("SoCTop") {
    it("runs RV32I software through MMIO and reports pass over UART") {
      val ramImage = Paths.get("src/test/resources/soc/smoke.hex").toAbsolutePath.toString
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

        var uartBytes = Vector.empty[Int]
        var trapCause = Option.empty[Int]
        var trapPc = Option.empty[BigInt]
        var trapInst = Option.empty[BigInt]
        var cycles = 0
        while (!dut.io.halted.peek().litToBoolean && cycles < 2000) {
          if (dut.io.uartTx.valid.peek().litToBoolean) {
            uartBytes :+= dut.io.uartTx.bits.peek().litValue.toInt
          }
          if (dut.io.trap.valid.peek().litToBoolean) {
            trapCause = Some(dut.io.trap.cause.peek().litValue.toInt)
            trapPc = Some(dut.io.trap.pc.peek().litValue)
            trapInst = Some(dut.io.trap.inst.peek().litValue)
          }
          dut.clock.step()
          cycles += 1
        }

        if (dut.io.uartTx.valid.peek().litToBoolean) {
          uartBytes :+= dut.io.uartTx.bits.peek().litValue.toInt
        }

        dut.io.halted.expect(true)
        val state = s"cycles=$cycles uart=$uartBytes trap=$trapCause/$trapPc/$trapInst " +
          s"controls=${dut.io.accelEnable.peek().litValue}/" +
          s"${dut.io.accelMode.peek().litValue}/" +
          s"${dut.io.accelThreshold.peek().litValue}/" +
          s"${dut.io.accelBypass.peek().litValue}"
        withClue(state) {
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
