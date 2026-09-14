package gpu

import chisel3._
import chisel3.util.Cat
import org.scalatest.funspec.AnyFunSpec
import org.scalatest.matchers.should.Matchers
import testutil.StableChiselSim

class ScanoutDmaProductionHarness extends Module {
  val io = IO(new Bundle {
    val done = Output(Bool())
    val mismatch = Output(Bool())
    val mismatchCode = Output(UInt(4.W))
    val mismatchAt = Output(UInt(19.W))
    val mismatchActual = Output(UInt(16.W))
    val pixelCount = Output(UInt(19.W))
    val lineCount = Output(UInt(10.W))
    val frameLastCount = Output(UInt(2.W))
    val frameCrc = Output(UInt(32.W))
  })

  private val scanout = Module(new ScanoutDma)
  private val base = GpuMemoryMap.FramebufferA.U(32.W)
  private val readAddress = RegInit(base)
  private val readBeats = RegInit(0.U(9.W))
  private val done = RegInit(false.B)
  private val stopRequested = RegInit(false.B)
  private val mismatch = RegInit(false.B)
  private val mismatchCode = RegInit(0.U(4.W))
  private val mismatchAt = RegInit(0.U(19.W))
  private val mismatchActual = RegInit(0.U(16.W))
  private val pixelCount = RegInit(0.U(19.W))
  private val lineCount = RegInit(0.U(10.W))
  private val frameLastCount = RegInit(0.U(2.W))
  private val crc = RegInit("hffffffff".U(32.W))
  private val frameCrc = RegInit(0.U(32.W))

  scanout.io.enable := !stopRequested
  scanout.io.frontBase := base
  scanout.io.fifoLevel := 0.U
  scanout.io.pixel.ready := true.B
  scanout.io.axi.ar.ready := readBeats === 0.U
  scanout.io.axi.aw.ready := true.B
  scanout.io.axi.w.ready := true.B
  scanout.io.axi.b.valid := false.B
  scanout.io.axi.b.bits := 0.U.asTypeOf(new Axi4WriteResponse)

  private val firstPixel = ((readAddress - base) >> 1)(15, 0)
  scanout.io.axi.r.valid := readBeats =/= 0.U
  scanout.io.axi.r.bits.id := 0.U
  scanout.io.axi.r.bits.data := Cat(firstPixel + 1.U, firstPixel)
  scanout.io.axi.r.bits.resp := Axi4.Okay.U
  scanout.io.axi.r.bits.last := readBeats === 1.U

  when(scanout.io.axi.ar.fire) {
    readAddress := scanout.io.axi.ar.bits.addr
    readBeats := Cat(0.U(1.W), scanout.io.axi.ar.bits.len) + 1.U
  }
  when(scanout.io.axi.r.fire) {
    readAddress := readAddress + 4.U
    readBeats := readBeats - 1.U
  }

  private def crcByte(initial: UInt, data: UInt): UInt = {
    var next = initial ^ data
    for (_ <- 0 until 8) {
      next = Mux(next(0), (next >> 1) ^ "hedb88320".U, next >> 1)
    }
    next
  }
  private val crcAfterPixel = crcByte(crcByte(crc, scanout.io.pixel.bits.pixel(7, 0)), scanout.io.pixel.bits.pixel(15, 8))

  when(scanout.io.pixel.fire) {
    when(scanout.io.pixel.bits.pixel =/= pixelCount(15, 0)) {
      mismatch := true.B
      mismatchCode := mismatchCode | 1.U
      when(!mismatch) {
        mismatchAt := pixelCount
        mismatchActual := scanout.io.pixel.bits.pixel
      }
    }
    when(scanout.io.pixel.bits.lineLast =/= (pixelCount % GpuMemoryMap.FrameWidth.U === (GpuMemoryMap.FrameWidth - 1).U)) {
      mismatch := true.B
      mismatchCode := mismatchCode | 2.U
    }
    when(scanout.io.pixel.bits.frameLast =/= (pixelCount === (GpuMemoryMap.FrameWidth * GpuMemoryMap.FrameHeight - 1).U)) {
      mismatch := true.B
      mismatchCode := mismatchCode | 4.U
    }
    when(scanout.io.pixel.bits.lineLast) { lineCount := lineCount + 1.U }
    when(scanout.io.pixel.bits.frameLast) { frameLastCount := frameLastCount + 1.U }
    when(scanout.io.pixel.bits.frameLast) { stopRequested := true.B }
    pixelCount := pixelCount + 1.U
    crc := crcAfterPixel
  }
  when(scanout.io.error) {
    mismatch := true.B
    mismatchCode := mismatchCode | 8.U
  }
  when(scanout.io.frameDone) {
    done := true.B
    frameCrc := crc ^ "hffffffff".U
  }

