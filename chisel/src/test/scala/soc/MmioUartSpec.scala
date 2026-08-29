package soc

import org.scalatest.funspec.AnyFunSpec
import org.scalatest.matchers.should.Matchers
import testutil.StableChiselSim

class MmioUartSpec extends AnyFunSpec with StableChiselSim with Matchers {
  describe("MmioUart") {
    it("buffers exactly one transmit byte and reports backpressure") {
      simulate(new MmioUart) { dut =>
        dut.io.bus.req.valid.poke(false)
        dut.io.bus.resp.ready.poke(true)
        dut.io.tx.ready.poke(false)
        dut.io.rx.valid.poke(false)
        dut.io.rx.bits.poke(0)

        def transact(
          offset: BigInt,
          write: Boolean = false,
          data: BigInt = 0,
          strobe: Int = 0xf
        ): (BigInt, Boolean) = {
          dut.io.bus.req.valid.poke(true)
          dut.io.bus.req.bits.addr.poke(MemoryMap.UartBase + offset)
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

        transact(MemoryMap.Uart.StatusOffset) shouldBe (BigInt(1), false)
        transact(MemoryMap.Uart.TxDataOffset, write = true, data = 0xa5) shouldBe (BigInt(0), false)
        dut.io.tx.valid.expect(true)
        dut.io.tx.bits.expect(0xa5)
        dut.clock.step(3)
        dut.io.tx.valid.expect(true)
        dut.io.tx.bits.expect(0xa5)
        transact(MemoryMap.Uart.StatusOffset) shouldBe (BigInt(0), false)

        transact(MemoryMap.Uart.TxDataOffset, write = true, data = 0x5a) shouldBe (BigInt(0), true)
        dut.io.tx.bits.expect(0xa5)

        dut.io.tx.ready.poke(true)
        dut.clock.step()
        dut.io.tx.valid.expect(false)
        transact(MemoryMap.Uart.StatusOffset) shouldBe (BigInt(1), false)

        transact(MemoryMap.Uart.TxDataOffset) shouldBe (BigInt(0), true)
        transact(0x0c) shouldBe (BigInt(0), true)
        transact(MemoryMap.Uart.TxDataOffset, write = true, data = 0xff, strobe = 0) shouldBe (BigInt(0), true)

        dut.io.rx.bits.poke(0x41)
        dut.io.rx.valid.poke(true)
        dut.io.rx.ready.expect(true)
        dut.clock.step()
        dut.io.rx.valid.poke(false)
        dut.io.rx.ready.expect(false)
        transact(MemoryMap.Uart.StatusOffset) shouldBe (BigInt(3), false)

        dut.io.rx.bits.poke(0x42)
        dut.io.rx.valid.poke(true)
        dut.clock.step(2)
        dut.io.rx.ready.expect(false)
        dut.io.rx.valid.poke(false)
        transact(MemoryMap.Uart.RxDataOffset) shouldBe (BigInt(0x41), false)
        dut.io.rx.ready.expect(true)
        transact(MemoryMap.Uart.StatusOffset) shouldBe (BigInt(1), false)
        transact(MemoryMap.Uart.RxDataOffset) shouldBe (BigInt(0), true)

        dut.io.bus.resp.ready.poke(false)
        dut.io.bus.req.valid.poke(true)
        dut.io.bus.req.bits.addr.poke(MemoryMap.UartBase + MemoryMap.Uart.StatusOffset)
        dut.io.bus.req.bits.write.poke(false)
        dut.io.bus.req.bits.size.poke(2)
        dut.io.bus.req.bits.wdata.poke(0)
        dut.io.bus.req.bits.wstrb.poke(0)
        dut.clock.step()
        dut.io.bus.req.valid.poke(false)
        dut.io.bus.resp.valid.expect(true)
        dut.io.bus.resp.bits.rdata.expect(1)
        dut.clock.step(3)
        dut.io.bus.resp.valid.expect(true)
        dut.io.bus.resp.bits.rdata.expect(1)
        dut.io.bus.resp.ready.poke(true)
        dut.clock.step()
      }
    }
  }
}
