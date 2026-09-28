package gpu

import chisel3._
import org.scalatest.funspec.AnyFunSpec
import org.scalatest.matchers.should.Matchers
import testutil.StableChiselSim

class WordKeyDmaSpec extends AnyFunSpec with StableChiselSim with Matchers {
  describe("halfword-phase Color Key DMA") {
    it("keeps overlapping strided Key reads on the legacy pixel path") {
      simulate(new DenseBlitEngine) { dut =>
        val memory = collection.mutable.Map.empty[Long, Int].withDefaultValue(0)
        for ((address, value) <- Seq(0x02400002L -> 0x1111, 0x02400004L -> 0x2222,
          0x02400006L -> 0x3333, 0x02400022L -> 0x4444, 0x02400024L -> 0x5555,
          0x02400026L -> 0x6666)) {
          memory(address) = value & 0xff; memory(address + 1) = value >> 8
        }
        def word(address: Long): Long = (0 until 4)
          .map(byte => memory(address + byte).toLong << (byte * 8)).reduce(_ | _)
        var submitted = false
        var completed = false
        var readAddress = 0L
        var readBeats = 0
        var writeAddress = 0L
        var response = false
        var pixelPending = false
        var pixel = 0
        var pixelRequests = 0
        dut.io.completion.ready.poke(true)
        dut.io.pixelRequest.ready.poke(true)
        dut.io.axi.aw.ready.poke(true)
        dut.io.axi.w.ready.poke(true)
        dut.io.axi.ar.ready.poke(true)
        dut.io.axi.r.bits.id.poke(0)
        dut.io.axi.r.bits.resp.poke(0)
        dut.io.axi.b.bits.id.poke(0)
        dut.io.axi.b.bits.resp.poke(0)
        for (_ <- 0 until 500 if !completed) {
          dut.io.command.valid.poke(!submitted)
          dut.io.command.bits.poke(0.U.asTypeOf(new GpuCommand))
          dut.io.command.bits.op.poke(GpuOpcode.ColorKey)
          dut.io.command.bits.srcAddr.poke(0x02400002L)
          dut.io.command.bits.dstAddr.poke(0x02400020L)
          dut.io.command.bits.srcStride.poke(32)
          dut.io.command.bits.dstStride.poke(8)
          dut.io.command.bits.widthPixels.poke(3)
          dut.io.command.bits.heightPixels.poke(2)
          dut.io.command.bits.colorKey.poke(0xbeef)
          dut.io.axi.r.valid.poke(readBeats > 0)
          dut.io.axi.r.bits.data.poke(if (readBeats > 0) word(readAddress) else 0L)
          dut.io.axi.r.bits.last.poke(readBeats == 1)
          dut.io.axi.b.valid.poke(response)
          dut.io.pixelResult.valid.poke(pixelPending)
          dut.io.pixelResult.bits.pixel.poke(pixel)
          dut.io.pixelResult.bits.writeEnable.poke(true)
          val commandFire = dut.io.command.valid.peek().litToBoolean && dut.io.command.ready.peek().litToBoolean
          val requestFire = dut.io.pixelRequest.valid.peek().litToBoolean
          val resultFire = pixelPending && dut.io.pixelResult.ready.peek().litToBoolean
          val arFire = dut.io.axi.ar.valid.peek().litToBoolean
          val rFire = readBeats > 0 && dut.io.axi.r.ready.peek().litToBoolean
          val awFire = dut.io.axi.aw.valid.peek().litToBoolean
          val wFire = dut.io.axi.w.valid.peek().litToBoolean
          val bFire = response && dut.io.axi.b.ready.peek().litToBoolean
          val wLast = wFire && dut.io.axi.w.bits.last.peek().litToBoolean
          dut.io.wordPixelsDone.expect(0)
          if (requestFire) { pixel = dut.io.pixelRequest.bits.foreground.peek().litValue.toInt; pixelRequests += 1 }
          if (arFire) {
            readAddress = dut.io.axi.ar.bits.addr.peek().litValue.longValue
            readBeats = dut.io.axi.ar.bits.len.peek().litValue.toInt + 1
          }
          if (awFire) writeAddress = dut.io.axi.aw.bits.addr.peek().litValue.longValue
          if (wFire) {
            val data = dut.io.axi.w.bits.data.peek().litValue.longValue
            val strobe = dut.io.axi.w.bits.strb.peek().litValue.toInt
            for (byte <- 0 until 4 if ((strobe >> byte) & 1) != 0)
              memory(writeAddress + byte) = ((data >> (byte * 8)) & 0xff).toInt
            writeAddress += 4
          }
          if (dut.io.completion.valid.peek().litToBoolean) { dut.io.completion.bits.error.expect(GpuError.None); completed = true }
          dut.clock.step()
          if (commandFire) submitted = true
          if (rFire) { readAddress += 4; readBeats -= 1 }
          if (bFire) response = false
          if (wLast) response = true
          if (resultFire) pixelPending = false
          if (requestFire) pixelPending = true
        }
        completed shouldBe true
        pixelRequests shouldBe 6
        // First destination row overwrites two pixels of the later source row.
        Seq(0x02400020L, 0x02400022L, 0x02400024L, 0x02400028L, 0x0240002aL, 0x0240002cL)
          .map(address => memory(address) | (memory(address + 1) << 8)) shouldBe
          Seq(0x1111, 0x2222, 0x3333, 0x2222, 0x3333, 0x6666)
      }
    }

    it("counts partial and transparent pixels independently from actual written bytes in RenderEngine") {
      simulate(new RenderEngine) { dut =>
        dut.io.command.valid.poke(false)
        dut.io.vblank.poke(false)
        dut.io.perfClear.poke(true)
        dut.io.underflowPulse.poke(false)
        dut.io.renderGrant.poke(0)
        dut.io.scanoutGrant.poke(0)
        dut.io.completion.ready.poke(true)
        dut.io.axi.aw.ready.poke(true)
        dut.io.axi.w.ready.poke(true)
        dut.io.axi.ar.ready.poke(true)
        dut.io.axi.r.valid.poke(false)
        dut.io.axi.r.bits.id.poke(0)
        dut.io.axi.r.bits.resp.poke(0)
        dut.io.axi.b.valid.poke(false)
        dut.io.axi.b.bits.id.poke(0)
        dut.io.axi.b.bits.resp.poke(0)
        dut.clock.step()
        dut.io.perfClear.poke(false)
        // Logical source pixels: [key, 1111, key], [2222, key, 3333].
        val source = Map(0x02400000L -> 0xbeef7777L, 0x02400004L -> 0xbeef1111L,
          0x02400008L -> 0x22227777L, 0x0240000cL -> 0x3333beefL)
        var submitted = false
        var completed = false
        var readAddress = 0L
        var readBeats = 0
        var response = false
        for (_ <- 0 until 300 if !completed) {
          dut.io.command.valid.poke(!submitted)
          dut.io.command.bits.poke(0.U.asTypeOf(new GpuCommand))
          dut.io.command.bits.op.poke(GpuOpcode.ColorKey)
          dut.io.command.bits.srcAddr.poke(0x02400002L)
          dut.io.command.bits.dstAddr.poke(0x02000000L)
          dut.io.command.bits.srcStride.poke(8)
          dut.io.command.bits.dstStride.poke(8)
          dut.io.command.bits.widthPixels.poke(3)
          dut.io.command.bits.heightPixels.poke(2)
          dut.io.command.bits.colorKey.poke(0xbeef)
          dut.io.axi.r.valid.poke(readBeats > 0)
          dut.io.axi.r.bits.data.poke(source.getOrElse(readAddress, 0L))
          dut.io.axi.r.bits.last.poke(readBeats == 1)
          dut.io.axi.b.valid.poke(response)
          val commandFire = dut.io.command.valid.peek().litToBoolean && dut.io.command.ready.peek().litToBoolean
          val arFire = dut.io.axi.ar.valid.peek().litToBoolean
          val rFire = readBeats > 0 && dut.io.axi.r.ready.peek().litToBoolean
          val bFire = response && dut.io.axi.b.ready.peek().litToBoolean
          val wLast = dut.io.axi.w.valid.peek().litToBoolean && dut.io.axi.w.bits.last.peek().litToBoolean
          if (arFire) {
            readAddress = dut.io.axi.ar.bits.addr.peek().litValue.longValue
            readBeats = dut.io.axi.ar.bits.len.peek().litValue.toInt + 1
          }
          if (dut.io.completion.valid.peek().litToBoolean) {
            dut.io.completion.bits.error.expect(GpuError.None)
            completed = true
          }
          dut.clock.step()
          if (commandFire) submitted = true
          if (rFire) { readAddress += 4; readBeats -= 1 }
          if (bFire) response = false
          if (wLast) response = true
        }
        completed shouldBe true
        dut.io.perfPixels.expect(6)
        dut.io.perfReadBytes.expect(16)
        dut.io.perfWriteBytes.expect(6)
      }
    }

    it("preserves guards and transparent lanes without the pixel pipe across offsets, strides and AXI stalls") {
      simulate(new DenseBlitEngine) { dut =>
        final case class Case(width: Int, srcOffset: Int, dstOffset: Int,
          transparent: Boolean = false, readError: Boolean = false, writeError: Boolean = false)
        val cases = (for (width <- Seq(1, 2, 3, 8, 11, 12); src <- Seq(0, 2); dst <- Seq(2, 0))
          yield Case(width, src, dst)) ++ Seq(
          Case(11, 2, 0, transparent = true), Case(12, 0, 2, transparent = true),
          Case(513, 2, 0), Case(12, 2, 0, readError = true),
          Case(11, 0, 2, writeError = true), Case(3, 2, 2))
        val key = 0xbeef
        val random = new scala.util.Random(0xabcdef)
        dut.io.command.valid.poke(false)
        dut.io.pixelRequest.ready.poke(false)
        dut.io.pixelResult.valid.poke(false)
        dut.io.pixelResult.bits.poke(0.U.asTypeOf(new PixelResult))
        dut.io.completion.ready.poke(false)
        dut.io.axi.r.valid.poke(false)
        dut.io.axi.b.valid.poke(false)
        dut.io.axi.r.bits.id.poke(0)
        dut.io.axi.b.bits.id.poke(0)
        dut.clock.step()

        for ((c, tag) <- cases.zipWithIndex) {
          val src = 0x02400ff8L + c.srcOffset
          val dst = 0x02000ff4L + c.dstOffset
          // Alternate row phase; source and destination also cross different 4 KB boundaries.
          val srcStride = c.width * 2 + 6
          val dstStride = c.width * 2 + 8
          val height = 3
          val memory = collection.mutable.Map.empty[Long, Int].withDefaultValue(0xa5)
          val expected = collection.mutable.Map.empty[Long, Int].withDefaultValue(0xa5)
          for (row <- 0 until height; byte <- -4 until dstStride + 4) {
            memory(dst + row * dstStride + byte) = 0xa5
            expected(dst + row * dstStride + byte) = 0xa5
          }
          for (row <- 0 until height; x <- 0 until c.width) {
            val pixel = if (c.transparent || x % 4 == 1 || x % 4 == 2) key else 0x1000 + row * 16 + x
            memory(src + row * srcStride + x * 2) = pixel & 0xff
            memory(src + row * srcStride + x * 2 + 1) = pixel >> 8
            if (pixel != key && (!(c.readError || c.writeError) || row == 0)) {
              expected(dst + row * dstStride + x * 2) = pixel & 0xff
              expected(dst + row * dstStride + x * 2 + 1) = pixel >> 8
            }
          }
          def word(address: Long): Long = (0 until 4)
            .map(byte => memory(address + byte).toLong << (byte * 8)).reduce(_ | _)
          def bursts(base: Long, stride: Int, rows: Int): Seq[(Long, Int)] = (0 until rows).flatMap { row =>
            var address = (base + row * stride) & ~3L
            var remaining = ((base + row * stride) % 4 + c.width * 2 + 3).toInt / 4
            val result = collection.mutable.ArrayBuffer.empty[(Long, Int)]
            while (remaining > 0) {
              val beats = remaining.min(256).min(((4096 - address % 4096) / 4).toInt)
              result += address -> beats
              address += beats * 4
              remaining -= beats
            }
            result.toSeq
          }
          val reads = collection.mutable.ArrayBuffer.empty[(Long, Int)]
          val writes = collection.mutable.ArrayBuffer.empty[(Long, Int)]
          var readAddress = 0L
          var readBeats = 0
          var writeAddress = 0L
          var writeBeats = 0
          var readOffered = false
          var responsePending = false
          var responseOffered = false
          var responseDelay = 0
          var submitted = false
          var completed = false
          var completionHold = 0
          var stalledWrite: Option[(BigInt, BigInt, Boolean)] = None
          var responseCount = 0
          var processedPixels = 0

          for (_ <- 0 until 15000 if !completed) {
            dut.io.command.valid.poke(!submitted)
            dut.io.command.bits.poke(0.U.asTypeOf(new GpuCommand))
            dut.io.command.bits.op.poke(GpuOpcode.ColorKey)
            dut.io.command.bits.srcAddr.poke(src)
            dut.io.command.bits.dstAddr.poke(dst)
            dut.io.command.bits.srcStride.poke(srcStride)
            dut.io.command.bits.dstStride.poke(dstStride)
            dut.io.command.bits.widthPixels.poke(c.width)
            dut.io.command.bits.heightPixels.poke(height)
            dut.io.command.bits.colorKey.poke(key)
            dut.io.command.bits.tag.poke(tag)
            dut.io.axi.aw.ready.poke(writeBeats == 0 && !responsePending && random.nextBoolean())
            dut.io.axi.w.ready.poke(random.nextBoolean())
            dut.io.axi.ar.ready.poke(readBeats == 0 && random.nextBoolean())
            readOffered ||= readBeats > 0 && random.nextBoolean()
            responseOffered ||= responsePending && responseDelay == 0 && random.nextBoolean()
            dut.io.axi.r.valid.poke(readOffered)
            dut.io.axi.r.bits.data.poke(if (readBeats > 0) word(readAddress) else 0L)
            dut.io.axi.r.bits.last.poke(readBeats == 1)
            dut.io.axi.r.bits.resp.poke(if (c.readError) 2 else 0)
            dut.io.axi.b.valid.poke(responseOffered)
            dut.io.axi.b.bits.resp.poke(if (c.writeError) 2 else 0)
            dut.io.completion.ready.poke(completionHold >= 3)

            def fire(valid: Bool, ready: Bool): Boolean = valid.peek().litToBoolean && ready.peek().litToBoolean
            val commandFire = fire(dut.io.command.valid, dut.io.command.ready)
            val arFire = fire(dut.io.axi.ar.valid, dut.io.axi.ar.ready)
            val rFire = fire(dut.io.axi.r.valid, dut.io.axi.r.ready)
            val awFire = fire(dut.io.axi.aw.valid, dut.io.axi.aw.ready)
            val wFire = fire(dut.io.axi.w.valid, dut.io.axi.w.ready)
            val bFire = fire(dut.io.axi.b.valid, dut.io.axi.b.ready)
            dut.io.pixelRequest.valid.expect(false)
            processedPixels += dut.io.wordPixelsDone.peek().litValue.toInt
            stalledWrite.foreach { case (data, strb, last) =>
              dut.io.axi.w.valid.expect(true)
              dut.io.axi.w.bits.data.expect(data)
              dut.io.axi.w.bits.strb.expect(strb)
              dut.io.axi.w.bits.last.expect(last)
            }
            stalledWrite = if (dut.io.axi.w.valid.peek().litToBoolean && !wFire) Some((
              dut.io.axi.w.bits.data.peek().litValue, dut.io.axi.w.bits.strb.peek().litValue,
              dut.io.axi.w.bits.last.peek().litToBoolean)) else None
            if (arFire) {
              readAddress = dut.io.axi.ar.bits.addr.peek().litValue.longValue
              readBeats = dut.io.axi.ar.bits.len.peek().litValue.toInt + 1
              reads += readAddress -> readBeats
            }
            if (awFire) {
              writeAddress = dut.io.axi.aw.bits.addr.peek().litValue.longValue
              writeBeats = dut.io.axi.aw.bits.len.peek().litValue.toInt + 1
              writes += writeAddress -> writeBeats
            }
            if (wFire) {
              val data = dut.io.axi.w.bits.data.peek().litValue.longValue
              val strobe = dut.io.axi.w.bits.strb.peek().litValue.toInt
              dut.io.axi.w.bits.last.expect(writeBeats == 1)
              for (byte <- 0 until 4 if ((strobe >> byte) & 1) != 0)
                memory(writeAddress + byte) = ((data >> (byte * 8)) & 0xff).toInt
              writeAddress += 4
              writeBeats -= 1
            }
            if (responsePending || readBeats > 0 || writeBeats > 0) dut.io.completion.valid.expect(false)
            if (dut.io.completion.valid.peek().litToBoolean) {
              dut.io.completion.bits.tag.expect(tag)
              dut.io.completion.bits.error.expect(if (c.readError || c.writeError) GpuError.AxiResponse else GpuError.None)
              if (completionHold >= 3) completed = true
              completionHold += 1
            }
            dut.clock.step()
            if (commandFire) submitted = true
            if (rFire) { readOffered = false; readAddress += 4; readBeats -= 1 }
            if (responseDelay > 0) responseDelay -= 1
            if (bFire) { responseOffered = false; responsePending = false; responseCount += 1 }
            if (wFire && writeBeats == 0) { responsePending = true; responseDelay = 7 }
          }
          withClue(s"case $c: ") {
            completed shouldBe true
            val rows = if (c.readError || c.writeError) 1 else height
            reads.toSeq shouldBe bursts(src, srcStride, rows)
            writes.toSeq shouldBe bursts(dst, dstStride, rows)
            responseCount shouldBe writes.size
            processedPixels shouldBe c.width * rows
            expected.foreach { case (address, value) => memory(address) shouldBe value }
          }
        }
      }
    }
  }
}
