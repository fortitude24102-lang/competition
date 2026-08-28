package cpu

import chisel3._
import chisel3.util._

private class IfIdStage extends Bundle {
  val valid = Bool()
  val pc = UInt(32.W)
  val inst = UInt(32.W)
  val fetchError = Bool()
}

private class IdExStage extends Bundle {
  val valid = Bool()
  val pc = UInt(32.W)
  val inst = UInt(32.W)
  val fetchError = Bool()
  val control = new DecodedControl
  val immediate = UInt(32.W)
  val rs1 = UInt(5.W)
  val rs2 = UInt(5.W)
  val rd = UInt(5.W)
  val rs1Value = UInt(32.W)
  val rs2Value = UInt(32.W)
}

private class ExMemStage extends Bundle {
  val valid = Bool()
  val pc = UInt(32.W)
  val inst = UInt(32.W)
  val legal = Bool()
  val aluResult = UInt(32.W)
  val rd = UInt(5.W)
  val regWrite = Bool()
  val wbSel = WbSel()
  val memRead = Bool()
}

private class MemWbStage extends Bundle {
  val valid = Bool()
  val pc = UInt(32.W)
  val inst = UInt(32.W)
  val legal = Bool()
  val rd = UInt(5.W)
  val regWrite = Bool()
  val writeData = UInt(32.W)
}

class Rv32Core(resetVector: BigInt = 0) extends Module {
  val io = IO(new Bundle {
    val imem = new CoreBusIO
    val dmem = new CoreBusIO
    val commit = Output(new CommitTrace)
    val trap = Output(new TrapTrace)
    val halted = Output(Bool())
  })

  val frontend = Module(new Frontend(resetVector))
  val decoder = Module(new Decoder)
  val regFile = Module(new RegFile)
  val execute = Module(new Execute)
  val control = Module(new PipelineControl)

  private val ifId = RegInit(0.U.asTypeOf(new IfIdStage))
  private val idEx = RegInit(0.U.asTypeOf(new IdExStage))
  private val exMem = RegInit(0.U.asTypeOf(new ExMemStage))
  private val memWb = RegInit(0.U.asTypeOf(new MemWbStage))

  io.imem.req.valid := frontend.io.imem.req.valid
  io.imem.req.bits := frontend.io.imem.req.bits
  frontend.io.imem.req.ready := io.imem.req.ready
  frontend.io.imem.resp.valid := io.imem.resp.valid
  frontend.io.imem.resp.bits := io.imem.resp.bits
  io.imem.resp.ready := frontend.io.imem.resp.ready

  io.dmem.req.valid := false.B
  io.dmem.req.bits := 0.U.asTypeOf(new CoreBusReq)
  io.dmem.resp.ready := false.B

  decoder.io.inst := ifId.inst
  regFile.io.rs1 := decoder.io.rs1
  regFile.io.rs2 := decoder.io.rs2
  regFile.io.rd := memWb.rd
  regFile.io.writeEnable := memWb.valid && memWb.legal && memWb.regWrite
  regFile.io.writeData := memWb.writeData

  val exMemForwardValue = Mux(exMem.wbSel === WbSel.Pc4, exMem.pc + 4.U, exMem.aluResult)
  val forwardedRs1 = MuxLookup(control.io.forwardRs1, idEx.rs1Value)(Seq(
    ForwardSel.ExMem -> exMemForwardValue,
    ForwardSel.MemWb -> memWb.writeData
  ))
  val forwardedRs2 = MuxLookup(control.io.forwardRs2, idEx.rs2Value)(Seq(
    ForwardSel.ExMem -> exMemForwardValue,
    ForwardSel.MemWb -> memWb.writeData
  ))

  execute.io.operand1 := MuxLookup(idEx.control.op1Sel, forwardedRs1)(Seq(
    Op1Sel.Pc -> idEx.pc,
    Op1Sel.Zero -> 0.U
  ))
  execute.io.operand2 := Mux(idEx.control.op2Sel === Op2Sel.Imm, idEx.immediate, forwardedRs2)
  execute.io.rs1Value := forwardedRs1
  execute.io.rs2Value := forwardedRs2
  execute.io.pc := idEx.pc
  execute.io.immediate := idEx.immediate
  execute.io.aluOp := idEx.control.aluOp
  execute.io.branchOp := idEx.control.branchOp

