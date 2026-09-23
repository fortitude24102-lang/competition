package gpu

import chisel3._
import chisel3.util._

class ApbSlavePort extends Bundle {
  val paddr = Input(UInt(16.W))
  val psel = Input(Bool())
  val penable = Input(Bool())
  val pwrite = Input(Bool())
  val pwdata = Input(UInt(32.W))
  val prdata = Output(UInt(32.W))
  val pready = Output(Bool())
  val pslverror = Output(Bool())
}

class Efinix2dGpuTop extends Module {
  val io = IO(new Bundle {
    val apb = new ApbSlavePort
    val axi = new Axi4MasterPort
    val vblank = Input(Bool())
    val scanoutLevel = Input(UInt(12.W))
    val underflow_pulse_gpu = Input(Bool())
    val displayReady = Input(Bool())
    val displayPixel = Output(UInt(16.W))
    val displayValid = Output(Bool())
    val displayLineLast = Output(Bool())
    val displayFrameLast = Output(Bool())
    val assetMeta = Flipped(Decoupled(new AssetPacketMeta))
    val assetPayload = Flipped(Decoupled(new AssetPayloadByte))
    val assetStreamError = Input(Bool())
    val assetSession = Output(UInt(32.W))
    val assetActive = Output(Bool())
    val assetDropPacket = Output(Bool())
    val assetAbort = Output(Bool())
    val irq = Output(Bool())
  })

  private val regs = Module(new GpuApbRegs)
  private val assetRegs = Module(new AssetDmaRegs)
  private val assetWriter = Module(new AssetDmaWriter)
  private val render = Module(new RenderEngine)
  private val scanout = Module(new ScanoutDma)
  private val ddr = Module(new DdrQosArbiter)
  private val lastDoneTag = RegInit(0.U(16.W))
  private val lastError = RegInit(GpuError.None.U(8.W))
  private val irq = RegInit(false.B)
  private val scanoutStarted = RegInit(false.B)
  private val scanoutEverEnabled = RegInit(false.B)

  private val assetSelect = io.apb.paddr(15, 8) === 1.U
  regs.io.paddr := io.apb.paddr
  regs.io.psel := io.apb.psel && !assetSelect
  regs.io.penable := io.apb.penable
  regs.io.pwrite := io.apb.pwrite
  regs.io.pwdata := io.apb.pwdata
  assetRegs.io.paddr := io.apb.paddr
  assetRegs.io.psel := io.apb.psel && assetSelect
  assetRegs.io.penable := io.apb.penable
  assetRegs.io.pwrite := io.apb.pwrite
  assetRegs.io.pwdata := io.apb.pwdata
  io.apb.prdata := Mux(assetSelect, assetRegs.io.prdata, regs.io.prdata)
  io.apb.pready := Mux(assetSelect, assetRegs.io.pready, regs.io.pready)
  io.apb.pslverror := Mux(assetSelect, assetRegs.io.pslverror, regs.io.pslverror)

  assetRegs.io.metaIn <> io.assetMeta
  assetWriter.io.meta <> assetRegs.io.metaOut
  assetWriter.io.payload <> io.assetPayload
  assetWriter.io.descriptor := assetRegs.io.descriptor
  assetWriter.io.abort := assetRegs.io.abort
  assetWriter.io.streamError := io.assetStreamError
  assetRegs.io.packetCommitted := assetWriter.io.packetCommitted
  assetRegs.io.packetBytes := assetWriter.io.packetBytes
  assetRegs.io.packetLast := assetWriter.io.packetLast
  assetRegs.io.packetFailed := assetWriter.io.packetFailed
  assetRegs.io.packetError := assetWriter.io.packetError
  assetRegs.io.abortDone := assetWriter.io.abortDone
  io.assetSession := Mux(assetRegs.io.active, assetRegs.io.descriptor.session, 0.U)
  io.assetActive := assetRegs.io.active
  io.assetDropPacket := assetRegs.io.dropPacket
  io.assetAbort := assetRegs.io.abort || assetWriter.io.packetFailed

  render.io.command <> regs.io.command
  render.io.vblank := io.vblank
  regs.io.queueLevel := render.io.queueLevel
  regs.io.queueHighWater := render.io.queueHighWater
  regs.io.queueFull := render.io.queueFull
  regs.io.queueEmpty := render.io.queueEmpty
  regs.io.engineBusy := render.io.busy
  regs.io.irqPending := irq
  regs.io.lastDoneTag := lastDoneTag
  regs.io.lastError := lastError
  regs.io.frontBuffer := render.io.frontBase
  regs.io.backBuffer := render.io.backBase
  regs.io.perfCycles := render.io.perfCycles
  regs.io.perfPixels := render.io.perfPixels
  regs.io.perfReadBytes := render.io.perfReadBytes
  regs.io.perfWriteBytes := render.io.perfWriteBytes
  regs.io.perfStalls := render.io.perfStalls
  regs.io.perfUnderflows := render.io.perfUnderflows
  regs.io.perfRenderGrants := render.io.perfRenderGrants
  regs.io.perfScanoutGrants := render.io.perfScanoutGrants
  render.io.perfClear := regs.io.perfClear
  render.io.underflowPulse := io.underflow_pulse_gpu
  render.io.renderGrant := ddr.io.renderGrant
  render.io.scanoutGrant := ddr.io.scanoutGrant

  render.io.completion.ready := true.B
  when(regs.io.irqClear) { irq := false.B }
  when(render.io.completion.fire) {
    lastDoneTag := render.io.completion.bits.tag
    // Preserve the first failure across later successful completions. This
    // lets software validate a batch even if LAST_DONE advances by >1 tag.
    when(lastError === GpuError.None.U && render.io.completion.bits.error =/= GpuError.None.U) {
      lastError := render.io.completion.bits.error
    }
    irq := true.B
  }

  ddr.io.render <> render.io.axi
  ddr.io.scanout <> scanout.io.axi
  ddr.io.asset <> assetWriter.io.axi
  ddr.io.scanoutLevel := io.scanoutLevel
  ddr.io.lowWatermark := regs.io.qosLowWatermark
  ddr.io.highWatermark := regs.io.qosHighWatermark
  // An empty FIFO before the first frame is not a scanout emergency.
  ddr.io.adaptiveEnable := regs.io.qosAdaptiveEnable && scanoutEverEnabled
  io.axi <> ddr.io.axi

  when(render.io.swapPending) { scanoutStarted := true.B }
  scanout.io.enable := scanoutStarted && !render.io.swapPending
  when(scanout.io.enable) { scanoutEverEnabled := true.B }
  scanout.io.frontBase := render.io.frontBase
  scanout.io.fifoLevel := io.scanoutLevel
  // Continue refilling through hysteresis: one 960-pixel row alone cannot
  // raise a 256-pixel low level to the default 1536-pixel high watermark.
  // The pixel ready/valid handshake still prevents physical FIFO overflow.
  scanout.io.refill := ddr.io.scanoutPriority
  scanout.io.pixel.ready := io.displayReady

  io.displayPixel := scanout.io.pixel.bits.pixel
  io.displayValid := scanout.io.pixel.valid
  io.displayLineLast := scanout.io.pixel.bits.lineLast
  io.displayFrameLast := scanout.io.pixel.bits.frameLast
  io.irq := irq
}