  io.done := done
  io.mismatch := mismatch
  io.mismatchCode := mismatchCode
  io.mismatchAt := mismatchAt
  io.mismatchActual := mismatchActual
  io.pixelCount := pixelCount
  io.lineCount := lineCount
  io.frameLastCount := frameLastCount
  io.frameCrc := frameCrc
}

class GpuSystemSpec extends AnyFunSpec with StableChiselSim with Matchers {
  describe("FrameSwapController") {
    it("holds both framebuffer addresses until vblank and completes the matching PRESENT tag") {
      simulate(new FrameSwapController) { dut =>
        dut.io.present.valid.poke(false)
        dut.io.present.bits.poke(0.U.asTypeOf(new GpuCommand))
        dut.io.vblank.poke(false)
        dut.io.completion.ready.poke(false)
        dut.clock.step()

        dut.io.frontBase.expect(GpuMemoryMap.FramebufferA)
        dut.io.backBase.expect(GpuMemoryMap.FramebufferB)
        dut.io.present.ready.expect(true)

        dut.io.present.valid.poke(true)
        dut.io.present.bits.op.poke(GpuOpcode.Present)
        dut.io.present.bits.dstAddr.poke(GpuMemoryMap.FramebufferB)
        dut.io.present.bits.tag.poke(0x1234)
        dut.clock.step()
        dut.io.present.valid.poke(false)

        for (_ <- 0 until 17) {
          dut.io.frontBase.expect(GpuMemoryMap.FramebufferA)
          dut.io.backBase.expect(GpuMemoryMap.FramebufferB)
          dut.io.completion.valid.expect(false)
          dut.io.pending.expect(true)
          dut.clock.step()
        }

        dut.io.vblank.poke(true)
        dut.clock.step()
        dut.io.vblank.poke(false)
        dut.io.frontBase.expect(GpuMemoryMap.FramebufferB)
        dut.io.backBase.expect(GpuMemoryMap.FramebufferA)
        dut.io.completion.valid.expect(true)
        dut.io.completion.bits.tag.expect(0x1234)
        dut.io.completion.bits.error.expect(GpuError.None)
        dut.io.present.ready.expect(false)

        dut.clock.step(3)
        dut.io.completion.valid.expect(true)
        dut.io.frontBase.expect(GpuMemoryMap.FramebufferB)
        dut.io.completion.ready.poke(true)
        dut.clock.step()
        dut.io.completion.valid.expect(false)
        dut.io.present.ready.expect(true)
      }
    }

    it("routes an APB PRESENT through the command queue and updates scanout only at vblank") {
      simulate(new Efinix2dGpuTop) { dut =>
        dut.io.apb.psel.poke(false)
        dut.io.apb.penable.poke(false)
        dut.io.apb.pwrite.poke(false)
        dut.io.apb.paddr.poke(0)
        dut.io.apb.pwdata.poke(0)
        dut.io.vblank.poke(false)
        dut.io.scanoutLevel.poke(4095)
        dut.io.underflow_pulse_gpu.poke(false)
        dut.io.displayReady.poke(false)
        dut.io.axi.aw.ready.poke(true)
        dut.io.axi.w.ready.poke(true)
        dut.io.axi.b.valid.poke(false)
        dut.io.axi.b.bits.poke(0.U.asTypeOf(new Axi4WriteResponse))
        dut.io.axi.ar.ready.poke(false)
        dut.io.axi.r.valid.poke(false)
        dut.io.axi.r.bits.poke(0.U.asTypeOf(new Axi4ReadData))
        dut.clock.step()

        def transfer(offset: Int, write: Boolean, data: BigInt = 0): BigInt = {
          dut.io.apb.paddr.poke(offset)
          dut.io.apb.pwrite.poke(write)
          dut.io.apb.pwdata.poke(data)
          dut.io.apb.psel.poke(true)
          dut.io.apb.penable.poke(false)
          dut.clock.step()
          dut.io.apb.penable.poke(true)
          dut.io.apb.pready.expect(true)
          dut.io.apb.pslverror.expect(false)
          val result = dut.io.apb.prdata.peek().litValue
          dut.clock.step()
          dut.io.apb.psel.poke(false)
          dut.io.apb.penable.poke(false)
          dut.clock.step()
          result
        }

        transfer(GpuRegisterMap.Op, write = true, GpuOpcode.Present)
        transfer(GpuRegisterMap.DstAddr, write = true, GpuMemoryMap.FramebufferB)
        transfer(GpuRegisterMap.Size, write = true, (1L << 16) | 1L)
        transfer(GpuRegisterMap.DstStride, write = true, 2)
        transfer(GpuRegisterMap.Tag, write = true, 0x4242)
        transfer(GpuRegisterMap.Control, write = true, 1)

        dut.clock.step(11)
        transfer(GpuRegisterMap.FrontBuffer, write = false) shouldBe GpuMemoryMap.FramebufferA
        transfer(GpuRegisterMap.BackBuffer, write = false) shouldBe GpuMemoryMap.FramebufferB
        transfer(GpuRegisterMap.LastDone, write = false) shouldBe 0

        dut.io.vblank.poke(true)
        dut.clock.step()
        dut.io.vblank.poke(false)
        dut.clock.step(5)
        transfer(GpuRegisterMap.FrontBuffer, write = false) shouldBe GpuMemoryMap.FramebufferB
        transfer(GpuRegisterMap.BackBuffer, write = false) shouldBe GpuMemoryMap.FramebufferA
        transfer(GpuRegisterMap.LastDone, write = false) shouldBe 0x4242

        transfer(GpuRegisterMap.Op, write = true, 15)
        transfer(GpuRegisterMap.Tag, write = true, 0x4243)
        transfer(GpuRegisterMap.Control, write = true, 1)
        dut.clock.step(12)
        transfer(GpuRegisterMap.LastDone, write = false) shouldBe 0x4243
        transfer(GpuRegisterMap.Error, write = false) shouldBe GpuError.InvalidOpcode

        transfer(GpuRegisterMap.Op, write = true, GpuOpcode.Present)
        transfer(GpuRegisterMap.DstAddr, write = true, GpuMemoryMap.FramebufferA)
        transfer(GpuRegisterMap.Tag, write = true, 0x4244)
        transfer(GpuRegisterMap.Control, write = true, 1)
        dut.clock.step(8)
        dut.io.vblank.poke(true)
        dut.clock.step()
        dut.io.vblank.poke(false)
        dut.clock.step(5)
        transfer(GpuRegisterMap.LastDone, write = false) shouldBe 0x4244
        transfer(GpuRegisterMap.Error, write = false) shouldBe GpuError.InvalidOpcode

        transfer(GpuRegisterMap.Op, write = true, GpuOpcode.Fill)
        transfer(GpuRegisterMap.Size, write = true, 1L << 16)
        transfer(GpuRegisterMap.DstStride, write = true, 2)
        transfer(GpuRegisterMap.Tag, write = true, 0x4245)
        transfer(GpuRegisterMap.Control, write = true, 1)
        dut.clock.step(12)
        transfer(GpuRegisterMap.LastDone, write = false) shouldBe 0x4245
        transfer(GpuRegisterMap.Error, write = false) shouldBe GpuError.InvalidOpcode
      }
    }
  }

