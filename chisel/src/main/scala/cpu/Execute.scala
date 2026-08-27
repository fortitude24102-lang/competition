package cpu

import chisel3._
import chisel3.util._

class Execute extends Module {
  val io = IO(new Bundle {
    val operand1 = Input(UInt(32.W))
    val operand2 = Input(UInt(32.W))
    val rs1Value = Input(UInt(32.W))
    val rs2Value = Input(UInt(32.W))
    val pc = Input(UInt(32.W))
    val immediate = Input(UInt(32.W))
    val aluOp = Input(AluOp())
    val branchOp = Input(BranchOp())
    val aluResult = Output(UInt(32.W))
    val branchTaken = Output(Bool())
    val branchTarget = Output(UInt(32.W))
  })

  io.aluResult := 0.U
  switch(io.aluOp) {
    is(AluOp.Add) { io.aluResult := io.operand1 + io.operand2 }
    is(AluOp.Sub) { io.aluResult := io.operand1 - io.operand2 }
    is(AluOp.Sll) { io.aluResult := io.operand1 << io.operand2(4, 0) }
    is(AluOp.Slt) { io.aluResult := io.operand1.asSInt < io.operand2.asSInt }
    is(AluOp.Sltu) { io.aluResult := io.operand1 < io.operand2 }
    is(AluOp.Xor) { io.aluResult := io.operand1 ^ io.operand2 }
    is(AluOp.Srl) { io.aluResult := io.operand1 >> io.operand2(4, 0) }
    is(AluOp.Sra) { io.aluResult := (io.operand1.asSInt >> io.operand2(4, 0)).asUInt }
    is(AluOp.Or) { io.aluResult := io.operand1 | io.operand2 }
    is(AluOp.And) { io.aluResult := io.operand1 & io.operand2 }
    is(AluOp.CopyB) { io.aluResult := io.operand2 }
  }

  io.branchTaken := false.B
  switch(io.branchOp) {
    is(BranchOp.Eq) { io.branchTaken := io.rs1Value === io.rs2Value }
    is(BranchOp.Ne) { io.branchTaken := io.rs1Value =/= io.rs2Value }
    is(BranchOp.Lt) { io.branchTaken := io.rs1Value.asSInt < io.rs2Value.asSInt }
    is(BranchOp.Ge) { io.branchTaken := io.rs1Value.asSInt >= io.rs2Value.asSInt }
    is(BranchOp.Ltu) { io.branchTaken := io.rs1Value < io.rs2Value }
    is(BranchOp.Geu) { io.branchTaken := io.rs1Value >= io.rs2Value }
    is(BranchOp.Jal) { io.branchTaken := true.B }
    is(BranchOp.Jalr) { io.branchTaken := true.B }
  }

  val pcRelativeTarget = io.pc + io.immediate
  val registerTarget = (io.rs1Value + io.immediate) & "hfffffffe".U
  io.branchTarget := Mux(io.branchOp === BranchOp.Jalr, registerTarget, pcRelativeTarget)
}