  control.io.exRs1 := idEx.rs1
  control.io.exRs2 := idEx.rs2
  control.io.exRs1Used := idEx.valid && idEx.control.rs1Used
  control.io.exRs2Used := idEx.valid && idEx.control.rs2Used
  control.io.exMemValid := exMem.valid
  control.io.exMemRegWrite := exMem.regWrite
  control.io.exMemResultReady := !exMem.memRead
  control.io.exMemRd := exMem.rd
  control.io.memWbValid := memWb.valid
  control.io.memWbRegWrite := memWb.regWrite
  control.io.memWbRd := memWb.rd
  control.io.idRs1 := decoder.io.rs1
  control.io.idRs2 := decoder.io.rs2
  control.io.idRs1Used := ifId.valid && decoder.io.control.rs1Used
  control.io.idRs2Used := ifId.valid && decoder.io.control.rs2Used
  control.io.idExValid := idEx.valid
  control.io.idExMemRead := idEx.control.memRead
  control.io.idExRd := idEx.rd
  control.io.resetActive := reset.asBool
  control.io.trap := false.B
  control.io.redirect := false.B
  control.io.memoryWait := false.B

  frontend.io.redirectValid := false.B
  frontend.io.redirectPc := 0.U
  frontend.io.output.ready := control.io.action === PipelineAction.Advance

  when(control.io.action === PipelineAction.Reset) {
    ifId.valid := false.B
    idEx.valid := false.B
    exMem.valid := false.B
    memWb.valid := false.B
  }.elsewhen(control.io.action === PipelineAction.LoadUseStall) {
    memWb.valid := exMem.valid
    memWb.pc := exMem.pc
    memWb.inst := exMem.inst
    memWb.legal := exMem.legal
    memWb.rd := exMem.rd
    memWb.regWrite := exMem.regWrite
    memWb.writeData := exMemForwardValue

    exMem.valid := idEx.valid
    exMem.pc := idEx.pc
    exMem.inst := idEx.inst
    exMem.legal := idEx.control.legal
    exMem.aluResult := execute.io.aluResult
    exMem.rd := idEx.rd
    exMem.regWrite := idEx.control.regWrite
    exMem.wbSel := idEx.control.wbSel
    exMem.memRead := idEx.control.memRead
    idEx.valid := false.B
  }.elsewhen(control.io.action === PipelineAction.Advance) {
    memWb.valid := exMem.valid
    memWb.pc := exMem.pc
    memWb.inst := exMem.inst
    memWb.legal := exMem.legal
    memWb.rd := exMem.rd
    memWb.regWrite := exMem.regWrite
    memWb.writeData := exMemForwardValue

    exMem.valid := idEx.valid
    exMem.pc := idEx.pc
    exMem.inst := idEx.inst
    exMem.legal := idEx.control.legal
    exMem.aluResult := execute.io.aluResult
    exMem.rd := idEx.rd
    exMem.regWrite := idEx.control.regWrite
    exMem.wbSel := idEx.control.wbSel
    exMem.memRead := idEx.control.memRead

    idEx.valid := ifId.valid
    idEx.pc := ifId.pc
    idEx.inst := ifId.inst
    idEx.fetchError := ifId.fetchError
    idEx.control := decoder.io.control
    idEx.immediate := decoder.io.immediate
    idEx.rs1 := decoder.io.rs1
    idEx.rs2 := decoder.io.rs2
    idEx.rd := decoder.io.rd
    idEx.rs1Value := regFile.io.rs1Data
    idEx.rs2Value := regFile.io.rs2Data

    ifId.valid := frontend.io.output.valid
    when(frontend.io.output.valid) {
      ifId.pc := frontend.io.output.bits.pc
      ifId.inst := frontend.io.output.bits.inst
      ifId.fetchError := frontend.io.output.bits.error
    }
  }

  io.commit.valid := memWb.valid && memWb.legal
  io.commit.pc := memWb.pc
  io.commit.inst := memWb.inst
  io.commit.writeEnable := memWb.valid && memWb.legal && memWb.regWrite && memWb.rd =/= 0.U
  io.commit.rd := memWb.rd
  io.commit.data := memWb.writeData

  io.trap := 0.U.asTypeOf(new TrapTrace)
  io.halted := false.B
}