  describe("Sparse render path") {
    it("matches color-key output while reading fewer source bytes and never writing transparent pixels") {
      simulate(new RenderEngine) { dut =>
        val srcBase = GpuMemoryMap.SparseAssets.longValue
        val dstBase = GpuMemoryMap.FramebufferA.longValue
        val tokens = Seq(0x00020002L, 0x22221111L, 0x00000004L, 0x00000008L)
        val memory = collection.mutable.Map.empty[Long, Int].withDefaultValue(0)
        tokens.zipWithIndex.foreach { case (word, index) =>
          (0 until 4).foreach(byte => memory(srcBase + index * 4 + byte) = ((word >> (byte * 8)) & 0xff).toInt)
        }
        (0 until 32).foreach(byte => memory(dstBase + byte) = 0x5a)
        def word(address: Long): Long =
          (0 until 4).map(byte => memory(address + byte).toLong << (byte * 8)).reduce(_ | _)
        def half(address: Long): Int = memory(address) | (memory(address + 1) << 8)

        val random = new scala.util.Random(0x2d5eL)
        var submitted = false
        var readPending = false
        var readAddress = 0L
        var writeOpen = false
        var writeAddress = 0L
        var responsePending = false
        var completed = false
        var readBytes = 0
        val writtenAddresses = collection.mutable.ArrayBuffer.empty[Long]

        dut.io.perfClear.poke(false)
        dut.io.underflowPulse.poke(false)
        dut.io.renderGrant.poke(0)
        dut.io.scanoutGrant.poke(0)
        dut.io.vblank.poke(false)
        dut.io.completion.ready.poke(true)
        dut.io.axi.r.bits.id.poke(0)
        dut.io.axi.r.bits.resp.poke(Axi4.Okay)
        dut.io.axi.r.bits.last.poke(true)
        dut.io.axi.b.bits.id.poke(0)
        dut.io.axi.b.bits.resp.poke(Axi4.Okay)

        for (_ <- 0 until 1500 if !completed) {
          dut.io.command.valid.poke(!submitted)
          dut.io.command.bits.poke(0.U.asTypeOf(new GpuCommand))
          dut.io.command.bits.op.poke(GpuOpcode.Sparse)
          dut.io.command.bits.srcAddr.poke(srcBase)
          dut.io.command.bits.dstAddr.poke(dstBase)
          dut.io.command.bits.widthPixels.poke(8)
          dut.io.command.bits.heightPixels.poke(2)
          dut.io.command.bits.dstStride.poke(16)
          dut.io.command.bits.tag.poke(0x5a5a)

          dut.io.axi.ar.ready.poke(!readPending && random.nextBoolean())
          dut.io.axi.r.valid.poke(readPending && random.nextBoolean())
          dut.io.axi.r.bits.data.poke(BigInt(if (readPending) word(readAddress) else 0L))
          dut.io.axi.aw.ready.poke(!writeOpen && random.nextBoolean())
          dut.io.axi.w.ready.poke(writeOpen && random.nextBoolean())
          dut.io.axi.b.valid.poke(responsePending && random.nextBoolean())

          val commandFire = dut.io.command.valid.peek().litToBoolean && dut.io.command.ready.peek().litToBoolean
          val arFire = dut.io.axi.ar.valid.peek().litToBoolean && dut.io.axi.ar.ready.peek().litToBoolean
          val rFire = dut.io.axi.r.valid.peek().litToBoolean && dut.io.axi.r.ready.peek().litToBoolean
          val awFire = dut.io.axi.aw.valid.peek().litToBoolean && dut.io.axi.aw.ready.peek().litToBoolean
          val wFire = dut.io.axi.w.valid.peek().litToBoolean && dut.io.axi.w.ready.peek().litToBoolean
          val wLast = wFire && dut.io.axi.w.bits.last.peek().litToBoolean
          val bFire = dut.io.axi.b.valid.peek().litToBoolean && dut.io.axi.b.ready.peek().litToBoolean
          val completionFire = dut.io.completion.valid.peek().litToBoolean && dut.io.completion.ready.peek().litToBoolean

          if (arFire) readAddress = dut.io.axi.ar.bits.addr.peek().litValue.longValue
          if (awFire) writeAddress = dut.io.axi.aw.bits.addr.peek().litValue.longValue
          if (wFire) {
            val data = dut.io.axi.w.bits.data.peek().litValue.longValue
            val strobe = dut.io.axi.w.bits.strb.peek().litValue.toInt
            for (byte <- 0 until 4 if ((strobe >> byte) & 1) != 0) {
              memory(writeAddress + byte) = ((data >> (byte * 8)) & 0xff).toInt
              writtenAddresses += writeAddress + byte
            }
            writeAddress += 4
          }
          if (completionFire) {
            dut.io.completion.bits.tag.expect(0x5a5a)
            dut.io.completion.bits.error.expect(GpuError.None)
            completed = true
          }

          dut.clock.step()
          if (commandFire) submitted = true
          if (arFire) readPending = true
          if (rFire) { readPending = false; readBytes += 4 }
          if (awFire) writeOpen = true
          if (wLast) { writeOpen = false; responsePending = true }
          if (bFire) responsePending = false
        }

        completed shouldBe true
        readBytes shouldBe 16
        readBytes should be < (8 * 2 * 2)
        half(dstBase + 4) shouldBe 0x1111
        half(dstBase + 6) shouldBe 0x2222
        (writtenAddresses.toSet -- Set(dstBase + 4, dstBase + 5, dstBase + 6, dstBase + 7)) shouldBe empty
        Seq(0, 1, 4, 5, 6, 7).foreach(x => half(dstBase + x * 2) shouldBe 0x5a5a)
      }
    }

    it("completes with AXI error when a failing write overlaps a delayed token read") {
      simulate(new SparseBlitEngine) { dut =>
        val srcBase = GpuMemoryMap.SparseAssets.longValue
        val tokens = Seq(0x00010000L, 0x00001111L, 0x00010001L, 0x00002222L, 0x00000001L)
        var submitted = false
        var readPending = false
        var readAddress = 0L
        var responsePending = false
        var writeErrorSent = false
        var completed = false

        dut.io.completion.ready.poke(true)
        dut.io.axi.ar.ready.poke(true)
        dut.io.axi.aw.ready.poke(true)
        dut.io.axi.w.ready.poke(true)
        dut.io.axi.r.bits.id.poke(0)
        dut.io.axi.r.bits.resp.poke(Axi4.Okay)
        dut.io.axi.r.bits.last.poke(true)
        dut.io.axi.b.bits.id.poke(0)

        for (_ <- 0 until 500 if !completed) {
          dut.io.command.valid.poke(!submitted)
          dut.io.command.bits.poke(0.U.asTypeOf(new GpuCommand))
          dut.io.command.bits.op.poke(GpuOpcode.Sparse)
          dut.io.command.bits.srcAddr.poke(srcBase)
          dut.io.command.bits.dstAddr.poke(GpuMemoryMap.FramebufferA)
          dut.io.command.bits.widthPixels.poke(4)
          dut.io.command.bits.heightPixels.poke(1)
          dut.io.command.bits.dstStride.poke(8)
          dut.io.command.bits.tag.poke(0xe901)

          val delayedLastRead = readPending && readAddress == srcBase + 16 && !writeErrorSent
          dut.io.axi.r.valid.poke(readPending && !delayedLastRead)
          val tokenIndex = ((readAddress - srcBase) / 4).toInt
          dut.io.axi.r.bits.data.poke(BigInt(if (readPending && tokenIndex >= 0 && tokenIndex < tokens.size) tokens(tokenIndex) else 0L))
          dut.io.axi.b.valid.poke(responsePending && delayedLastRead)
          dut.io.axi.b.bits.resp.poke(2)

          val commandFire = dut.io.command.valid.peek().litToBoolean && dut.io.command.ready.peek().litToBoolean
          val arFire = dut.io.axi.ar.valid.peek().litToBoolean && dut.io.axi.ar.ready.peek().litToBoolean
          val rFire = dut.io.axi.r.valid.peek().litToBoolean && dut.io.axi.r.ready.peek().litToBoolean
          val wLast = dut.io.axi.w.valid.peek().litToBoolean && dut.io.axi.w.ready.peek().litToBoolean &&
            dut.io.axi.w.bits.last.peek().litToBoolean
          val bFire = dut.io.axi.b.valid.peek().litToBoolean && dut.io.axi.b.ready.peek().litToBoolean
          val completionFire = dut.io.completion.valid.peek().litToBoolean && dut.io.completion.ready.peek().litToBoolean
          if (arFire) readAddress = dut.io.axi.ar.bits.addr.peek().litValue.longValue
          if (completionFire) {
            dut.io.completion.bits.tag.expect(0xe901)
            dut.io.completion.bits.error.expect(GpuError.AxiResponse)
            completed = true
          }

          dut.clock.step()
          if (commandFire) submitted = true
          if (arFire) readPending = true
          if (rFire) readPending = false
          if (wLast) responsePending = true
          if (bFire) { responsePending = false; writeErrorSent = true }
        }

        writeErrorSent shouldBe true
        completed shouldBe true
      }
    }
  }

