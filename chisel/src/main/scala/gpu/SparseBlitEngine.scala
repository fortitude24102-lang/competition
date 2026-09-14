package gpu

import chisel3._
import chisel3.util._

/** Reads a sparse token stream and writes only literal RGB565 pixels. */
class SparseBlitEngine extends Module {
  val io = IO(new Bundle {
    val command = Flipped(Decoupled(new GpuCommand))
    val axi = new Axi4MasterPort
    val completion = Decoupled(new GpuCompletion)
    val busy = Output(Bool())
    val pixelDone = Output(Bool())
  })

  private val reader = Module(new AxiReadEngine)
  private val decoder = Module(new SparseDecoder)
  private val packer = Module(new PixelWritePacker)
  private val writer = Module(new AxiWriteEngine)
  private val idle :: startDecoder :: run :: finish :: Nil = Enum(4)
  private val state = RegInit(idle)
  private val command = Reg(new GpuCommand)
  private val tokenAddress = Reg(UInt(32.W))
  private val wordValid = RegInit(false.B)
  private val word = Reg(UInt(32.W))
  private val readOutstanding = RegInit(false.B)
  private val writeOutstanding = RegInit(false.B)
  private val error = RegInit(GpuError.None.U(8.W))
  private val errorFlushDone = RegInit(false.B)

  io.command.ready := state === idle
  io.busy := state =/= idle
  io.pixelDone := false.B
  when(io.command.fire) {
    command := io.command.bits
    tokenAddress := io.command.bits.srcAddr
    wordValid := false.B
    readOutstanding := false.B
    writeOutstanding := false.B
    error := GpuError.None.U
    errorFlushDone := false.B
    state := startDecoder
  }

  decoder.io.start.valid := state === startDecoder
  decoder.io.start.bits.widthPixels := command.widthPixels
  decoder.io.start.bits.heightPixels := command.heightPixels
  when(decoder.io.start.fire) { state := run }

  private val failed = error =/= GpuError.None.U || decoder.io.error
  private val tokenInRange = tokenAddress <= (GpuMemoryMap.DdrEndExclusive - 4).U
  private val needsWord = state === run && !failed && decoder.io.input.ready &&
    !wordValid && !readOutstanding && !decoder.io.done
  reader.io.request.valid := needsWord && tokenInRange
  reader.io.request.bits.address := tokenAddress
  reader.io.request.bits.bytes := 4.U
  when(reader.io.request.fire) {
    tokenAddress := tokenAddress + 4.U
    readOutstanding := true.B
  }
  when(needsWord && !tokenInRange) { error := GpuError.AddressRange.U }

  reader.io.data.ready := failed || !wordValid
  when(reader.io.data.fire) {
    when(failed) {
      wordValid := false.B
    }.otherwise {
      word := reader.io.data.bits.data
      wordValid := true.B
    }
  }
  when(reader.io.done) {
    readOutstanding := false.B
    when(reader.io.error) { error := GpuError.AxiResponse.U }
  }

  decoder.io.input.valid := wordValid && !failed
  decoder.io.input.bits := word
  when(decoder.io.input.fire) { wordValid := false.B }
  when(failed) { wordValid := false.B }
  decoder.io.abort := state === finish || failed || reader.io.error

  private val errorFlush = state === run && failed && !errorFlushDone
  packer.io.input.valid := (state === run && decoder.io.output.valid && !failed) || errorFlush
  private val rowOffset = (decoder.io.output.bits.y * command.dstStride)(31, 0)
  private val pixelOffset = Cat(0.U(15.W), decoder.io.output.bits.x, 0.U(1.W))
  packer.io.input.bits.address := Mux(
    errorFlush,
    command.dstAddr + Cat(0.U(15.W), command.widthPixels, 0.U(1.W)),
    command.dstAddr + rowOffset + pixelOffset
  )
  packer.io.input.bits.pixel := decoder.io.output.bits.pixel
  packer.io.input.bits.writeEnable := decoder.io.output.bits.writeEnable && !errorFlush
  packer.io.input.bits.rowLast := decoder.io.output.bits.rowLast || errorFlush
  decoder.io.output.ready := state === run && !failed && packer.io.input.ready
  when(errorFlush && packer.io.input.fire) { errorFlushDone := true.B }
  when(packer.io.input.fire && packer.io.input.bits.writeEnable) { io.pixelDone := true.B }

  writer.io.request.valid := state === run && !failed && packer.io.output.valid && !writeOutstanding
  writer.io.request.bits.address := packer.io.output.bits.address
  writer.io.request.bits.beats := 1.U
  when(writer.io.request.fire) { writeOutstanding := true.B }
  writer.io.data.valid := packer.io.output.valid && (!failed || writeOutstanding)
  writer.io.data.bits.data := packer.io.output.bits.data
  writer.io.data.bits.strb := packer.io.output.bits.strb
  packer.io.output.ready := Mux(failed && !writeOutstanding, true.B, writer.io.data.ready)
  when(writer.io.done) {
    writeOutstanding := false.B
    when(writer.io.error) { error := GpuError.AxiResponse.U }
  }

  when(state === run && decoder.io.done && decoder.io.error && error === GpuError.None.U) {
    error := GpuError.SparseFormat.U
  }
  private val decodeFinished = decoder.io.done || error =/= GpuError.None.U
  private val flushFinished = !failed || errorFlushDone
  when(state === run && decodeFinished && flushFinished && !wordValid && !readOutstanding &&
      !writeOutstanding && !packer.io.output.valid && writer.io.request.ready) {
    state := finish
  }

  io.completion.valid := state === finish
  io.completion.bits.tag := command.tag
  io.completion.bits.error := error
  when(io.completion.fire) { state := idle }

  io.axi.ar.valid := reader.io.axiAr.valid
  io.axi.ar.bits := reader.io.axiAr.bits
  reader.io.axiAr.ready := io.axi.ar.ready
  reader.io.axiR.valid := io.axi.r.valid
  reader.io.axiR.bits := io.axi.r.bits
  io.axi.r.ready := reader.io.axiR.ready
  io.axi.aw.valid := writer.io.axiAw.valid
  io.axi.aw.bits := writer.io.axiAw.bits
  writer.io.axiAw.ready := io.axi.aw.ready
  io.axi.w.valid := writer.io.axiW.valid
  io.axi.w.bits := writer.io.axiW.bits
  writer.io.axiW.ready := io.axi.w.ready
  writer.io.axiB.valid := io.axi.b.valid
  writer.io.axiB.bits := io.axi.b.bits
  io.axi.b.ready := writer.io.axiB.ready
}
