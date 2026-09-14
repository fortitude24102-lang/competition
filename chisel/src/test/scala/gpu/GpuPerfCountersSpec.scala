package gpu

import chisel3._
import org.scalatest.funspec.AnyFunSpec
import org.scalatest.matchers.should.Matchers
import testutil.StableChiselSim

class GpuPerfCountersSpec extends AnyFunSpec with StableChiselSim with Matchers {
  it("counts active cycles, completed pixels, AXI bytes, and stalls") {
    simulate(new GpuPerfCounters) { dut =>
      dut.io.clear.poke(false)
      dut.io.active.poke(true)
      dut.io.pixelDone.poke(true)
      dut.io.readBeat.poke(true)
      dut.io.writeStrobe.poke("b1011".U)
      dut.io.stalled.poke(true)
      dut.clock.step()

      dut.io.cycles.expect(1)
      dut.io.pixels.expect(1)
      dut.io.readBytes.expect(4)
      dut.io.writeBytes.expect(3)
      dut.io.stalls.expect(1)

      dut.io.pixelDone.poke(false)
      dut.io.readBeat.poke(false)
      dut.io.writeStrobe.poke(0)
      dut.io.stalled.poke(false)
      dut.clock.step()

      dut.io.cycles.expect(2)
      dut.io.pixels.expect(1)
      dut.io.readBytes.expect(4)
      dut.io.writeBytes.expect(3)
      dut.io.stalls.expect(1)

      dut.io.clear.poke(true)
      dut.clock.step()
      dut.io.cycles.expect(0)
      dut.io.pixels.expect(0)
      dut.io.readBytes.expect(0)
      dut.io.writeBytes.expect(0)
      dut.io.stalls.expect(0)
    }
  }
}
