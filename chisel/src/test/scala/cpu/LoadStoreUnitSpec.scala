package cpu

import chisel3.simulator.scalatest.ChiselSim
import org.scalatest.funspec.AnyFunSpec

class LoadStoreUnitSpec extends AnyFunSpec with ChiselSim {
  private def defaults(dut: LoadStoreUnit): Unit = {
    dut.io.addr.poke(0)
    dut.io.memWidth.poke(MemWidth.Byte)
    dut.io.unsignedLoad.poke(false)
    dut.io.storeData.poke(0)
    dut.io.responseData.poke(0)
  }

  describe("LoadStoreUnit") {
    it("extracts signed and unsigned bytes at every offset") {
      simulate(new LoadStoreUnit) { dut =>
        defaults(dut)
        dut.io.responseData.poke(BigInt("80ff7f01", 16))
        val signed = Seq(BigInt(1), BigInt(127), BigInt("ffffffff", 16), BigInt("ffffff80", 16))
        val unsigned = Seq(BigInt(1), BigInt(127), BigInt(255), BigInt(128))
        for (offset <- 0 until 4) {
          dut.io.addr.poke(offset)
          dut.io.unsignedLoad.poke(false)
          dut.io.loadData.expect(signed(offset))
          dut.io.unsignedLoad.poke(true)
          dut.io.loadData.expect(unsigned(offset))
          dut.io.misaligned.expect(false)
        }
      }
    }

    it("extracts signed and unsigned halfwords at legal offsets") {
      simulate(new LoadStoreUnit) { dut =>
        defaults(dut)
        dut.io.memWidth.poke(MemWidth.Half)
        dut.io.responseData.poke(BigInt("80017fff", 16))

        dut.io.addr.poke(0)
        dut.io.unsignedLoad.poke(false)
        dut.io.loadData.expect(0x7fff)
        dut.io.addr.poke(2)
        dut.io.loadData.expect(BigInt("ffff8001", 16))
        dut.io.unsignedLoad.poke(true)
        dut.io.loadData.expect(0x8001)
      }
    }

    it("generates byte, halfword, and word store lanes") {
      simulate(new LoadStoreUnit) { dut =>
        defaults(dut)
        dut.io.storeData.poke(BigInt("a1b2c3d4", 16))

        for (offset <- 0 until 4) {
          dut.io.memWidth.poke(MemWidth.Byte)
          dut.io.addr.poke(offset)
          dut.io.wstrb.expect(1 << offset)
          dut.io.wdata.expect((BigInt(0xd4) << (offset * 8)) & BigInt("ffffffff", 16))
        }

        dut.io.memWidth.poke(MemWidth.Half)
        dut.io.addr.poke(0)
        dut.io.wstrb.expect(3)
        dut.io.wdata.expect(0xc3d4)
        dut.io.addr.poke(2)
        dut.io.wstrb.expect(12)
        dut.io.wdata.expect(BigInt("c3d40000", 16))

        dut.io.memWidth.poke(MemWidth.Word)
        dut.io.addr.poke(0)
        dut.io.wstrb.expect(15)
        dut.io.wdata.expect(BigInt("a1b2c3d4", 16))
      }
    }

    it("detects every misaligned halfword and word offset") {
      simulate(new LoadStoreUnit) { dut =>
        defaults(dut)
        dut.io.memWidth.poke(MemWidth.Half)
        for (offset <- 0 until 4) {
          dut.io.addr.poke(offset)
          dut.io.misaligned.expect((offset & 1) != 0)
        }

        dut.io.memWidth.poke(MemWidth.Word)
        for (offset <- 0 until 4) {
          dut.io.addr.poke(offset)
          dut.io.misaligned.expect(offset != 0)
        }
      }
    }
  }
}
