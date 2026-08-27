package cpu

import chisel3.simulator.scalatest.ChiselSim
import org.scalatest.funspec.AnyFunSpec

class RegFileSpec extends AnyFunSpec with ChiselSim {
  describe("RegFile") {
    it("keeps x0 zero and stores other registers") {
      simulate(new RegFile) { dut =>
        dut.io.rs1.poke(1)
        dut.io.rs2.poke(0)
        dut.io.writeEnable.poke(true)
        dut.io.rd.poke(1)
        dut.io.writeData.poke(BigInt("12345678", 16))
        dut.clock.step()
        dut.io.writeEnable.poke(false)
        dut.io.rs1Data.expect(BigInt("12345678", 16))

        dut.io.writeEnable.poke(true)
        dut.io.rd.poke(0)
        dut.io.writeData.poke(BigInt("ffffffff", 16))
        dut.clock.step()
        dut.io.rs1.poke(0)
        dut.io.rs1Data.expect(0)
      }
    }

    it("bypasses a same-cycle write to both read ports") {
      simulate(new RegFile) { dut =>
        dut.io.rs1.poke(7)
        dut.io.rs2.poke(7)
        dut.io.writeEnable.poke(true)
        dut.io.rd.poke(7)
        dut.io.writeData.poke(BigInt("89abcdef", 16))
        dut.io.rs1Data.expect(BigInt("89abcdef", 16))
        dut.io.rs2Data.expect(BigInt("89abcdef", 16))
      }
    }
  }
}
