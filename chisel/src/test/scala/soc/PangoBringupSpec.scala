package soc

import java.nio.file.Paths
import chisel3.simulator.{Randomization, Settings}
import org.scalatest.funspec.AnyFunSpec
import org.scalatest.matchers.should.Matchers
import testutil.StableChiselSim

class PangoBringupSpec extends AnyFunSpec with StableChiselSim with Matchers {
  describe("Pango board-independent bring-up") {
    it("runs software against GPIO and the machine timer") {
      val ramImage = Paths.get("../sw/build/pango_bringup.hex").toAbsolutePath.toString
      val settings = Settings.default[SoCTop].copy(randomization = Randomization.uninitialized)

      simulate(new SoCTop(
        ramInitFile = Some(ramImage),
        videoSourcePath = "../rtl/video/VideoAccelTop.v"
      ), settings = settings) { dut =>
        dut.io.gpioInput.poke(0x3c)
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
        while (!dut.io.halted.peek().litToBoolean && cycles < 3000) {
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

        withClue(s"cycles=$cycles uart=$uartBytes trap=$trapCause") {
          dut.io.halted.expect(true)
          uartBytes shouldBe Vector('P'.toInt)
          trapCause shouldBe Some(3)
          dut.io.gpioOutput.expect(0xa5)
          dut.io.timerInterrupt.expect(false)
        }
      }
    }
  }
}
