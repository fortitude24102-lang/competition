package cpu

import org.scalatest.funspec.AnyFunSpec
import testutil.StableChiselSim

class DecoderSpec extends AnyFunSpec with StableChiselSim {
  private def check(dut: Decoder, inst: BigInt)(body: => Unit): Unit = {
    dut.io.inst.poke(inst)
    body
  }

  describe("Decoder") {
    it("decodes representative RV32I instruction formats") {
      simulate(new Decoder) { dut =>
        check(dut, BigInt("fff10093", 16)) {
          dut.io.control.legal.expect(true)
          dut.io.control.aluOp.expect(AluOp.Add)
          dut.io.control.rs1Used.expect(true)
          dut.io.control.regWrite.expect(true)
          dut.io.rs1.expect(2)
          dut.io.rd.expect(1)
          dut.io.immediate.expect(BigInt("ffffffff", 16))
        }

        check(dut, BigInt("002081b3", 16)) {
          dut.io.control.legal.expect(true)
          dut.io.control.aluOp.expect(AluOp.Add)
          dut.io.control.rs1Used.expect(true)
          dut.io.control.rs2Used.expect(true)
          dut.io.rs1.expect(1)
          dut.io.rs2.expect(2)
          dut.io.rd.expect(3)
        }

        check(dut, BigInt("00832283", 16)) {
          dut.io.control.legal.expect(true)
          dut.io.control.memRead.expect(true)
          dut.io.control.memWidth.expect(MemWidth.Word)
          dut.io.control.wbSel.expect(WbSel.Mem)
          dut.io.immediate.expect(8)
        }

        check(dut, BigInt("00532623", 16)) {
          dut.io.control.legal.expect(true)
          dut.io.control.memWrite.expect(true)
          dut.io.control.memWidth.expect(MemWidth.Word)
          dut.io.control.rs2Used.expect(true)
          dut.io.immediate.expect(12)
        }

        check(dut, BigInt("00208463", 16)) {
          dut.io.control.legal.expect(true)
          dut.io.control.branchOp.expect(BranchOp.Eq)
          dut.io.immediate.expect(8)
        }

        check(dut, BigInt("008000ef", 16)) {
          dut.io.control.legal.expect(true)
          dut.io.control.branchOp.expect(BranchOp.Jal)
          dut.io.control.wbSel.expect(WbSel.Pc4)
          dut.io.control.regWrite.expect(true)
          dut.io.immediate.expect(8)
        }
      }
    }

    it("decodes all register and immediate ALU operations") {
      simulate(new Decoder) { dut =>
        val registerOps = Seq(
          BigInt("002081b3", 16) -> AluOp.Add,
          BigInt("402081b3", 16) -> AluOp.Sub,
          BigInt("002091b3", 16) -> AluOp.Sll,
          BigInt("0020a1b3", 16) -> AluOp.Slt,
          BigInt("0020b1b3", 16) -> AluOp.Sltu,
          BigInt("0020c1b3", 16) -> AluOp.Xor,
          BigInt("0020d1b3", 16) -> AluOp.Srl,
          BigInt("4020d1b3", 16) -> AluOp.Sra,
          BigInt("0020e1b3", 16) -> AluOp.Or,
          BigInt("0020f1b3", 16) -> AluOp.And
        )
        registerOps.foreach { case (inst, operation) =>
          check(dut, inst) {
            dut.io.control.legal.expect(true)
            dut.io.control.aluOp.expect(operation)
          }
        }

        val immediateOps = Seq(
          BigInt("00110093", 16) -> AluOp.Add,
          BigInt("00112093", 16) -> AluOp.Slt,
          BigInt("00113093", 16) -> AluOp.Sltu,
          BigInt("00114093", 16) -> AluOp.Xor,
          BigInt("00116093", 16) -> AluOp.Or,
          BigInt("00117093", 16) -> AluOp.And,
          BigInt("00111093", 16) -> AluOp.Sll,
          BigInt("00115093", 16) -> AluOp.Srl,
          BigInt("40115093", 16) -> AluOp.Sra
        )
        immediateOps.foreach { case (inst, operation) =>
          check(dut, inst) {
            dut.io.control.legal.expect(true)
            dut.io.control.aluOp.expect(operation)
            dut.io.control.op2Sel.expect(Op2Sel.Imm)
          }
        }
      }
    }

    it("recognizes fence and base system traps") {
      simulate(new Decoder) { dut =>
        check(dut, BigInt("0000000f", 16)) {
          dut.io.control.legal.expect(true)
          dut.io.control.fence.expect(true)
        }
        check(dut, BigInt("00000073", 16)) {
          dut.io.control.legal.expect(true)
          dut.io.control.ecall.expect(true)
        }
        check(dut, BigInt("00100073", 16)) {
          dut.io.control.legal.expect(true)
          dut.io.control.ebreak.expect(true)
        }
      }
    }

    it("rejects illegal and reserved encodings without side effects") {
      simulate(new Decoder) { dut =>
        Seq(BigInt("ffffffff", 16), BigInt("402091b3", 16), BigInt("02011093", 16)).foreach { inst =>
          check(dut, inst) {
            dut.io.control.legal.expect(false)
            dut.io.control.regWrite.expect(false)
            dut.io.control.memRead.expect(false)
            dut.io.control.memWrite.expect(false)
          }
        }
      }
    }
  }
}
