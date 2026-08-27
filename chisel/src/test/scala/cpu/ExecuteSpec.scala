package cpu

import chisel3.simulator.scalatest.ChiselSim
import org.scalatest.funspec.AnyFunSpec

class ExecuteSpec extends AnyFunSpec with ChiselSim {
  private def defaults(dut: Execute): Unit = {
    dut.io.operand1.poke(0)
    dut.io.operand2.poke(0)
    dut.io.rs1Value.poke(0)
    dut.io.rs2Value.poke(0)
    dut.io.pc.poke(0)
    dut.io.immediate.poke(0)
    dut.io.aluOp.poke(AluOp.Add)
    dut.io.branchOp.poke(BranchOp.None)
  }

  describe("Execute") {
    it("implements every RV32I ALU operation") {
      simulate(new Execute) { dut =>
        defaults(dut)
        val cases = Seq(
          (AluOp.Add, BigInt("ffffffff", 16), BigInt(2), BigInt(1)),
          (AluOp.Sub, BigInt(1), BigInt(2), BigInt("ffffffff", 16)),
          (AluOp.Sll, BigInt(1), BigInt(31), BigInt("80000000", 16)),
          (AluOp.Slt, BigInt("ffffffff", 16), BigInt(1), BigInt(1)),
          (AluOp.Sltu, BigInt("ffffffff", 16), BigInt(1), BigInt(0)),
          (AluOp.Xor, BigInt("aa55aa55", 16), BigInt("ffff0000", 16), BigInt("55aaaa55", 16)),
          (AluOp.Srl, BigInt("80000000", 16), BigInt(31), BigInt(1)),
          (AluOp.Sra, BigInt("80000000", 16), BigInt(31), BigInt("ffffffff", 16)),
          (AluOp.Or, BigInt("aa550000", 16), BigInt("0000aa55", 16), BigInt("aa55aa55", 16)),
          (AluOp.And, BigInt("aa55aa55", 16), BigInt("0ff00ff0", 16), BigInt("0a500a50", 16)),
          (AluOp.CopyB, BigInt("aaaaaaaa", 16), BigInt("12345678", 16), BigInt("12345678", 16))
        )

        cases.foreach { case (operation, left, right, expected) =>
          dut.io.aluOp.poke(operation)
          dut.io.operand1.poke(left)
          dut.io.operand2.poke(right)
          dut.io.aluResult.expect(expected)
        }
      }
    }

    it("distinguishes signed and unsigned branches") {
      simulate(new Execute) { dut =>
        defaults(dut)
        dut.io.rs1Value.poke(BigInt("ffffffff", 16))
        dut.io.rs2Value.poke(1)

        dut.io.branchOp.poke(BranchOp.Lt)
        dut.io.branchTaken.expect(true)
        dut.io.branchOp.poke(BranchOp.Ltu)
        dut.io.branchTaken.expect(false)
        dut.io.branchOp.poke(BranchOp.Ge)
        dut.io.branchTaken.expect(false)
        dut.io.branchOp.poke(BranchOp.Geu)
        dut.io.branchTaken.expect(true)
      }
    }

    it("computes branch targets in parallel and clears JALR bit zero") {
      simulate(new Execute) { dut =>
        defaults(dut)
        dut.io.pc.poke(0x100)
        dut.io.immediate.poke(12)
        dut.io.branchOp.poke(BranchOp.Jal)
        dut.io.branchTaken.expect(true)
        dut.io.branchTarget.expect(0x10c)

        dut.io.rs1Value.poke(0x202)
        dut.io.immediate.poke(3)
        dut.io.branchOp.poke(BranchOp.Jalr)
        dut.io.branchTaken.expect(true)
        dut.io.branchTarget.expect(0x204)
      }
    }
  }
}
