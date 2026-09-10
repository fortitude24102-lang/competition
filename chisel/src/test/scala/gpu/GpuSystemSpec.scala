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
