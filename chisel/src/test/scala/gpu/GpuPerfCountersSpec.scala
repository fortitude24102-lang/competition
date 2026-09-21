package gpu

import chisel3._
import org.scalatest.funspec.AnyFunSpec
import org.scalatest.matchers.should.Matchers
import testutil.StableChiselSim

class GpuPerfCountersSpec extends AnyFunSpec with StableChiselSim with Matchers {
  it("counts active cycles, completed pixels, AXI bytes, stalls, underflows, and DDR grants") {
    simulate(new GpuPerfCounters) { dut =>
      dut.io.clear.poke(false)
      dut.io.active.poke(true)
      dut.io.pixelDone.poke(true)
      dut.io.readBeat.poke(true)
      dut.io.writeStrobe.poke("b1011".U)
      dut.io.stalled.poke(true)
      dut.io.underflow.poke(true)
      dut.io.renderGrant.poke(2)
      dut.io.scanoutGrant.poke(0)
      dut.clock.step()

      dut.io.cycles.expect(1)
      dut.io.pixels.expect(1)
      dut.io.readBytes.expect(4)
      dut.io.writeBytes.expect(3)
      dut.io.stalls.expect(1)
      dut.io.underflows.expect(1)
      dut.io.renderGrants.expect(2)
      dut.io.scanoutGrants.expect(0)

      dut.io.pixelDone.poke(false)
      dut.io.readBeat.poke(false)
      dut.io.writeStrobe.poke(0)
      dut.io.stalled.poke(false)
      dut.io.underflow.poke(false)
      dut.io.renderGrant.poke(0)
      dut.io.scanoutGrant.poke(1)
      dut.clock.step()

      dut.io.cycles.expect(2)
      dut.io.pixels.expect(1)
      dut.io.readBytes.expect(4)
      dut.io.writeBytes.expect(3)
      dut.io.stalls.expect(1)
      dut.io.underflows.expect(1)
      dut.io.renderGrants.expect(2)
      dut.io.scanoutGrants.expect(1)

      dut.io.clear.poke(true)
      dut.clock.step()
      dut.io.cycles.expect(0)
      dut.io.pixels.expect(0)
      dut.io.readBytes.expect(0)
      dut.io.writeBytes.expect(0)
      dut.io.stalls.expect(0)
      dut.io.underflows.expect(0)
      dut.io.renderGrants.expect(0)
      dut.io.scanoutGrants.expect(0)
    }
  }

  it("gives clear priority over simultaneous events and resumes counting on the next cycle") {
    simulate(new GpuPerfCounters) { dut =>
      dut.io.clear.poke(true)
      dut.io.active.poke(true)
      dut.io.pixelDone.poke(true)
      dut.io.readBeat.poke(true)
      dut.io.writeStrobe.poke("b1111".U)
      dut.io.stalled.poke(true)
      dut.io.underflow.poke(true)
      dut.io.renderGrant.poke(1)
      dut.io.scanoutGrant.poke(1)
      dut.clock.step()

      dut.io.cycles.expect(0)
      dut.io.pixels.expect(0)
      dut.io.readBytes.expect(0)
      dut.io.writeBytes.expect(0)
      dut.io.stalls.expect(0)
      dut.io.underflows.expect(0)
      dut.io.renderGrants.expect(0)
      dut.io.scanoutGrants.expect(0)

      dut.io.clear.poke(false)
      dut.clock.step()

      dut.io.cycles.expect(1)
      dut.io.pixels.expect(1)
      dut.io.readBytes.expect(4)
      dut.io.writeBytes.expect(4)
      dut.io.stalls.expect(1)
      dut.io.underflows.expect(1)
      dut.io.renderGrants.expect(1)
      dut.io.scanoutGrants.expect(1)
    }
  }

  it("carries from the low 32-bit word into the high word without truncation") {
    simulate(new GpuPerfCounters(initialValue = BigInt("ffffffff", 16))) { dut =>
      dut.io.clear.poke(false)
      dut.io.active.poke(true)
      dut.io.pixelDone.poke(false)
      dut.io.readBeat.poke(false)
      dut.io.writeStrobe.poke(0)
      dut.io.stalled.poke(false)
      dut.io.underflow.poke(false)
      dut.io.renderGrant.poke(0)
      dut.io.scanoutGrant.poke(0)
      dut.clock.step()

      dut.io.cycles.expect(BigInt("100000000", 16))
    }
  }
}
