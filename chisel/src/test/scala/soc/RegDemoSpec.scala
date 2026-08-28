package soc

import org.scalatest.funspec.AnyFunSpec
import testutil.StableChiselSim

class RegDemoSpec extends AnyFunSpec with StableChiselSim {
  describe("RegDemo") {
    it("resets the stored value to zero") {
      simulate(new RegDemo) { dut =>
        dut.io.read_data.expect(0)
      }
    }

    it("stores 0x55 when write enable is asserted") {
      simulate(new RegDemo) { dut =>
        dut.io.write_en.poke(true)
        dut.io.write_data.poke(0x55)
        dut.clock.step()

        dut.io.read_data.expect(0x55)
      }
    }

    it("holds the stored value when write enable is deasserted") {
      simulate(new RegDemo) { dut =>
        dut.io.write_en.poke(true)
        dut.io.write_data.poke(0x55)
        dut.clock.step()

        dut.io.write_en.poke(false)
        dut.io.write_data.poke(0xaa)
        dut.clock.step()

        dut.io.read_data.expect(0x55)
      }
    }
  }
}
