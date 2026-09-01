package soc

import org.scalatest.funspec.AnyFunSpec
import org.scalatest.matchers.should.Matchers
import testutil.StableChiselSim

class MachineTimerSpec extends AnyFunSpec with StableChiselSim with Matchers {
  describe("MachineTimer") {
    it("counts cycles, compares mtime, rejects invalid accesses, and holds responses") {
      simulate(new MachineTimer) { dut =>
        dut.io.bus.req.valid.poke(false)
        dut.io.bus.resp.ready.poke(true)

        def transact(
          offset: BigInt,
          write: Boolean = false,
          data: BigInt = 0,
          strobe: Int = 0xf,
          size: Int = 2
        ): (BigInt, Boolean) = {
          dut.io.bus.req.valid.poke(true)
          dut.io.bus.req.bits.addr.poke(MemoryMap.TimerBase + offset)
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

        dut.io.interrupt.expect(false)
        transact(MemoryMap.Timer.MtimecmpLowOffset) shouldBe (BigInt("ffffffff", 16), false)
        transact(MemoryMap.Timer.MtimecmpHighOffset) shouldBe (BigInt("ffffffff", 16), false)

        val firstTime = transact(MemoryMap.Timer.MtimeLowOffset)._1
        dut.clock.step(4)
        val secondTime = transact(MemoryMap.Timer.MtimeLowOffset)._1
        secondTime should be > firstTime

        transact(MemoryMap.Timer.MtimecmpHighOffset, write = true, data = 0xffffffffL) shouldBe (BigInt(0), false)
        val now = transact(MemoryMap.Timer.MtimeLowOffset)._1
        val deadline = now + 16
        transact(MemoryMap.Timer.MtimecmpLowOffset, write = true, data = deadline) shouldBe (BigInt(0), false)
        transact(MemoryMap.Timer.MtimecmpHighOffset, write = true, data = 0) shouldBe (BigInt(0), false)
        dut.io.interrupt.expect(false)
        var waitCycles = 0
        while (!dut.io.interrupt.peek().litToBoolean && waitCycles < 20) {
          dut.clock.step()
          waitCycles += 1
        }
        dut.io.interrupt.expect(true)

        transact(MemoryMap.Timer.MtimecmpHighOffset, write = true, data = 0xffffffffL) shouldBe (BigInt(0), false)
        dut.io.interrupt.expect(false)
        transact(MemoryMap.Timer.MtimeLowOffset, write = true, data = 0) shouldBe (BigInt(0), true)
        transact(MemoryMap.Timer.MtimecmpLowOffset, write = true, data = 0, strobe = 0x3) shouldBe (BigInt(0), true)
        transact(MemoryMap.Timer.MtimecmpLowOffset, write = true, data = 0, size = 1) shouldBe (BigInt(0), true)
        transact(0x00) shouldBe (BigInt(0), true)

        dut.io.bus.resp.ready.poke(false)
        dut.io.bus.req.valid.poke(true)
        dut.io.bus.req.bits.addr.poke(MemoryMap.TimerBase + MemoryMap.Timer.MtimecmpHighOffset)
        dut.io.bus.req.bits.write.poke(false)
        dut.io.bus.req.bits.size.poke(2)
        dut.io.bus.req.bits.wdata.poke(0)
        dut.io.bus.req.bits.wstrb.poke(0)
        dut.clock.step()
        dut.io.bus.req.valid.poke(false)
        dut.io.bus.resp.valid.expect(true)
        dut.io.bus.resp.bits.rdata.expect(0xffffffffL)
        dut.clock.step(3)
        dut.io.bus.resp.valid.expect(true)
        dut.io.bus.resp.bits.rdata.expect(0xffffffffL)
        dut.io.bus.resp.ready.poke(true)
        dut.clock.step()
      }
    }
  }
}
