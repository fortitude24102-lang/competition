package gpu

import chisel3._
import org.scalatest.funspec.AnyFunSpec
import org.scalatest.matchers.should.Matchers
import testutil.StableChiselSim

private final case class TextureCacheRunResult(
  readIds: Seq[Int], writes: Seq[(BigInt, BigInt, Boolean)])

class TextureCacheBlitSpec extends AnyFunSpec with StableChiselSim with Matchers {
  describe("GPU texture-cache blits") {
    it("matches DDR pixels for aligned and halfword Key plus Alpha without foreground AR") {
      simulate(new RenderEngine) { dut =>
        val atlas = GpuMemoryMap.DenseAssets.longValue
        val words = collection.mutable.Map[Long, Long](
          atlas -> 0x2222beefL,
          (atlas + 4) -> 0x44443333L,
          (atlas + 8) -> 0x66665555L,
          (atlas + 12) -> 0x88887777L,
          0x02001000L -> 0x001f07e0L,
          0x02002000L -> 0x001f07e0L)

        init(dut)

        val ddrAligned = run(dut, words, GpuOpcode.ColorKey, atlas, 0x02000100L, 4, 0xbeef, 255)
        val ddrHalf = run(dut, words, GpuOpcode.ColorKey, atlas + 2, 0x02000202L, 3, 0xbeef, 255)
        val ddrAlpha = run(dut, words, GpuOpcode.Alpha, atlas + 8, 0x02001000L, 2, 0, 128)
        ddrAligned.readIds should contain (0)
        ddrHalf.readIds should contain (0)
        ddrAlpha.readIds should contain allOf (0, 1)

        preload(dut, words, atlas, 32)
        dut.io.textureCacheValid.expect(true)
        dut.io.textureCacheError.expect(false)

        val cachedAligned = run(dut, words, GpuOpcode.ColorKey, atlas, 0x02000300L, 4, 0xbeef, 255)
        val cachedHalf = run(dut, words, GpuOpcode.ColorKey, atlas + 2, 0x02000402L, 3, 0xbeef, 255)
        val cachedAlpha = run(dut, words, GpuOpcode.Alpha, atlas + 8, 0x02002000L, 2, 0, 128)

        cachedAligned.readIds shouldBe empty
        cachedHalf.readIds shouldBe empty
        cachedAlpha.readIds shouldBe Seq(1)
        cachedAligned.writes shouldBe ddrAligned.writes
        cachedHalf.writes shouldBe ddrHalf.writes
        cachedAlpha.writes shouldBe ddrAlpha.writes
        dut.io.perfCacheBytes.expect(20)
      }
    }

    it("falls back as a whole command after a range miss, invalidate, or preload error") {
      simulate(new RenderEngine) { dut =>
        val atlas = GpuMemoryMap.DenseAssets.longValue
        val words = collection.mutable.Map.empty[Long, Long].withDefaultValue(0x12345678L)
        init(dut)
        preload(dut, words, atlas, 32)

        val crossing = run(dut, words, GpuOpcode.ColorKey, atlas + 28, 0x02003000L, 3, 0xffff, 255)
        crossing.readIds.nonEmpty shouldBe true
        crossing.readIds.distinct shouldBe Seq(0)

        dut.io.textureCacheInvalidate.poke(true)
        dut.clock.step()
        dut.io.textureCacheInvalidate.poke(false)
        dut.io.textureCacheValid.expect(false)
        run(dut, words, GpuOpcode.ColorKey, atlas, 0x02003100L, 2, 0xffff, 255).readIds shouldBe Seq(0)

        preload(dut, words, atlas, 32, fail = true)
        dut.io.textureCacheValid.expect(false)
        dut.io.textureCacheError.expect(true)
        run(dut, words, GpuOpcode.ColorKey, atlas, 0x02003200L, 2, 0xffff, 255).readIds shouldBe Seq(0)
      }
    }

    it("keeps Alpha background and write response errors on the DDR path") {
      simulate(new RenderEngine) { dut =>
        val atlas = GpuMemoryMap.DenseAssets.longValue
        val words = collection.mutable.Map.empty[Long, Long].withDefaultValue(0x12345678L)
        init(dut)
        preload(dut, words, atlas, 32)

        val backgroundError = run(dut, words, GpuOpcode.Alpha, atlas,
          0x02004000L, 2, 0, 128, readErrorId = Some(1),
          expectedError = GpuError.AxiResponse)
        backgroundError.readIds shouldBe Seq(1)
        val writeError = run(dut, words, GpuOpcode.Alpha, atlas,
          0x02005000L, 2, 0, 128, writeError = true,
          expectedError = GpuError.AxiResponse)
        writeError.readIds shouldBe Seq(1)
        writeError.writes.nonEmpty shouldBe true
      }
    }
  }

