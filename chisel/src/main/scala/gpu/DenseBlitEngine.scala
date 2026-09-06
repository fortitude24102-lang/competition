package gpu

import chisel3._
import chisel3.util._

class DenseBlitEngine extends Module {
  val io = IO(new Bundle {
    val command = Flipped(Decoupled(new GpuCommand))
    val pixelRequest = Decoupled(new PixelTransaction)
    val pixelResult = Flipped(Decoupled(new PixelResult))
    val axi = new Axi4MasterPort
    val completion = Decoupled(new GpuCompletion)
  })

  private val rect = Module(new RectAddressGen)
  private val packer = Module(new PixelWritePacker)
  private val writer = Module(new AxiWriteEngine)

  private val idle :: launchFirstRow :: launchRow :: requestPixel :: waitPixel :: waitRow :: finish :: Nil = Enum(7)
  private val state = RegInit(idle)
  private val commandReg = Reg(new GpuCommand)
  private val rowBase = Reg(UInt(32.W))
  private val pixelAddress = Reg(UInt(32.W))
  private val pixelRowLast = Reg(Bool())
  private val pixelLast = Reg(Bool())
  private val completionError = RegInit(GpuError.None.U(8.W))

  io.command.ready := state === idle
  when(io.command.fire) {
    commandReg := io.command.bits
    rowBase := io.command.bits.dstAddr
    completionError := GpuError.None.U
    state := launchFirstRow
  }

  private val firstLaunch = state === launchFirstRow
  private val laterLaunch = state === launchRow
  private val launching = firstLaunch || laterLaunch
  private val rowBytes = Cat(0.U(15.W), commandReg.widthPixels, 0.U(1.W))
  private val rowTransferBytes = rowBytes + rowBase(1, 0)
  private val rowBeats = (rowTransferBytes + 3.U) >> 2

  rect.io.start.valid := firstLaunch && writer.io.request.ready
  rect.io.start.bits.base := commandReg.dstAddr
  rect.io.start.bits.widthPixels := commandReg.widthPixels
  rect.io.start.bits.heightPixels := commandReg.heightPixels
  rect.io.start.bits.stride := commandReg.dstStride

  writer.io.request.valid := launching && (laterLaunch || rect.io.start.ready)
  writer.io.request.bits.address := rowBase
  writer.io.request.bits.beats := rowBeats

  when(writer.io.request.fire && (laterLaunch || rect.io.start.fire)) {
    state := requestPixel
  }

  io.pixelRequest.valid := state === requestPixel && rect.io.address.valid
  io.pixelRequest.bits.op := commandReg.op(2, 0)
  io.pixelRequest.bits.foreground := 0.U
  io.pixelRequest.bits.background := 0.U
  io.pixelRequest.bits.fillColor := commandReg.color
  io.pixelRequest.bits.colorKey := commandReg.colorKey
  io.pixelRequest.bits.alpha := commandReg.alpha
  rect.io.address.ready := state === requestPixel && io.pixelRequest.ready

  when(io.pixelRequest.fire) {
    pixelAddress := rect.io.address.bits.address
    pixelRowLast := rect.io.address.bits.rowLast
    pixelLast := rect.io.address.bits.last
    state := waitPixel
  }

  packer.io.input.valid := state === waitPixel && io.pixelResult.valid
  packer.io.input.bits.address := pixelAddress
  packer.io.input.bits.pixel := io.pixelResult.bits.pixel
  packer.io.input.bits.writeEnable := io.pixelResult.bits.writeEnable
  packer.io.input.bits.rowLast := pixelRowLast
  io.pixelResult.ready := state === waitPixel && packer.io.input.ready

  when(io.pixelResult.fire) {
    state := Mux(pixelRowLast, waitRow, requestPixel)
  }

  writer.io.data.valid := packer.io.output.valid
  writer.io.data.bits.data := packer.io.output.bits.data
  writer.io.data.bits.strb := packer.io.output.bits.strb
  packer.io.output.ready := writer.io.data.ready

  when(state === waitRow && writer.io.done) {
    when(writer.io.error) {
      completionError := GpuError.AxiResponse.U
      state := finish
    }.elsewhen(pixelLast) {
      state := finish
    }.otherwise {
      rowBase := rowBase + commandReg.dstStride
      state := launchRow
    }
  }

  io.completion.valid := state === finish
  io.completion.bits.tag := commandReg.tag
  io.completion.bits.error := completionError
  when(io.completion.fire) {
    state := idle
  }

  io.axi.aw.valid := writer.io.axiAw.valid
  io.axi.aw.bits := writer.io.axiAw.bits
  writer.io.axiAw.ready := io.axi.aw.ready
  io.axi.w.valid := writer.io.axiW.valid
  io.axi.w.bits := writer.io.axiW.bits
  writer.io.axiW.ready := io.axi.w.ready
  writer.io.axiB.valid := io.axi.b.valid
  writer.io.axiB.bits := io.axi.b.bits
  io.axi.b.ready := writer.io.axiB.ready

  io.axi.ar.valid := false.B
  io.axi.ar.bits := 0.U.asTypeOf(new Axi4Address)
  io.axi.r.ready := false.B
}
