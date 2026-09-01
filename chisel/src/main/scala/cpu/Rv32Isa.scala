package cpu

import chisel3._

object AluOp extends ChiselEnum {
  val Add, Sub, Sll, Slt, Sltu, Xor, Srl, Sra, Or, And, CopyB = Value
}

object BranchOp extends ChiselEnum {
  val None, Eq, Ne, Lt, Ge, Ltu, Geu, Jal, Jalr = Value
}

object Op1Sel extends ChiselEnum {
  val Rs1, Pc, Zero = Value
}

object Op2Sel extends ChiselEnum {
  val Rs2, Imm = Value
}

object WbSel extends ChiselEnum {
  val Alu, Mem, Pc4 = Value
}

object MemWidth extends ChiselEnum {
  val Byte, Half, Word = Value
}

object CsrOp extends ChiselEnum {
  val None, Write, Set, Clear = Value
}

object TrapCause {
  val InstructionAddressMisaligned = 0.U(4.W)
  val InstructionAccessFault = 1.U(4.W)
  val IllegalInstruction = 2.U(4.W)
  val Breakpoint = 3.U(4.W)
  val LoadAddressMisaligned = 4.U(4.W)
  val LoadAccessFault = 5.U(4.W)
  val StoreAddressMisaligned = 6.U(4.W)
  val StoreAccessFault = 7.U(4.W)
  val EnvironmentCall = 11.U(4.W)
}

class DecodedControl extends Bundle {
  val legal = Bool()
  val rs1Used = Bool()
  val rs2Used = Bool()
  val aluOp = AluOp()
  val op1Sel = Op1Sel()
  val op2Sel = Op2Sel()
  val branchOp = BranchOp()
  val memRead = Bool()
  val memWrite = Bool()
  val memWidth = MemWidth()
  val memUnsigned = Bool()
  val regWrite = Bool()
  val wbSel = WbSel()
  val fence = Bool()
  val ecall = Bool()
  val ebreak = Bool()
  val csrOp = CsrOp()
  val csrImmediate = Bool()
  val mret = Bool()
}
