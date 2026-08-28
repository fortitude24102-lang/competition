package soc

import cpu.CoreBusIO
import org.scalatest.funspec.AnyFunSpec
import org.scalatest.matchers.should.Matchers
import testutil.StableChiselSim

class SoCInterconnectSpec extends AnyFunSpec with StableChiselSim with Matchers {
  describe("SoCInterconnect") {
    it("routes every region and locks each accepted response source") {
      simulate(new SoCInterconnect) { dut =>
        val targets = Seq(
          dut.io.ramImem,
          dut.io.ramDmem,
          dut.io.uart,
          dut.io.accelerator,
          dut.io.externalImem,
          dut.io.externalDmem
        )

        dut.io.cpuImem.req.valid.poke(false)
        dut.io.cpuImem.resp.ready.poke(true)
        dut.io.cpuDmem.req.valid.poke(false)
        dut.io.cpuDmem.resp.ready.poke(true)
        targets.foreach { target =>
          target.req.ready.poke(true)
          target.resp.valid.poke(false)
          target.resp.bits.rdata.poke(0)
          target.resp.bits.error.poke(false)
        }

        def driveRequest(cpu: SocBusTargetIO, address: BigInt): Unit = {
          cpu.req.valid.poke(true)
          cpu.req.bits.addr.poke(address)
          cpu.req.bits.write.poke(false)
          cpu.req.bits.size.poke(2)
          cpu.req.bits.wdata.poke(0)
          cpu.req.bits.wstrb.poke(0)
        }

        def exchange(cpu: SocBusTargetIO, target: CoreBusIO, address: BigInt, response: BigInt): Unit = {
          driveRequest(cpu, address)
          cpu.req.ready.expect(true)
          target.req.valid.expect(true)
          target.req.bits.addr.expect(address)
          dut.clock.step()
          cpu.req.valid.poke(false)
          target.resp.valid.poke(true)
          target.resp.bits.rdata.poke(response)
          cpu.resp.valid.expect(true)
          cpu.resp.bits.rdata.expect(response)
          cpu.resp.bits.error.expect(false)
          dut.clock.step()
          target.resp.valid.poke(false)
        }

        def expectLocalError(cpu: SocBusTargetIO, address: BigInt): Unit = {
          driveRequest(cpu, address)
          cpu.req.ready.expect(true)
          targets.foreach(_.req.valid.expect(false))
          dut.clock.step()
          cpu.req.valid.poke(false)
          cpu.resp.valid.expect(true)
          cpu.resp.bits.error.expect(true)
          dut.clock.step()
        }

        exchange(dut.io.cpuImem, dut.io.ramImem, MemoryMap.BootRamBase, 0x11111111)
        exchange(dut.io.cpuImem, dut.io.ramImem, MemoryMap.BootRamBase + MemoryMap.BootRamBytes - 1, 0x11111112)
        exchange(dut.io.cpuImem, dut.io.externalImem, MemoryMap.ExternalBase, 0x22222222)
        exchange(dut.io.cpuImem, dut.io.externalImem, BigInt("ffffffff", 16), 0x22222223)
        expectLocalError(dut.io.cpuImem, MemoryMap.UartBase)

        exchange(dut.io.cpuDmem, dut.io.ramDmem, MemoryMap.BootRamBase + 4, 0x33333333)
        exchange(dut.io.cpuDmem, dut.io.ramDmem, MemoryMap.BootRamBase + MemoryMap.BootRamBytes - 1, 0x33333334)
        exchange(dut.io.cpuDmem, dut.io.uart, MemoryMap.UartBase, 0x44444444)
        exchange(dut.io.cpuDmem, dut.io.uart, MemoryMap.UartBase + MemoryMap.UartBytes - 1, 0x44444445)
        exchange(dut.io.cpuDmem, dut.io.accelerator, MemoryMap.AccelBase, 0x55555555)
        exchange(dut.io.cpuDmem, dut.io.accelerator, MemoryMap.AccelBase + MemoryMap.AccelBytes - 1, 0x55555556)
        exchange(dut.io.cpuDmem, dut.io.externalDmem, MemoryMap.ExternalBase, 0x66666666)
        exchange(dut.io.cpuDmem, dut.io.externalDmem, BigInt("ffffffff", 16), 0x66666667)
        expectLocalError(dut.io.cpuDmem, BigInt("40000000", 16))

        dut.io.cpuDmem.resp.ready.poke(false)
        driveRequest(dut.io.cpuDmem, MemoryMap.AccelBase + MemoryMap.Accelerator.ModeOffset)
        dut.io.accelerator.req.valid.expect(true)
        dut.clock.step()
        dut.io.cpuDmem.req.valid.poke(false)
        dut.io.accelerator.resp.valid.poke(true)
        dut.io.accelerator.resp.bits.rdata.poke(2)
        dut.io.uart.resp.valid.poke(true)
        dut.io.uart.resp.bits.rdata.poke(0xdeadbeefL)
        dut.io.cpuDmem.resp.valid.expect(true)
        dut.io.cpuDmem.resp.bits.rdata.expect(2)
        dut.io.accelerator.resp.ready.expect(false)
        dut.io.uart.resp.ready.expect(false)
        dut.clock.step(2)
        dut.io.cpuDmem.resp.bits.rdata.expect(2)
        dut.io.cpuDmem.resp.ready.poke(true)
        dut.io.accelerator.resp.ready.expect(true)
        dut.clock.step()
        dut.io.accelerator.resp.valid.poke(false)
        dut.io.uart.resp.valid.poke(false)

        dut.io.ramDmem.req.ready.poke(false)
        driveRequest(dut.io.cpuDmem, MemoryMap.BootRamBase + 8)
        dut.io.cpuDmem.req.ready.expect(false)
        dut.io.ramDmem.req.valid.expect(true)
        dut.io.ramDmem.req.bits.addr.expect(MemoryMap.BootRamBase + 8)
        dut.clock.step(2)
        dut.io.ramDmem.req.valid.expect(true)
        dut.io.ramDmem.req.bits.addr.expect(MemoryMap.BootRamBase + 8)
        dut.io.ramDmem.req.ready.poke(true)
        dut.io.cpuDmem.req.ready.expect(true)
        dut.clock.step()
        dut.io.cpuDmem.req.valid.poke(false)
        dut.io.ramDmem.resp.valid.poke(true)
        dut.io.ramDmem.resp.bits.rdata.poke(0x77777777)
        dut.io.cpuDmem.resp.bits.rdata.expect(0x77777777)
        dut.clock.step()
        dut.io.ramDmem.resp.valid.poke(false)

        dut.io.cpuDmem.resp.ready.poke(false)
        driveRequest(dut.io.cpuDmem, BigInt("40000004", 16))
        dut.clock.step()
        dut.io.cpuDmem.req.valid.poke(false)
        dut.io.cpuDmem.resp.valid.expect(true)
        dut.io.cpuDmem.resp.bits.error.expect(true)
        dut.clock.step(2)
        dut.io.cpuDmem.resp.valid.expect(true)
        dut.io.cpuDmem.resp.bits.error.expect(true)
        dut.io.cpuDmem.resp.ready.poke(true)
        dut.clock.step()
      }
    }
  }
}
