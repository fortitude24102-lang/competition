package cpu

import chisel3._
import chisel3.util._

class Decoder extends Module {
  val io = IO(new Bundle {
    val inst = Input(UInt(32.W))
    val control = Output(new DecodedControl)
    val immediate = Output(UInt(32.W))
    val rs1 = Output(UInt(5.W))
    val rs2 = Output(UInt(5.W))
    val rd = Output(UInt(5.W))
  })

  val opcode = io.inst(6, 0)
  val funct3 = io.inst(14, 12)
  val funct7 = io.inst(31, 25)

  val iImmediate = Cat(Fill(20, io.inst(31)), io.inst(31, 20))
  val sImmediate = Cat(Fill(20, io.inst(31)), io.inst(31, 25), io.inst(11, 7))
  val bImmediate = Cat(Fill(19, io.inst(31)), io.inst(31), io.inst(7), io.inst(30, 25), io.inst(11, 8), 0.U(1.W))
  val uImmediate = Cat(io.inst(31, 12), 0.U(12.W))
  val jImmediate = Cat(Fill(11, io.inst(31)), io.inst(31), io.inst(19, 12), io.inst(20), io.inst(30, 21), 0.U(1.W))

  io.rs1 := io.inst(19, 15)
  io.rs2 := io.inst(24, 20)
  io.rd := io.inst(11, 7)
  io.immediate := 0.U
  io.control := 0.U.asTypeOf(new DecodedControl)
  io.control.aluOp := AluOp.Add
  io.control.branchOp := BranchOp.None
  io.control.op1Sel := Op1Sel.Rs1
  io.control.op2Sel := Op2Sel.Rs2
  io.control.wbSel := WbSel.Alu
  io.control.memWidth := MemWidth.Byte

