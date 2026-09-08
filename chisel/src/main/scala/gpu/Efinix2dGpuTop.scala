package gpu

import chisel3._

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
    val displayReady = Input(Bool())
    val displayPixel = Output(UInt(16.W))
    val displayValid = Output(Bool())
    val displayLineLast = Output(Bool())
    val displayFrameLast = Output(Bool())
    val irq = Output(Bool())
  })

  private val regs = Module(new GpuApbRegs)
  private val render = Module(new RenderEngine)
  private val scanout = Module(new ScanoutDma)
  private val ddr = Module(new DdrQosArbiter)
  private val lastDoneTag = RegInit(0.U(16.W))
  private val lastError = RegInit(GpuError.None.U(8.W))
  private val irq = RegInit(false.B)

  regs.io.paddr := io.apb.paddr
  regs.io.psel := io.apb.psel
  regs.io.penable := io.apb.penable
  regs.io.pwrite := io.apb.pwrite
  regs.io.pwdata := io.apb.pwdata
  io.apb.prdata := regs.io.prdata
  io.apb.pready := regs.io.pready
  io.apb.pslverror := regs.io.pslverror

  render.io.command <> regs.io.command
  regs.io.queueLevel := render.io.queueLevel
  regs.io.queueFull := render.io.queueFull
  regs.io.queueEmpty := render.io.queueEmpty
  regs.io.engineBusy := render.io.busy
  regs.io.lastDoneTag := lastDoneTag
  regs.io.lastError := lastError

  render.io.completion.ready := true.B
  irq := false.B
  when(render.io.completion.fire) {
    lastDoneTag := render.io.completion.bits.tag
    lastError := render.io.completion.bits.error
    irq := true.B
  }

  ddr.io.render <> render.io.axi
  ddr.io.scanout <> scanout.io.axi
  io.axi <> ddr.io.axi

  scanout.io.enable := true.B
  scanout.io.frontBase := GpuMemoryMap.FramebufferA.U
  scanout.io.fifoLevel := io.scanoutLevel
  scanout.io.pixel.ready := io.displayReady

  io.displayPixel := scanout.io.pixel.bits.pixel
  io.displayValid := scanout.io.pixel.valid
  io.displayLineLast := scanout.io.pixel.bits.lineLast
  io.displayFrameLast := scanout.io.pixel.bits.frameLast
  io.irq := irq
}