  describe("ScanoutDma") {
    it("reads a strided framebuffer in order and marks line and frame boundaries") {
      simulate(new ScanoutDma(frameWidth = 3, frameHeight = 2, strideBytes = 8, lowWatermark = 2)) { dut =>
        val memory = Map[Long, Long](
          0x2000L -> 0x22221111L,
          0x2004L -> 0xaaaa3333L,
          0x2008L -> 0x55554444L,
          0x200cL -> 0xbbbb6666L
        ).withDefaultValue(0L)
        val observed = collection.mutable.ArrayBuffer.empty[(BigInt, Boolean, Boolean)]
        var readAddress = 0L
        var readBeats = 0
        var sawDone = false

        dut.io.enable.poke(true)
        dut.io.frontBase.poke(0x2000)
        dut.io.fifoLevel.poke(0)
        dut.io.pixel.ready.poke(true)
        dut.io.axi.ar.ready.poke(true)
        dut.io.axi.r.bits.id.poke(0)
        dut.io.axi.r.bits.resp.poke(0)
        dut.io.axi.aw.ready.poke(true)
        dut.io.axi.w.ready.poke(true)
        dut.io.axi.b.valid.poke(false)
        dut.io.axi.b.bits.id.poke(0)
        dut.io.axi.b.bits.resp.poke(0)

        for (cycle <- 0 until 200 if !sawDone) {
          dut.io.pixel.ready.poke(cycle % 4 != 1)
          dut.io.axi.r.valid.poke(readBeats > 0)
          dut.io.axi.r.bits.data.poke(BigInt(if (readBeats > 0) memory(readAddress) else 0L))
          dut.io.axi.r.bits.last.poke(readBeats == 1)

          val arFire = dut.io.axi.ar.valid.peek().litToBoolean && dut.io.axi.ar.ready.peek().litToBoolean
          val rFire = dut.io.axi.r.valid.peek().litToBoolean && dut.io.axi.r.ready.peek().litToBoolean
          val pixelFire = dut.io.pixel.valid.peek().litToBoolean && dut.io.pixel.ready.peek().litToBoolean
          if (arFire) {
            readAddress = dut.io.axi.ar.bits.addr.peek().litValue.longValue
            readBeats = dut.io.axi.ar.bits.len.peek().litValue.toInt + 1
          }
          if (pixelFire) {
            observed += ((
              dut.io.pixel.bits.pixel.peek().litValue,
              dut.io.pixel.bits.lineLast.peek().litToBoolean,
              dut.io.pixel.bits.frameLast.peek().litToBoolean
            ))
          }
          sawDone ||= dut.io.frameDone.peek().litToBoolean
          dut.clock.step()
          if (rFire) {
            readAddress += 4
            readBeats -= 1
          }
        }

        sawDone shouldBe true
        observed.toSeq shouldBe Seq(
          (BigInt(0x1111), false, false),
          (BigInt(0x2222), false, false),
          (BigInt(0x3333), true, false),
          (BigInt(0x4444), false, false),
          (BigInt(0x5555), false, false),
          (BigInt(0x6666), true, true)
        )
      }
    }

    it("waits for the configured FIFO low watermark before issuing the next row") {
      simulate(new ScanoutDma(frameWidth = 2, frameHeight = 1, strideBytes = 4, lowWatermark = 2)) { dut =>
        dut.io.enable.poke(true)
        dut.io.frontBase.poke(0x2000)
        dut.io.fifoLevel.poke(3)
        dut.io.pixel.ready.poke(true)
        dut.io.axi.ar.ready.poke(false)
        dut.io.axi.r.valid.poke(false)
        dut.io.axi.r.bits.id.poke(0)
        dut.io.axi.r.bits.data.poke(0)
        dut.io.axi.r.bits.resp.poke(0)
        dut.io.axi.r.bits.last.poke(false)
        dut.io.axi.aw.ready.poke(true)
        dut.io.axi.w.ready.poke(true)
        dut.io.axi.b.valid.poke(false)
        dut.io.axi.b.bits.id.poke(0)
        dut.io.axi.b.bits.resp.poke(0)
        dut.clock.step(4)
        dut.io.axi.ar.valid.expect(false)
        dut.io.fifoLevel.poke(2)
        dut.clock.step(3)
        dut.io.axi.ar.valid.expect(true)
      }
    }

    it("streams all 307200 production pixels across split bursts with a fixed frame CRC") {
      simulate(new ScanoutDmaProductionHarness) { dut =>
        dut.clock.step(500000)
        dut.io.done.expect(true)
        withClue(s"first pixel mismatch at ${dut.io.mismatchAt.peek().litValue}, actual ${dut.io.mismatchActual.peek().litValue}: ") {
          dut.io.mismatchCode.peek().litValue shouldBe 0
        }
        dut.io.mismatch.expect(false)
        dut.io.pixelCount.expect(GpuMemoryMap.FrameWidth * GpuMemoryMap.FrameHeight)
        dut.io.lineCount.expect(GpuMemoryMap.FrameHeight)
        dut.io.frameLastCount.expect(1)
        dut.io.frameCrc.expect(0x0fc5c6bcL)
      }
    }
  }
}
