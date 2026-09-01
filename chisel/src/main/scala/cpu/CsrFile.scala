package cpu

import chisel3._
import chisel3.util._

object CsrAddress {
  val Mstatus = 0x300
  val Misa = 0x301
  val Mie = 0x304
  val Mtvec = 0x305
  val Mscratch = 0x340
  val Mepc = 0x341
  val Mcause = 0x342
  val Mtval = 0x343
  val Mip = 0x344
  val Mhartid = 0xf14
}

class CsrFile extends Module {
  val io = IO(new Bundle {
    val address = Input(UInt(12.W))
    val readData = Output(UInt(32.W))
    val readLegal = Output(Bool())
    val writeAllowed = Output(Bool())
    val writeValid = Input(Bool())
    val writeData = Input(UInt(32.W))

    val trapValid = Input(Bool())
    val trapPc = Input(UInt(32.W))
    val trapCause = Input(UInt(31.W))
    val trapInterrupt = Input(Bool())
    val trapValue = Input(UInt(32.W))
    val mretValid = Input(Bool())

    val timerInterrupt = Input(Bool())
    val timerInterruptPending = Output(Bool())
    val trapVector = Output(UInt(32.W))
    val returnPc = Output(UInt(32.W))
  })

  private val machineInterruptEnable = RegInit(false.B)
  private val machinePreviousInterruptEnable = RegInit(false.B)
  private val timerInterruptEnable = RegInit(false.B)
  private val mtvec = RegInit(0.U(32.W))
  private val mscratch = RegInit(0.U(32.W))
  private val mepc = RegInit(0.U(32.W))
  private val mcause = RegInit(0.U(32.W))
  private val mtval = RegInit(0.U(32.W))

  private val isMstatus = io.address === CsrAddress.Mstatus.U
  private val isMisa = io.address === CsrAddress.Misa.U
  private val isMie = io.address === CsrAddress.Mie.U
  private val isMtvec = io.address === CsrAddress.Mtvec.U
  private val isMscratch = io.address === CsrAddress.Mscratch.U
  private val isMepc = io.address === CsrAddress.Mepc.U
  private val isMcause = io.address === CsrAddress.Mcause.U
  private val isMtval = io.address === CsrAddress.Mtval.U
  private val isMip = io.address === CsrAddress.Mip.U
  private val isMhartid = io.address === CsrAddress.Mhartid.U

  private val mstatusRead = "h00001800".U(32.W) |
    (machinePreviousInterruptEnable.asUInt << 7) |
    (machineInterruptEnable.asUInt << 3)
  private val mieRead = timerInterruptEnable.asUInt << 7
  private val mipRead = io.timerInterrupt.asUInt << 7

  io.readLegal := isMstatus || isMisa || isMie || isMtvec || isMscratch ||
    isMepc || isMcause || isMtval || isMip || isMhartid
  io.writeAllowed := isMstatus || isMie || isMtvec || isMscratch ||
    isMepc || isMcause || isMtval || isMip
  io.readData := MuxCase(0.U, Seq(
    isMstatus -> mstatusRead,
    isMisa -> "h40000100".U,
    isMie -> mieRead,
    isMtvec -> mtvec,
    isMscratch -> mscratch,
    isMepc -> mepc,
    isMcause -> mcause,
    isMtval -> mtval,
    isMip -> mipRead,
    isMhartid -> 0.U
  ))

  io.trapVector := mtvec
  io.returnPc := mepc
  io.timerInterruptPending := io.timerInterrupt && timerInterruptEnable && machineInterruptEnable

  when(io.trapValid) {
    machinePreviousInterruptEnable := machineInterruptEnable
    machineInterruptEnable := false.B
    mepc := Cat(io.trapPc(31, 2), 0.U(2.W))
    mcause := Cat(io.trapInterrupt, io.trapCause)
    mtval := io.trapValue
  }.elsewhen(io.mretValid) {
    machineInterruptEnable := machinePreviousInterruptEnable
    machinePreviousInterruptEnable := true.B
  }.elsewhen(io.writeValid && io.writeAllowed) {
    switch(io.address) {
      is(CsrAddress.Mstatus.U) {
        machineInterruptEnable := io.writeData(3)
        machinePreviousInterruptEnable := io.writeData(7)
      }
      is(CsrAddress.Mie.U) {
        timerInterruptEnable := io.writeData(7)
      }
      is(CsrAddress.Mtvec.U) {
        mtvec := Cat(io.writeData(31, 2), 0.U(2.W))
      }
      is(CsrAddress.Mscratch.U) {
        mscratch := io.writeData
      }
      is(CsrAddress.Mepc.U) {
        mepc := Cat(io.writeData(31, 2), 0.U(2.W))
      }
      is(CsrAddress.Mcause.U) {
        mcause := io.writeData
      }
      is(CsrAddress.Mtval.U) {
        mtval := io.writeData
      }
    }
  }
}
