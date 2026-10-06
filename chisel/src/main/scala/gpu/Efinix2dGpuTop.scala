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

class Efinix2dGpuTop(enableCopyStream: Boolean = true, enableInstances: Boolean = false) extends Module {
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

  private val regs = Module(new GpuApbRegs(enableInstances))
  private val instances = if (enableInstances) Some(Module(new InstanceStream)) else None
  private val assetRegs = Module(new AssetDmaRegs)
  private val assetWriter = Module(new AssetDmaWriter)
  private val render = Module(new RenderEngine(enableCopyStream))
  private val scanout = Module(new ScanoutDma)
  private val ddr = Module(new DdrQosArbiter)
  private val lastDoneTag = RegInit(0.U(16.W))
  private val lastError = RegInit(GpuError.None.U(8.W))
  private val irq = RegInit(false.B)
  private val scanoutStarted = RegInit(false.B)
  private val scanoutEverEnabled = RegInit(false.B)

  private val assetSelect = io.apb.paddr(15, 8) === 1.U
  private val instanceSelect = if (enableInstances) io.apb.paddr(15, 8) === 4.U else false.B
  private val instanceActive = instances.map(_.io.active).getOrElse(false.B)
  // Candidate-only response stage: break the decoded read mux -> Sapphire
  // path without changing the default legacy APB timing or register ABI.
  private val responseValid = if (enableInstances) RegInit(false.B) else false.B
  private val localSelect = io.apb.psel && !responseValid
  private val responseData = WireDefault(Mux(assetSelect, assetRegs.io.prdata, regs.io.prdata))
  private val responseReady = WireDefault(Mux(assetSelect, assetRegs.io.pready, regs.io.pready))
  private val responseError = WireDefault(Mux(assetSelect, assetRegs.io.pslverror, regs.io.pslverror))
  regs.io.paddr := io.apb.paddr
  regs.io.psel := localSelect && !assetSelect && !instanceSelect
  regs.io.penable := io.apb.penable
  regs.io.pwrite := io.apb.pwrite
  regs.io.pwdata := io.apb.pwdata
  assetRegs.io.paddr := io.apb.paddr
  assetRegs.io.psel := localSelect && assetSelect
  assetRegs.io.penable := io.apb.penable
  assetRegs.io.pwrite := io.apb.pwrite
  assetRegs.io.pwdata := io.apb.pwdata
  instances.foreach { frontend =>
    frontend.io.apb.paddr := io.apb.paddr
    frontend.io.apb.psel := localSelect && instanceSelect
    frontend.io.apb.penable := io.apb.penable
    frontend.io.apb.pwrite := io.apb.pwrite
    frontend.io.apb.pwdata := io.apb.pwdata
    frontend.io.idle := !render.io.busy && !render.io.textureCacheBusy
    frontend.io.hardwareError := lastError
    when(instanceSelect) {
      responseData := frontend.io.apb.prdata
      responseReady := frontend.io.apb.pready
      responseError := frontend.io.apb.pslverror
    }
  }
  if (enableInstances) {
    val data = Reg(UInt(32.W))
    val error = RegInit(false.B)
    when(localSelect && io.apb.penable && responseReady) {
      data := responseData
      error := responseError
      responseValid := true.B
    }
    when(!io.apb.psel || !io.apb.penable || responseValid) {
      responseValid := false.B
    }
    io.apb.prdata := data
    io.apb.pready := responseValid && io.apb.psel && io.apb.penable
    io.apb.pslverror := io.apb.pready && error
  } else {
    io.apb.prdata := responseData
    io.apb.pready := responseReady
    io.apb.pslverror := responseError
  }

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

  render.io.command.valid := regs.io.command.valid && !instanceActive
  render.io.command.bits := regs.io.command.bits
  regs.io.command.ready := render.io.command.ready && !instanceActive
  instances.foreach { frontend =>
    frontend.io.command.ready := render.io.command.ready && instanceActive
    when(instanceActive) {
      render.io.command.valid := frontend.io.command.valid
      render.io.command.bits := frontend.io.command.bits
    }
  }
  render.io.vblank := io.vblank
  regs.io.queueLevel := render.io.queueLevel
  regs.io.queueHighWater := render.io.queueHighWater
  regs.io.queueFull := render.io.queueFull || instanceActive
  regs.io.queueEmpty := render.io.queueEmpty && !instanceActive
  regs.io.engineBusy := render.io.busy || instanceActive
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
  regs.io.perfCacheBytes := render.io.perfCacheBytes
  regs.io.textureCacheValid := render.io.textureCacheValid
  regs.io.textureCacheBusy := render.io.textureCacheBusy
  regs.io.textureCacheError := render.io.textureCacheError
  render.io.textureCacheLoad := regs.io.textureCacheLoad
  render.io.textureCacheInvalidate := regs.io.textureCacheInvalidate
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
