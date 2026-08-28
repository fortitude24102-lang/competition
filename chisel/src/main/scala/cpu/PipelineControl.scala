package cpu

import chisel3._

object ForwardSel extends ChiselEnum {
  val Reg, ExMem, MemWb = Value
}

object PipelineAction extends ChiselEnum {
  val Advance, LoadUseStall, MemoryWait, Redirect, Trap, Reset = Value
}

class PipelineControl extends Module {
  val io = IO(new Bundle {
    val exRs1 = Input(UInt(5.W))
    val exRs2 = Input(UInt(5.W))
    val exRs1Used = Input(Bool())
    val exRs2Used = Input(Bool())
    val exMemValid = Input(Bool())
    val exMemRegWrite = Input(Bool())
    val exMemResultReady = Input(Bool())
    val exMemRd = Input(UInt(5.W))
    val memWbValid = Input(Bool())
    val memWbRegWrite = Input(Bool())
    val memWbRd = Input(UInt(5.W))
    val idRs1 = Input(UInt(5.W))
    val idRs2 = Input(UInt(5.W))
    val idRs1Used = Input(Bool())
    val idRs2Used = Input(Bool())
    val idExValid = Input(Bool())
    val idExMemRead = Input(Bool())
    val idExRd = Input(UInt(5.W))
    val resetActive = Input(Bool())
    val trap = Input(Bool())
    val redirect = Input(Bool())
    val memoryWait = Input(Bool())
    val forwardRs1 = Output(ForwardSel())
    val forwardRs2 = Output(ForwardSel())
    val loadUseStall = Output(Bool())
    val action = Output(PipelineAction())
  })

  private def forwarding(source: UInt, used: Bool): ForwardSel.Type = {
    val selection = WireDefault(ForwardSel.Reg)
    when(used && io.memWbValid && io.memWbRegWrite && io.memWbRd =/= 0.U && io.memWbRd === source) {
      selection := ForwardSel.MemWb
    }
    when(used && io.exMemValid && io.exMemRegWrite && io.exMemResultReady && io.exMemRd =/= 0.U && io.exMemRd === source) {
      selection := ForwardSel.ExMem
    }
    selection
  }

  io.forwardRs1 := forwarding(io.exRs1, io.exRs1Used)
  io.forwardRs2 := forwarding(io.exRs2, io.exRs2Used)

  val rs1LoadDependency = io.idRs1Used && io.idRs1 === io.idExRd
  val rs2LoadDependency = io.idRs2Used && io.idRs2 === io.idExRd
  io.loadUseStall := io.idExValid && io.idExMemRead && io.idExRd =/= 0.U && (rs1LoadDependency || rs2LoadDependency)

  io.action := PipelineAction.Advance
  when(io.resetActive) {
    io.action := PipelineAction.Reset
  }.elsewhen(io.trap) {
    io.action := PipelineAction.Trap
  }.elsewhen(io.redirect) {
    io.action := PipelineAction.Redirect
  }.elsewhen(io.memoryWait) {
    io.action := PipelineAction.MemoryWait
  }.elsewhen(io.loadUseStall) {
    io.action := PipelineAction.LoadUseStall
  }
}
