package soc

import org.scalatest.funspec.AnyFunSpec
import org.scalatest.matchers.should.Matchers
import testutil.StableChiselSim

class AccelRegsSpec extends AnyFunSpec with StableChiselSim with Matchers {
  describe("AccelRegs") {
    it("implements the frozen control and status register contract") {
      simulate(new AccelRegs) { dut =>
        dut.io.bus.req.valid.poke(false)
        dut.io.bus.resp.ready.poke(true)
        dut.io.busy.poke(false)
        dut.io.frameDone.poke(false)

        def transact(
          offset: BigInt,
          write: Boolean = false,
          data: BigInt = 0,
          strobe: Int = 0xf
        ): (BigInt, Boolean) = {
          dut.io.bus.req.valid.poke(true)
          dut.io.bus.req.bits.addr.poke(MemoryMap.AccelBase + offset)
          dut.io.bus.req.bits.write.poke(write)
          dut.io.bus.req.bits.size.poke(2)
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

        dut.io.enable.expect(false)
        dut.io.mode.expect(0)
        dut.io.threshold.expect(128)
        dut.io.bypass.expect(true)

        transact(MemoryMap.Accelerator.ControlOffset, write = true, data = 1) shouldBe (BigInt(0), false)
        transact(MemoryMap.Accelerator.ModeOffset, write = true, data = 2) shouldBe (BigInt(0), false)
        transact(MemoryMap.Accelerator.ThresholdOffset, write = true, data = 50) shouldBe (BigInt(0), false)
        transact(MemoryMap.Accelerator.BypassOffset, write = true, data = 0) shouldBe (BigInt(0), false)

        dut.io.enable.expect(true)
        dut.io.mode.expect(2)
        dut.io.threshold.expect(50)
        dut.io.bypass.expect(false)
        transact(MemoryMap.Accelerator.ControlOffset)._1 shouldBe BigInt(1)
        transact(MemoryMap.Accelerator.ModeOffset)._1 shouldBe BigInt(2)
        transact(MemoryMap.Accelerator.ThresholdOffset)._1 shouldBe BigInt(50)
        transact(MemoryMap.Accelerator.BypassOffset)._1 shouldBe BigInt(0)

        dut.io.busy.poke(true)
        dut.io.frameDone.poke(true)
        transact(MemoryMap.Accelerator.StatusOffset) shouldBe (BigInt(3), false)

        transact(MemoryMap.Accelerator.ModeOffset, write = true, data = 1, strobe = 0) shouldBe (BigInt(0), false)
        dut.io.mode.expect(2)
        transact(MemoryMap.Accelerator.StatusOffset, write = true, data = 0) shouldBe (BigInt(0), true)
        transact(0x14, write = true, data = 0xffffffffL) shouldBe (BigInt(0), true)
        dut.io.mode.expect(2)

        dut.io.bus.resp.ready.poke(false)
        dut.io.bus.req.valid.poke(true)
        dut.io.bus.req.bits.addr.poke(MemoryMap.AccelBase + MemoryMap.Accelerator.ModeOffset)
        dut.io.bus.req.bits.write.poke(false)
        dut.io.bus.req.bits.size.poke(2)
        dut.io.bus.req.bits.wdata.poke(0)
        dut.io.bus.req.bits.wstrb.poke(0)
        dut.clock.step()
        dut.io.bus.req.valid.poke(false)
        dut.io.bus.resp.valid.expect(true)
        dut.io.bus.resp.bits.rdata.expect(2)
        dut.clock.step(3)
        dut.io.bus.resp.valid.expect(true)
        dut.io.bus.resp.bits.rdata.expect(2)
        dut.io.bus.resp.ready.poke(true)
        dut.clock.step()
      }
    }
  }
}
