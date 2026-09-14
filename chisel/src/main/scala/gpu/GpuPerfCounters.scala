package gpu

import chisel3._
import chisel3.util.PopCount

/** Free-running render counters; APB exposure and clear control are added with the Day 18 register work. */
class GpuPerfCounters extends Module {
  val io = IO(new Bundle {
    val clear = Input(Bool())
    val active = Input(Bool())
    val pixelDone = Input(Bool())
    val readBeat = Input(Bool())
    val writeStrobe = Input(UInt(4.W))
    val stalled = Input(Bool())
    val cycles = Output(UInt(64.W))
    val pixels = Output(UInt(64.W))
    val readBytes = Output(UInt(64.W))
    val writeBytes = Output(UInt(64.W))
    val stalls = Output(UInt(64.W))
  })

  private val cycles = RegInit(0.U(64.W))
  private val pixels = RegInit(0.U(64.W))
  private val readBytes = RegInit(0.U(64.W))
  private val writeBytes = RegInit(0.U(64.W))
  private val stalls = RegInit(0.U(64.W))

  when(io.clear) {
    cycles := 0.U
    pixels := 0.U
    readBytes := 0.U
    writeBytes := 0.U
    stalls := 0.U
  }.otherwise {
    when(io.active) { cycles := cycles + 1.U }
    when(io.pixelDone) { pixels := pixels + 1.U }
    when(io.readBeat) { readBytes := readBytes + 4.U }
    when(io.writeStrobe.orR) { writeBytes := writeBytes + PopCount(io.writeStrobe) }
    when(io.stalled) { stalls := stalls + 1.U }
  }

  io.cycles := cycles
  io.pixels := pixels
  io.readBytes := readBytes
  io.writeBytes := writeBytes
  io.stalls := stalls
}
