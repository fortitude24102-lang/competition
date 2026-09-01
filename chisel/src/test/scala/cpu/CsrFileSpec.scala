package cpu

import org.scalatest.funspec.AnyFunSpec
import org.scalatest.matchers.should.Matchers
import testutil.StableChiselSim

class CsrFileSpec extends AnyFunSpec with StableChiselSim with Matchers {
  private def defaults(dut: CsrFile): Unit = {
    dut.io.address.poke(0)
    dut.io.writeValid.poke(false)
    dut.io.writeData.poke(0)
    dut.io.trapValid.poke(false)
    dut.io.trapPc.poke(0)
    dut.io.trapCause.poke(0)
    dut.io.trapInterrupt.poke(false)
    dut.io.trapValue.poke(0)
    dut.io.mretValid.poke(false)
    dut.io.timerInterrupt.poke(false)
  }

  private def read(dut: CsrFile, address: Int): (BigInt, Boolean, Boolean) = {
    dut.io.address.poke(address)
    (
      dut.io.readData.peek().litValue,
      dut.io.readLegal.peek().litToBoolean,
      dut.io.writeAllowed.peek().litToBoolean
    )
  }

  private def write(dut: CsrFile, address: Int, data: BigInt): Unit = {
    dut.io.address.poke(address)
    dut.io.writeData.poke(data)
    dut.io.writeValid.poke(true)
    dut.clock.step()
    dut.io.writeValid.poke(false)
  }

  describe("CsrFile") {
    it("implements reset values, writable masks, and access legality") {
      simulate(new CsrFile) { dut =>
        defaults(dut)

        read(dut, CsrAddress.Mstatus) shouldBe (BigInt(0x1800), true, true)
        read(dut, CsrAddress.Misa) shouldBe (BigInt("40000100", 16), true, false)
        read(dut, CsrAddress.Mie) shouldBe (BigInt(0), true, true)
        read(dut, CsrAddress.Mtvec) shouldBe (BigInt(0), true, true)
        read(dut, CsrAddress.Mscratch) shouldBe (BigInt(0), true, true)
        read(dut, CsrAddress.Mepc) shouldBe (BigInt(0), true, true)
        read(dut, CsrAddress.Mcause) shouldBe (BigInt(0), true, true)
        read(dut, CsrAddress.Mtval) shouldBe (BigInt(0), true, true)
        read(dut, CsrAddress.Mip) shouldBe (BigInt(0), true, true)
        read(dut, CsrAddress.Mhartid) shouldBe (BigInt(0), true, false)
        read(dut, 0x7ff) shouldBe (BigInt(0), false, false)

        write(dut, CsrAddress.Mstatus, BigInt("ffffffff", 16))
        read(dut, CsrAddress.Mstatus)._1 shouldBe BigInt(0x1888)
        write(dut, CsrAddress.Mie, BigInt("ffffffff", 16))
        read(dut, CsrAddress.Mie)._1 shouldBe BigInt(0x80)
        write(dut, CsrAddress.Mtvec, 0x123)
        read(dut, CsrAddress.Mtvec)._1 shouldBe BigInt(0x120)
        dut.io.trapVector.expect(0x120)
        write(dut, CsrAddress.Mepc, 0x87)
        read(dut, CsrAddress.Mepc)._1 shouldBe BigInt(0x84)
        dut.io.returnPc.expect(0x84)
        write(dut, CsrAddress.Mscratch, BigInt("a5a55a5a", 16))
        read(dut, CsrAddress.Mscratch)._1 shouldBe BigInt("a5a55a5a", 16)

        dut.io.timerInterrupt.poke(true)
        read(dut, CsrAddress.Mip)._1 shouldBe BigInt(0x80)
        dut.io.timerInterruptPending.expect(true)
        write(dut, CsrAddress.Mip, 0)
        read(dut, CsrAddress.Mip)._1 shouldBe BigInt(0x80)
      }
    }

    it("records traps, restores interrupt state with MRET, and prioritizes trap entry") {
      simulate(new CsrFile) { dut =>
        defaults(dut)
        write(dut, CsrAddress.Mstatus, 0x8)

        dut.io.trapValid.poke(true)
        dut.io.trapPc.poke(0x107)
        dut.io.trapCause.poke(11)
        dut.io.trapValue.poke(BigInt("deadbeef", 16))
        dut.clock.step()
        dut.io.trapValid.poke(false)

        read(dut, CsrAddress.Mstatus)._1 shouldBe BigInt(0x1880)
        read(dut, CsrAddress.Mepc)._1 shouldBe BigInt(0x104)
        read(dut, CsrAddress.Mcause)._1 shouldBe BigInt(11)
        read(dut, CsrAddress.Mtval)._1 shouldBe BigInt("deadbeef", 16)

        dut.io.mretValid.poke(true)
        dut.clock.step()
        dut.io.mretValid.poke(false)
        read(dut, CsrAddress.Mstatus)._1 shouldBe BigInt(0x1888)

        dut.io.address.poke(CsrAddress.Mscratch)
        dut.io.writeData.poke(0x55)
        dut.io.writeValid.poke(true)
        dut.io.mretValid.poke(true)
        dut.io.trapValid.poke(true)
        dut.io.trapPc.poke(0x200)
        dut.io.trapCause.poke(7)
        dut.io.trapInterrupt.poke(true)
        dut.io.trapValue.poke(0)
        dut.clock.step()
        dut.io.writeValid.poke(false)
        dut.io.mretValid.poke(false)
        dut.io.trapValid.poke(false)

        read(dut, CsrAddress.Mcause)._1 shouldBe BigInt("80000007", 16)
        read(dut, CsrAddress.Mepc)._1 shouldBe BigInt(0x200)
        read(dut, CsrAddress.Mscratch)._1 shouldBe BigInt(0)
        read(dut, CsrAddress.Mstatus)._1 shouldBe BigInt(0x1880)
      }
    }
  }
}
