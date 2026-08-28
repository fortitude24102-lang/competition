package soc

import chisel3._
import chisel3.util._
import cpu.{CommitTrace, CoreBusIO, Rv32Core, TrapTrace}

class VideoStreamIO extends Bundle {
  val pixelIn = Input(UInt(24.W))
  val pixelInValid = Input(Bool())
  val pixelOut = Output(UInt(24.W))
  val pixelOutValid = Output(Bool())
  val busy = Output(Bool())
  val frameDone = Output(Bool())
}

class SoCTop(
  ramWords: Int = 16384,
  ramInitFile: Option[String] = None,
  videoSourcePath: String = "../rtl/video/VideoAccelTop.v"
) extends Module {
  val io = IO(new Bundle {
    val video = new VideoStreamIO
    val uartTx = Decoupled(UInt(8.W))
    val externalImem = new CoreBusIO
    val externalDmem = new CoreBusIO

    val accelEnable = Output(Bool())
    val accelMode = Output(UInt(2.W))
    val accelThreshold = Output(UInt(8.W))
    val accelBypass = Output(Bool())

    val commit = Output(new CommitTrace)
    val trap = Output(new TrapTrace)
    val halted = Output(Bool())
  })

  private val core = Module(new Rv32Core(MemoryMap.BootRamBase))
  private val interconnect = Module(new SoCInterconnect)
  private val ram = Module(new DualPortRam(ramWords, ramInitFile))
  private val uart = Module(new MmioUart)
  private val acceleratorRegisters = Module(new AccelRegs)
  private val videoAccelerator = Module(new VideoAccelExt(videoSourcePath))

  interconnect.io.cpuImem <> core.io.imem
  interconnect.io.cpuDmem <> core.io.dmem
  ram.io.imem <> interconnect.io.ramImem
  ram.io.dmem <> interconnect.io.ramDmem
  uart.io.bus <> interconnect.io.uart
  acceleratorRegisters.io.bus <> interconnect.io.accelerator
  io.externalImem <> interconnect.io.externalImem
  io.externalDmem <> interconnect.io.externalDmem

  io.uartTx <> uart.io.tx

  videoAccelerator.clock := clock
  videoAccelerator.reset := reset.asBool
  videoAccelerator.pixel_in := io.video.pixelIn
  videoAccelerator.pixel_in_valid := io.video.pixelInValid
  videoAccelerator.enable := acceleratorRegisters.io.enable
  videoAccelerator.mode := acceleratorRegisters.io.mode
  videoAccelerator.threshold := acceleratorRegisters.io.threshold
  videoAccelerator.bypass := acceleratorRegisters.io.bypass
  io.video.pixelOut := videoAccelerator.pixel_out
  io.video.pixelOutValid := videoAccelerator.pixel_out_valid
  io.video.busy := videoAccelerator.busy
  io.video.frameDone := videoAccelerator.frame_done

  acceleratorRegisters.io.busy := videoAccelerator.busy
  acceleratorRegisters.io.frameDone := videoAccelerator.frame_done
  io.accelEnable := acceleratorRegisters.io.enable
  io.accelMode := acceleratorRegisters.io.mode
  io.accelThreshold := acceleratorRegisters.io.threshold
  io.accelBypass := acceleratorRegisters.io.bypass

  io.commit := core.io.commit
  io.trap := core.io.trap
  io.halted := core.io.halted
}