  switch(opcode) {
    is("b0110111".U) { // LUI
      io.control.legal := true.B
      io.control.aluOp := AluOp.CopyB
      io.control.op1Sel := Op1Sel.Zero
      io.control.op2Sel := Op2Sel.Imm
      io.control.regWrite := true.B
      io.immediate := uImmediate
    }

    is("b0010111".U) { // AUIPC
      io.control.legal := true.B
      io.control.op1Sel := Op1Sel.Pc
      io.control.op2Sel := Op2Sel.Imm
      io.control.regWrite := true.B
      io.immediate := uImmediate
    }

    is("b1101111".U) { // JAL
      io.control.legal := true.B
      io.control.branchOp := BranchOp.Jal
      io.control.regWrite := true.B
      io.control.wbSel := WbSel.Pc4
      io.immediate := jImmediate
    }

    is("b1100111".U) { // JALR
      when(funct3 === 0.U) {
        io.control.legal := true.B
        io.control.rs1Used := true.B
        io.control.branchOp := BranchOp.Jalr
        io.control.regWrite := true.B
        io.control.wbSel := WbSel.Pc4
        io.immediate := iImmediate
      }
    }

    is("b1100011".U) { // Conditional branches
      io.control.rs1Used := true.B
      io.control.rs2Used := true.B
      io.immediate := bImmediate
      switch(funct3) {
        is("b000".U) { io.control.legal := true.B; io.control.branchOp := BranchOp.Eq }
        is("b001".U) { io.control.legal := true.B; io.control.branchOp := BranchOp.Ne }
        is("b100".U) { io.control.legal := true.B; io.control.branchOp := BranchOp.Lt }
        is("b101".U) { io.control.legal := true.B; io.control.branchOp := BranchOp.Ge }
        is("b110".U) { io.control.legal := true.B; io.control.branchOp := BranchOp.Ltu }
        is("b111".U) { io.control.legal := true.B; io.control.branchOp := BranchOp.Geu }
      }
    }

    is("b0000011".U) { // Loads
      io.control.rs1Used := true.B
      io.control.op2Sel := Op2Sel.Imm
      io.control.memRead := true.B
      io.control.regWrite := true.B
      io.control.wbSel := WbSel.Mem
      io.immediate := iImmediate
      switch(funct3) {
        is("b000".U) { io.control.legal := true.B; io.control.memWidth := MemWidth.Byte }
        is("b001".U) { io.control.legal := true.B; io.control.memWidth := MemWidth.Half }
        is("b010".U) { io.control.legal := true.B; io.control.memWidth := MemWidth.Word }
        is("b100".U) { io.control.legal := true.B; io.control.memWidth := MemWidth.Byte; io.control.memUnsigned := true.B }
        is("b101".U) { io.control.legal := true.B; io.control.memWidth := MemWidth.Half; io.control.memUnsigned := true.B }
      }
    }

    is("b0100011".U) { // Stores
      io.control.rs1Used := true.B
      io.control.rs2Used := true.B
      io.control.op2Sel := Op2Sel.Imm
      io.control.memWrite := true.B
      io.immediate := sImmediate
      switch(funct3) {
        is("b000".U) { io.control.legal := true.B; io.control.memWidth := MemWidth.Byte }
        is("b001".U) { io.control.legal := true.B; io.control.memWidth := MemWidth.Half }
        is("b010".U) { io.control.legal := true.B; io.control.memWidth := MemWidth.Word }
      }
    }

    is("b0010011".U) { // Immediate ALU
      io.control.rs1Used := true.B
      io.control.op2Sel := Op2Sel.Imm
      io.control.regWrite := true.B
      io.immediate := iImmediate
      switch(funct3) {
        is("b000".U) { io.control.legal := true.B; io.control.aluOp := AluOp.Add }
        is("b010".U) { io.control.legal := true.B; io.control.aluOp := AluOp.Slt }
        is("b011".U) { io.control.legal := true.B; io.control.aluOp := AluOp.Sltu }
        is("b100".U) { io.control.legal := true.B; io.control.aluOp := AluOp.Xor }
        is("b110".U) { io.control.legal := true.B; io.control.aluOp := AluOp.Or }
        is("b111".U) { io.control.legal := true.B; io.control.aluOp := AluOp.And }
        is("b001".U) {
          when(funct7 === "b0000000".U) {
            io.control.legal := true.B
            io.control.aluOp := AluOp.Sll
          }
        }
        is("b101".U) {
          when(funct7 === "b0000000".U) {
            io.control.legal := true.B
            io.control.aluOp := AluOp.Srl
          }.elsewhen(funct7 === "b0100000".U) {
            io.control.legal := true.B
            io.control.aluOp := AluOp.Sra
          }
        }
      }
    }

    is("b0110011".U) { // Register ALU
      io.control.rs1Used := true.B
      io.control.rs2Used := true.B
      io.control.regWrite := true.B
      switch(funct3) {
        is("b000".U) {
          when(funct7 === "b0000000".U) { io.control.legal := true.B; io.control.aluOp := AluOp.Add }
            .elsewhen(funct7 === "b0100000".U) { io.control.legal := true.B; io.control.aluOp := AluOp.Sub }
        }
        is("b001".U) { when(funct7 === 0.U) { io.control.legal := true.B; io.control.aluOp := AluOp.Sll } }
        is("b010".U) { when(funct7 === 0.U) { io.control.legal := true.B; io.control.aluOp := AluOp.Slt } }
        is("b011".U) { when(funct7 === 0.U) { io.control.legal := true.B; io.control.aluOp := AluOp.Sltu } }
        is("b100".U) { when(funct7 === 0.U) { io.control.legal := true.B; io.control.aluOp := AluOp.Xor } }
        is("b101".U) {
          when(funct7 === "b0000000".U) { io.control.legal := true.B; io.control.aluOp := AluOp.Srl }
            .elsewhen(funct7 === "b0100000".U) { io.control.legal := true.B; io.control.aluOp := AluOp.Sra }
        }
        is("b110".U) { when(funct7 === 0.U) { io.control.legal := true.B; io.control.aluOp := AluOp.Or } }
        is("b111".U) { when(funct7 === 0.U) { io.control.legal := true.B; io.control.aluOp := AluOp.And } }
      }
    }

    is("b0001111".U) { // FENCE
      when(funct3 === 0.U && io.rs1 === 0.U && io.rd === 0.U) {
        io.control.legal := true.B
        io.control.fence := true.B
      }
    }

    is("b1110011".U) { // Base SYSTEM instructions
      when(io.inst === "h00000073".U) {
        io.control.legal := true.B
        io.control.ecall := true.B
      }.elsewhen(io.inst === "h00100073".U) {
        io.control.legal := true.B
        io.control.ebreak := true.B
      }
    }
  }

  when(!io.control.legal) {
    io.control.regWrite := false.B
    io.control.memRead := false.B
    io.control.memWrite := false.B
    io.control.branchOp := BranchOp.None
  }
}
