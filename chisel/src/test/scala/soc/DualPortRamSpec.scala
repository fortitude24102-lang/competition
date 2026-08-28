package soc

import org.scalatest.funspec.AnyFunSpec
import org.scalatest.matchers.should.Matchers
import testutil.StableChiselSim

class DualPortRamSpec extends AnyFunSpec with StableChiselSim with Matchers {
  describe("DualPortRam") {
    it("serves independent instruction and masked data accesses") {
      simulate(new DualPortRam(words = 64)) { dut =>
        dut.io.imem.req.valid.poke(false)
        dut.io.imem.resp.ready.poke(true)
        dut.io.dmem.req.valid.poke(false)
        dut.io.dmem.resp.ready.poke(true)

        def dataAccess(
          address: BigInt,
          write: Boolean = false,
          data: BigInt = 0,
          strobe: Int = 0,
          size: Int = 2
        ): (BigInt, Boolean) = {
          dut.io.dmem.req.valid.poke(true)
          dut.io.dmem.req.bits.addr.poke(address)
          dut.io.dmem.req.bits.write.poke(write)
          dut.io.dmem.req.bits.size.poke(size)
          dut.io.dmem.req.bits.wdata.poke(data)
          dut.io.dmem.req.bits.wstrb.poke(strobe)
          while (!dut.io.dmem.req.ready.peek().litToBoolean) dut.clock.step()
          dut.clock.step()
          dut.io.dmem.req.valid.poke(false)
          while (!dut.io.dmem.resp.valid.peek().litToBoolean) dut.clock.step()
          val result = dut.io.dmem.resp.bits.rdata.peek().litValue ->
            dut.io.dmem.resp.bits.error.peek().litToBoolean
          dut.clock.step()
          result
        }

        def instructionAccess(address: BigInt, write: Boolean = false): (BigInt, Boolean) = {
          dut.io.imem.req.valid.poke(true)
          dut.io.imem.req.bits.addr.poke(address)
          dut.io.imem.req.bits.write.poke(write)
          dut.io.imem.req.bits.size.poke(2)
          dut.io.imem.req.bits.wdata.poke(0)
          dut.io.imem.req.bits.wstrb.poke(0)
          while (!dut.io.imem.req.ready.peek().litToBoolean) dut.clock.step()
          dut.clock.step()
          dut.io.imem.req.valid.poke(false)
          while (!dut.io.imem.resp.valid.peek().litToBoolean) dut.clock.step()
          val result = dut.io.imem.resp.bits.rdata.peek().litValue ->
            dut.io.imem.resp.bits.error.peek().litToBoolean
          dut.clock.step()
          result
        }

        dataAccess(0x00, write = true, data = 0x11223344, strobe = 0xf) shouldBe (BigInt(0), false)
        instructionAccess(0x00) shouldBe (BigInt("11223344", 16), false)
        dataAccess(0x00, write = true, data = 0x0000aa00, strobe = 0x2) shouldBe (BigInt(0), false)
        dataAccess(0x00) shouldBe (BigInt("1122aa44", 16), false)
        dataAccess(0x04, write = true, data = 0x55667788, strobe = 0xf) shouldBe (BigInt(0), false)

        dut.io.imem.req.valid.poke(true)
        dut.io.imem.req.bits.addr.poke(0x00)
        dut.io.imem.req.bits.write.poke(false)
        dut.io.imem.req.bits.size.poke(2)
        dut.io.imem.req.bits.wdata.poke(0)
        dut.io.imem.req.bits.wstrb.poke(0)
        dut.io.dmem.req.valid.poke(true)
        dut.io.dmem.req.bits.addr.poke(0x04)
        dut.io.dmem.req.bits.write.poke(false)
        dut.io.dmem.req.bits.size.poke(2)
        dut.io.dmem.req.bits.wdata.poke(0)
        dut.io.dmem.req.bits.wstrb.poke(0)
        dut.io.imem.req.ready.expect(true)
        dut.io.dmem.req.ready.expect(true)
        dut.clock.step()
        dut.io.imem.req.valid.poke(false)
        dut.io.dmem.req.valid.poke(false)
        while (!dut.io.imem.resp.valid.peek().litToBoolean || !dut.io.dmem.resp.valid.peek().litToBoolean) {
          dut.clock.step()
        }
        dut.io.imem.resp.bits.rdata.expect(BigInt("1122aa44", 16))
        dut.io.dmem.resp.bits.rdata.expect(BigInt("55667788", 16))
        dut.io.imem.resp.bits.error.expect(false)
        dut.io.dmem.resp.bits.error.expect(false)
        dut.clock.step()

        instructionAccess(0x00, write = true)._2 shouldBe true
        instructionAccess(0x02)._2 shouldBe true
        dataAccess(0x100)._2 shouldBe true
        dataAccess(0x03, size = 2)._2 shouldBe true

        dut.io.dmem.resp.ready.poke(false)
        dut.io.dmem.req.valid.poke(true)
        dut.io.dmem.req.bits.addr.poke(0x00)
        dut.io.dmem.req.bits.write.poke(false)
        dut.io.dmem.req.bits.size.poke(2)
        dut.io.dmem.req.bits.wdata.poke(0)
        dut.io.dmem.req.bits.wstrb.poke(0)
        dut.clock.step()
        dut.io.dmem.req.valid.poke(false)
        while (!dut.io.dmem.resp.valid.peek().litToBoolean) dut.clock.step()
        dut.io.dmem.resp.bits.rdata.expect(BigInt("1122aa44", 16))
        dut.clock.step(3)
        dut.io.dmem.resp.valid.expect(true)
        dut.io.dmem.resp.bits.rdata.expect(BigInt("1122aa44", 16))
        dut.io.dmem.resp.ready.poke(true)
        dut.clock.step()
      }
    }
  }
}