  private def init(dut: RenderEngine): Unit = {
    dut.io.command.valid.poke(false)
    dut.io.command.bits.poke(0.U.asTypeOf(new GpuCommand))
    dut.io.vblank.poke(false)
    dut.io.perfClear.poke(false)
    dut.io.underflowPulse.poke(false)
    dut.io.renderGrant.poke(0)
    dut.io.scanoutGrant.poke(0)
    dut.io.completion.ready.poke(true)
    dut.io.textureCacheLoad.valid.poke(false)
    dut.io.textureCacheLoad.bits.base.poke(0)
    dut.io.textureCacheLoad.bits.bytes.poke(0)
    dut.io.textureCacheInvalidate.poke(false)
    dut.io.axi.aw.ready.poke(false)
    dut.io.axi.w.ready.poke(false)
    dut.io.axi.b.valid.poke(false)
    dut.io.axi.b.bits.poke(0.U.asTypeOf(new Axi4WriteResponse))
    dut.io.axi.ar.ready.poke(false)
    dut.io.axi.r.valid.poke(false)
    dut.io.axi.r.bits.poke(0.U.asTypeOf(new Axi4ReadData))
    dut.reset.poke(true)
    dut.clock.step(2)
    dut.reset.poke(false)
    dut.clock.step()
  }

  private def preload(dut: RenderEngine, memory: collection.Map[Long, Long],
                      base: Long, bytes: Int, fail: Boolean = false): Unit = {
    while (dut.io.busy.peek().litToBoolean || dut.io.textureCacheBusy.peek().litToBoolean)
      dut.clock.step()
    dut.io.textureCacheLoad.bits.base.poke(base)
    dut.io.textureCacheLoad.bits.bytes.poke(bytes)
    dut.io.textureCacheLoad.valid.poke(true)
    dut.clock.step()
    dut.io.textureCacheLoad.valid.poke(false)

    var address = 0L
    var beats = 0
    var done = false
    for (_ <- 0 until 200 if !done) {
      dut.io.axi.ar.ready.poke(beats == 0)
      dut.io.axi.r.valid.poke(beats > 0)
      dut.io.axi.r.bits.id.poke(0)
      dut.io.axi.r.bits.data.poke(memory.getOrElse(address, 0L))
      dut.io.axi.r.bits.resp.poke(if (fail) 2 else Axi4.Okay)
      dut.io.axi.r.bits.last.poke(beats == 1)
      val arFire = dut.io.axi.ar.valid.peek().litToBoolean && dut.io.axi.ar.ready.peek().litToBoolean
      val rFire = dut.io.axi.r.valid.peek().litToBoolean && dut.io.axi.r.ready.peek().litToBoolean
      if (arFire) {
        address = dut.io.axi.ar.bits.addr.peek().litValue.longValue
        beats = dut.io.axi.ar.bits.len.peek().litValue.toInt + 1
      }
      dut.clock.step()
      if (rFire) { address += 4; beats -= 1 }
      done = !dut.io.textureCacheBusy.peek().litToBoolean && beats == 0
    }
    dut.io.axi.r.valid.poke(false)
    dut.io.axi.ar.ready.poke(false)
    done shouldBe true
  }

