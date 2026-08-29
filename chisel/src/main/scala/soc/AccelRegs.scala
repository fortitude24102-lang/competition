package soc

import chisel3._
import chisel3.util._

class AccelRegs extends Module {
  val io = IO(new Bundle {
    val bus = new SocBusTargetIO
    val busy = Input(Bool())
    val frameDone = Input(Bool())
    val inputAccepted = Input(Bool())
    val outputAccepted = Input(Bool())
    val outputStalled = Input(Bool())
    val enable = Output(Bool())
    val mode = Output(UInt(2.W))
    val threshold = Output(UInt(8.W))
    val bypass = Output(Bool())
  })

  private val enableReg = RegInit(false.B)
  private val modeReg = RegInit(0.U(2.W))
  private val thresholdReg = RegInit(128.U(8.W))
  private val bypassReg = RegInit(true.B)
  private val cycleCount = RegInit(0.U(32.W))
  private val inputCount = RegInit(0.U(32.W))
  private val outputCount = RegInit(0.U(32.W))
  private val frameCount = RegInit(0.U(32.W))
  private val stallCount = RegInit(0.U(32.W))
  private val busyCycles = RegInit(0.U(32.W))
  private val responseValid = RegInit(false.B)
  private val responseData = RegInit(0.U(32.W))
  private val responseError = RegInit(false.B)

  io.enable := enableReg
  io.mode := modeReg
  io.threshold := thresholdReg
  io.bypass := bypassReg

  io.bus.req.ready := !responseValid
  io.bus.resp.valid := responseValid
  io.bus.resp.bits.rdata := responseData
  io.bus.resp.bits.error := responseError

  private val clearPerformanceCounters = WireDefault(false.B)

  when(clearPerformanceCounters) {
    cycleCount := 0.U
    inputCount := 0.U
    outputCount := 0.U
    frameCount := 0.U
    stallCount := 0.U
    busyCycles := 0.U
  }.otherwise {
    cycleCount := cycleCount + 1.U
    when(io.inputAccepted) { inputCount := inputCount + 1.U }
    when(io.outputAccepted) { outputCount := outputCount + 1.U }
    when(io.frameDone) { frameCount := frameCount + 1.U }
    when(io.outputStalled) { stallCount := stallCount + 1.U }
    when(io.busy) { busyCycles := busyCycles + 1.U }
  }

  when(io.bus.resp.fire) {
    responseValid := false.B
  }

  when(io.bus.req.fire) {
    val offset = io.bus.req.bits.addr(11, 0)
    val legalWord = io.bus.req.bits.size === 2.U && io.bus.req.bits.addr(1, 0) === 0.U
    val readData = WireDefault(0.U(32.W))
    val readable = WireDefault(false.B)
    val writable = WireDefault(false.B)

    switch(offset) {
      is(MemoryMap.Accelerator.ControlOffset.U) {
        readData := enableReg
        readable := true.B
        writable := true.B
      }
      is(MemoryMap.Accelerator.StatusOffset.U) {
        readData := Cat(0.U(30.W), io.frameDone, io.busy)
        readable := true.B
      }
      is(MemoryMap.Accelerator.ModeOffset.U) {
        readData := modeReg
        readable := true.B
        writable := true.B
      }
      is(MemoryMap.Accelerator.ThresholdOffset.U) {
        readData := thresholdReg
        readable := true.B
        writable := true.B
      }
      is(MemoryMap.Accelerator.BypassOffset.U) {
        readData := bypassReg
        readable := true.B
        writable := true.B
      }
      is(MemoryMap.Accelerator.PerfControlOffset.U) {
        readData := 0.U
        readable := true.B
        writable := true.B
      }
      is(MemoryMap.Accelerator.CycleCountOffset.U) {
        readData := cycleCount
        readable := true.B
      }
      is(MemoryMap.Accelerator.InputCountOffset.U) {
        readData := inputCount
        readable := true.B
      }
      is(MemoryMap.Accelerator.OutputCountOffset.U) {
        readData := outputCount
        readable := true.B
      }
      is(MemoryMap.Accelerator.FrameCountOffset.U) {
        readData := frameCount
        readable := true.B
      }
      is(MemoryMap.Accelerator.StallCountOffset.U) {
        readData := stallCount
        readable := true.B
      }
      is(MemoryMap.Accelerator.BusyCyclesOffset.U) {
        readData := busyCycles
        readable := true.B
      }
    }

    val accessError = !legalWord || Mux(io.bus.req.bits.write, !writable, !readable)
    responseValid := true.B
    responseData := Mux(io.bus.req.bits.write || accessError, 0.U, readData)
    responseError := accessError

    when(io.bus.req.bits.write && writable && legalWord && io.bus.req.bits.wstrb(0)) {
      switch(offset) {
        is(MemoryMap.Accelerator.ControlOffset.U) {
          enableReg := io.bus.req.bits.wdata(0)
        }
        is(MemoryMap.Accelerator.ModeOffset.U) {
          modeReg := io.bus.req.bits.wdata(1, 0)
        }
        is(MemoryMap.Accelerator.ThresholdOffset.U) {
          thresholdReg := io.bus.req.bits.wdata(7, 0)
        }
        is(MemoryMap.Accelerator.BypassOffset.U) {
          bypassReg := io.bus.req.bits.wdata(0)
        }
        is(MemoryMap.Accelerator.PerfControlOffset.U) {
          clearPerformanceCounters := io.bus.req.bits.wdata(0)
        }
      }
    }
  }
}
