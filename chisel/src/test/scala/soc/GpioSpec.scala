package soc

import org.scalatest.funspec.AnyFunSpec
import org.scalatest.matchers.should.Matchers
import testutil.StableChiselSim

class GpioSpec extends AnyFunSpec with StableChiselSim with Matchers {
  describe("Gpio") {
    it("changes output only for legal writes and holds responses under backpressure") {
      simulate(new Gpio) { dut =>
        dut.io.bus.req.valid.poke(false)
        dut.io.bus.resp.ready.poke(true)
        dut.io.input.poke(0x5a)

        def transact(
          offset: BigInt,
          write: Boolean = false,
          data: BigInt = 0,
          strobe: Int = 0xf,
          size: Int = 2
        ): (BigInt, Boolean) = {
          dut.io.bus.req.valid.poke(true)
          dut.io.bus.req.bits.addr.poke(MemoryMap.GpioBase + offset)
          dut.io.bus.req.bits.write.poke(write)
          dut.io.bus.req.bits.size.poke(size)
          dut.io.bus.req.bits.wdata.poke(data)
          dut.io.bus.req.bits.wstrb.poke(strobe)
          while (!dut.io.bus.req.ready.peek().litToBoolean) dut.clock.step()
          dut.clock.step()
          dut.io.bus.req.valid.poke(false)
          while (!dut.io.bus.resp.valid.peek().litToBoolean) dut.clock.step()
          val result = dut.io.bus.resp.bits.rdata.peek().litValue ->
            dut.io.bus.resp.bits.error.peek().litToBoolean
          dut.clock.step()
          result
        }

        dut.io.output.expect(0)
        transact(MemoryMap.Gpio.InputOffset) shouldBe (BigInt(0x5a), false)
        transact(MemoryMap.Gpio.OutputOffset, write = true, data = 0xa5) shouldBe (BigInt(0), false)
        dut.io.output.expect(0xa5)
        transact(MemoryMap.Gpio.OutputOffset) shouldBe (BigInt(0xa5), false)

        transact(MemoryMap.Gpio.InputOffset, write = true, data = 0xff) shouldBe (BigInt(0), true)
        transact(MemoryMap.Gpio.OutputOffset, write = true, data = 0x11, strobe = 0x1) shouldBe (BigInt(0), true)
        transact(MemoryMap.Gpio.OutputOffset, write = true, data = 0x22, size = 1) shouldBe (BigInt(0), true)
        transact(0x08) shouldBe (BigInt(0), true)
        dut.io.output.expect(0xa5)

        dut.io.bus.resp.ready.poke(false)
        dut.io.bus.req.valid.poke(true)
        dut.io.bus.req.bits.addr.poke(MemoryMap.GpioBase + MemoryMap.Gpio.InputOffset)
        dut.io.bus.req.bits.write.poke(false)
        dut.io.bus.req.bits.size.poke(2)
        dut.io.bus.req.bits.wdata.poke(0)
        dut.io.bus.req.bits.wstrb.poke(0)
        dut.clock.step()
        dut.io.bus.req.valid.poke(false)
        dut.io.bus.resp.valid.expect(true)
        dut.io.bus.resp.bits.rdata.expect(0x5a)
        dut.io.input.poke(0x33)
        dut.clock.step(3)
        dut.io.bus.resp.valid.expect(true)
        dut.io.bus.resp.bits.rdata.expect(0x5a)
        dut.io.bus.resp.ready.poke(true)
        dut.clock.step()
      }
    }
  }
}
