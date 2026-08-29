package soc

import chisel3._
import chisel3.util._
import cpu.{CommitTrace, CoreBusIO, CoreBusReq, CoreBusResp, Rv32Core, TrapTrace}

class VideoStreamIO extends Bundle {
  val input = Flipped(Decoupled(new StreamBeat(24)))
  val output = Decoupled(new StreamBeat(24))
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
  private val externalImemRequest = Module(new Queue(new CoreBusReq, 1, pipe = false, flow = false))
  private val externalImemResponse = Module(new Queue(new CoreBusResp, 1, pipe = false, flow = false))
  private val externalDmemRequest = Module(new Queue(new CoreBusReq, 1, pipe = false, flow = false))
  private val externalDmemResponse = Module(new Queue(new CoreBusResp, 1, pipe = false, flow = false))

  interconnect.io.cpuImem <> core.io.imem
  interconnect.io.cpuDmem <> core.io.dmem
  ram.io.imem <> interconnect.io.ramImem
  ram.io.dmem <> interconnect.io.ramDmem
  uart.io.bus <> interconnect.io.uart
  acceleratorRegisters.io.bus <> interconnect.io.accelerator
  externalImemRequest.io.enq <> interconnect.io.externalImem.req
  io.externalImem.req <> externalImemRequest.io.deq
  externalImemResponse.io.enq <> io.externalImem.resp
  interconnect.io.externalImem.resp <> externalImemResponse.io.deq
  externalDmemRequest.io.enq <> interconnect.io.externalDmem.req
  io.externalDmem.req <> externalDmemRequest.io.deq
  externalDmemResponse.io.enq <> io.externalDmem.resp
  interconnect.io.externalDmem.resp <> externalDmemResponse.io.deq

  io.uartTx <> uart.io.tx

  videoAccelerator.clock := clock
  videoAccelerator.reset := reset.asBool
  videoAccelerator.pixel_in := io.video.input.bits.data
  videoAccelerator.pixel_in_valid := io.video.input.valid
  io.video.input.ready := videoAccelerator.pixel_in_ready
  videoAccelerator.pixel_in_start_of_frame := io.video.input.bits.startOfFrame
  videoAccelerator.pixel_in_end_of_line := io.video.input.bits.endOfLine
  videoAccelerator.pixel_in_end_of_frame := io.video.input.bits.endOfFrame
  videoAccelerator.enable := acceleratorRegisters.io.enable
  videoAccelerator.mode := acceleratorRegisters.io.mode
  videoAccelerator.threshold := acceleratorRegisters.io.threshold
  videoAccelerator.bypass := acceleratorRegisters.io.bypass
  io.video.output.bits.data := videoAccelerator.pixel_out
  io.video.output.valid := videoAccelerator.pixel_out_valid
  videoAccelerator.pixel_out_ready := io.video.output.ready
  io.video.output.bits.startOfFrame := videoAccelerator.pixel_out_start_of_frame
  io.video.output.bits.endOfLine := videoAccelerator.pixel_out_end_of_line
  io.video.output.bits.endOfFrame := videoAccelerator.pixel_out_end_of_frame
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