  private def run(dut: RenderEngine, memory: collection.Map[Long, Long], op: Int,
                  src: Long, dst: Long, width: Int, key: Int,
                  alpha: Int, readErrorId: Option[Int] = None,
                  writeError: Boolean = false,
                  expectedError: Int = GpuError.None): TextureCacheRunResult = {
    var submitted = false
    var completed = false
    var readAddress = 0L
    var readBeats = 0
    var readId = 0
    var writeBeats = 0
    var responsePending = false
    val readIds = collection.mutable.ArrayBuffer.empty[Int]
    val writes = collection.mutable.ArrayBuffer.empty[(BigInt, BigInt, Boolean)]

    for (_ <- 0 until 1200 if !completed) {
      dut.io.command.valid.poke(!submitted)
      dut.io.command.bits.poke(0.U.asTypeOf(new GpuCommand))
      dut.io.command.bits.op.poke(op)
      dut.io.command.bits.srcAddr.poke(src)
      dut.io.command.bits.dstAddr.poke(dst)
      dut.io.command.bits.srcStride.poke(width * 2)
      dut.io.command.bits.dstStride.poke(width * 2)
      dut.io.command.bits.widthPixels.poke(width)
      dut.io.command.bits.heightPixels.poke(1)
      dut.io.command.bits.colorKey.poke(key)
      dut.io.command.bits.alpha.poke(alpha)
      dut.io.command.bits.tag.poke(dst & 0xffff)
      dut.io.axi.ar.ready.poke(readBeats == 0)
      dut.io.axi.r.valid.poke(readBeats > 0)
      dut.io.axi.r.bits.id.poke(readId)
      dut.io.axi.r.bits.data.poke(memory.getOrElse(readAddress, 0L))
      dut.io.axi.r.bits.resp.poke(if (readErrorId.contains(readId)) 2 else Axi4.Okay)
      dut.io.axi.r.bits.last.poke(readBeats == 1)
      dut.io.axi.aw.ready.poke(writeBeats == 0 && !responsePending)
      dut.io.axi.w.ready.poke(true)
      dut.io.axi.b.valid.poke(responsePending)
      dut.io.axi.b.bits.id.poke(0)
      dut.io.axi.b.bits.resp.poke(if (writeError) 2 else Axi4.Okay)

      def fire(valid: Bool, ready: Bool): Boolean =
        valid.peek().litToBoolean && ready.peek().litToBoolean
      val commandFire = fire(dut.io.command.valid, dut.io.command.ready)
      val arFire = fire(dut.io.axi.ar.valid, dut.io.axi.ar.ready)
      val rFire = fire(dut.io.axi.r.valid, dut.io.axi.r.ready)
      val awFire = fire(dut.io.axi.aw.valid, dut.io.axi.aw.ready)
      val wFire = fire(dut.io.axi.w.valid, dut.io.axi.w.ready)
      val bFire = fire(dut.io.axi.b.valid, dut.io.axi.b.ready)

      if (arFire) {
        readAddress = dut.io.axi.ar.bits.addr.peek().litValue.longValue
        readBeats = dut.io.axi.ar.bits.len.peek().litValue.toInt + 1
        readId = dut.io.axi.ar.bits.id.peek().litValue.toInt
        readIds += readId
      }
      if (awFire) writeBeats = dut.io.axi.aw.bits.len.peek().litValue.toInt + 1
      if (wFire) {
        val last = dut.io.axi.w.bits.last.peek().litToBoolean
        writes += ((dut.io.axi.w.bits.data.peek().litValue,
          dut.io.axi.w.bits.strb.peek().litValue, last))
        writeBeats -= 1
        if (last) responsePending = true
      }
      if (dut.io.completion.valid.peek().litToBoolean) {
        dut.io.completion.bits.error.expect(expectedError)
        completed = true
      }
      dut.clock.step()
      if (commandFire) submitted = true
      if (rFire) { readAddress += 4; readBeats -= 1 }
      if (bFire) responsePending = false
    }
    dut.io.command.valid.poke(false)
    dut.io.axi.r.valid.poke(false)
    dut.io.axi.b.valid.poke(false)
    completed shouldBe true
    TextureCacheRunResult(readIds.toSeq, writes.toSeq)
  }
}
