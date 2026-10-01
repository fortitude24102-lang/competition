package gpu

import chisel3._
import org.scalatest.funspec.AnyFunSpec
import org.scalatest.matchers.should.Matchers
import testutil.StableChiselSim

class CopyStreamSpec extends AnyFunSpec with StableChiselSim with Matchers {
  describe("continuous Copy using the existing AXI engines") {
    for (enabled <- Seq(true, false)) {
    it(s"preserves bytes and delayed B completion with continuous Copy enabled=$enabled") {
      simulate(new DenseBlitEngine(enableCopyStream = enabled)) { dut =>
        dut.io.command.valid.poke(false)
        dut.io.pixelRequest.ready.poke(false)
        dut.io.pixelResult.valid.poke(false)
        dut.io.pixelResult.bits.poke(0.U.asTypeOf(new PixelResult))
        dut.io.textureCacheLoad.valid.poke(false)
        dut.io.textureCacheLoad.bits.poke(0.U.asTypeOf(new TextureCacheLoad))
        dut.io.textureCacheInvalidate.poke(false)
        dut.io.textureCachePerfClear.poke(false)
        dut.io.completion.ready.poke(false)
        dut.io.axi.r.valid.poke(false)
        dut.io.axi.b.valid.poke(false)
        dut.clock.step()

        // Hand-derived burst lengths; src/dst have different 4 KiB boundaries.
        // fault: 1=RRESP, 2=BRESP, 3=RID, 4=BID, 5=early RLAST, 6=wrong RID1.
        val cases = if (!enabled) Seq(
          (8, 8, 16, 0x02400000L, 0x02000000L, Seq.fill(8)(4), Seq.fill(8)(4), 0)) else Seq(
          (8, 8, 16, 0x02400000L, 0x02000000L, Seq(32), Seq(32), 0),
          (514, 3, 1028, 0x02400ff8L, 0x02000ff4L,
            Seq(2, 256, 256, 256, 1), Seq(3, 256, 256, 256), 0),
          (3, 2, 6, 0x02400000L, 0x02000000L, Seq(3), Seq(3), 0),
          (8, 3, 24, 0x02400000L, 0x02000000L, Seq(4, 4, 4), Seq(4, 4, 4), 0)) ++
          (1 to 6).map(fault => (514, 3, 1028, 0x02400ff8L, 0x02000ff4L,
            Seq(2, 256, 256, 256, 1), Seq(3, 256, 256, 256), fault)) ++
          Seq((8, 8, 16, 0x02400000L, 0x02000000L, Seq(32), Seq(32), 0))
        for (((width, height, stride, src, dst, expectedReads, expectedWrites, fault), tag) <- cases.zipWithIndex) {
          val memory = collection.mutable.Map.empty[Long, Int].withDefaultValue(0xa5)
          for (row <- 0 until height; byte <- 0 until width * 2)
            memory(src + row * stride + byte) = (row * 73 + byte * 17) & 255
          def word(address: Long): Long = (0 until 4).map(b => memory(address + b).toLong << (8 * b)).reduce(_ | _)
          val random = new scala.util.Random(31 + tag)
          val reads = collection.mutable.ArrayBuffer.empty[Int]
          val writes = collection.mutable.ArrayBuffer.empty[Int]
          var readAddress = 0L
          var readBeats = 0
          var readOffered = false
          var writeAddress = 0L
          var writeBeats = 0
          var writeOutstanding = false
          var responseDelay = -1
          var submitted = false
          var completed = false
          var readWords = 0
          var writtenWords = 0
          var peakBuffered = 0
          var cycles = 0
          while (!completed && cycles < 5000) {
            dut.io.command.valid.poke(!submitted)
            dut.io.command.bits.poke(0.U.asTypeOf(new GpuCommand))
            dut.io.command.bits.op.poke(GpuOpcode.Copy)
            dut.io.command.bits.srcAddr.poke(src)
            dut.io.command.bits.dstAddr.poke(dst)
            dut.io.command.bits.widthPixels.poke(width)
            dut.io.command.bits.heightPixels.poke(height)
            dut.io.command.bits.srcStride.poke(stride)
            dut.io.command.bits.dstStride.poke(stride)
            dut.io.command.bits.tag.poke(tag)
            val arReady = random.nextInt(5) != 0
            val awReady = random.nextInt(4) != 0
            // Long write-only stall forces read/write decoupling and FIFO saturation.
            val wReady = cycles > 80 && random.nextInt(4) != 0
            if (readBeats > 0 && !readOffered) readOffered = random.nextInt(4) != 0
            dut.io.axi.ar.ready.poke(arReady)
            dut.io.axi.aw.ready.poke(awReady)
            dut.io.axi.w.ready.poke(wReady)
            dut.io.axi.r.valid.poke(readOffered)
            dut.io.axi.r.bits.id.poke(if (fault == 6 && readWords == 0) 1 else if (fault == 3 && readWords == 0) 7 else 0)
            dut.io.axi.r.bits.resp.poke(if (fault == 1 && readWords == 0) 2 else 0)
            dut.io.axi.r.bits.last.poke(readBeats == 1 || (fault == 5 && readWords == 0))
            dut.io.axi.r.bits.data.poke(word(readAddress))
            dut.io.axi.b.valid.poke(responseDelay == 0)
            dut.io.axi.b.bits.id.poke(if (fault == 4 && writes.size == 1) 7 else 0)
            dut.io.axi.b.bits.resp.poke(if (fault == 2 && writes.size == 1) 2 else 0)
            val commandFire = !submitted && dut.io.command.ready.peek().litToBoolean
            val arFire = arReady && dut.io.axi.ar.valid.peek().litToBoolean
            val rFire = readOffered && dut.io.axi.r.ready.peek().litToBoolean
            val awFire = awReady && dut.io.axi.aw.valid.peek().litToBoolean
            val wFire = wReady && dut.io.axi.w.valid.peek().litToBoolean
            val bFire = responseDelay == 0 && dut.io.axi.b.ready.peek().litToBoolean
            if (arFire) {
              readBeats shouldBe 0
              readAddress = dut.io.axi.ar.bits.addr.peek().litValue.longValue
              readBeats = dut.io.axi.ar.bits.len.peek().litValue.toInt + 1
              readBeats should be <= 256
              ((readAddress & 4095) + readBeats * 4) should be <= 4096L
              reads += readBeats
            }
            if (awFire) {
              writeOutstanding shouldBe false
              writeOutstanding = true
              writeAddress = dut.io.axi.aw.bits.addr.peek().litValue.longValue
              writeBeats = dut.io.axi.aw.bits.len.peek().litValue.toInt + 1
              ((writeAddress & 4095) + writeBeats * 4) should be <= 4096L
              writes += writeBeats
            }
            if (wFire) {
              writeBeats should be > 0
              dut.io.axi.w.bits.strb.expect(15)
              dut.io.axi.w.bits.last.expect(writeBeats == 1)
              val data = dut.io.axi.w.bits.data.peek().litValue.longValue
              for (b <- 0 until 4) memory(writeAddress + b) = ((data >> (8 * b)) & 255).toInt
              writeAddress += 4
              writeBeats -= 1
              writtenWords += 1
              if (writeBeats == 0) responseDelay = 19
            }
            if (rFire) { readWords += 1 }
            peakBuffered = peakBuffered.max(readWords - writtenWords)
            dut.io.pixelRequest.valid.expect(false)
            if (dut.io.completion.valid.peek().litToBoolean) {
              readBeats shouldBe 0
              writeOutstanding shouldBe false
              writtenWords shouldBe width * height / 2
              dut.io.completion.bits.tag.expect(tag)
              dut.io.completion.bits.error.expect(if (fault == 0) GpuError.None else GpuError.AxiResponse)
              completed = true
            }
            dut.clock.step()
            if (commandFire) submitted = true
            if (rFire) { readAddress += 4; readBeats -= 1; readOffered = false }
            if (responseDelay > 0) responseDelay -= 1
            if (bFire) { responseDelay = -1; writeOutstanding = false }
            cycles += 1
          }
          completed shouldBe true
          for (row <- 0 until height; byte <- -4 until stride) {
            val expected = if (byte >= 0 && byte < width * 2) (row * 73 + byte * 17) & 255 else 0xa5
            // A prior row's data is not a guard; only inspect the actual padding.
            if (byte >= 0 || row == 0) memory(dst + row * stride + byte) shouldBe expected
          }
          reads.toSeq shouldBe expectedReads
          writes.toSeq shouldBe expectedWrites
          if (enabled && stride == width * 2) { peakBuffered should be > 1; peakBuffered should be <= 16 }
          println(s"COPY enabled=$enabled tag=$tag fault=$fault words=$writtenWords AR=${reads.size} AW=${writes.size} cycles=$cycles fifo_peak=$peakBuffered")
          // Completion is stable until acknowledged; idle must not accept a second command.
          dut.io.command.valid.poke(false)
          dut.io.command.ready.expect(false)
          dut.clock.step(3)
          dut.io.completion.valid.expect(true)
          dut.io.completion.ready.poke(true)
          dut.clock.step()
          dut.io.completion.ready.poke(false)
        }
      }
    }
    }

    it("rejects invalid Copy descriptors without any memory access") {
      simulate(new RenderEngine) { dut =>
        dut.io.command.valid.poke(false)
        dut.io.vblank.poke(false)
        dut.io.perfClear.poke(false)
        dut.io.underflowPulse.poke(false)
        dut.io.renderGrant.poke(0)
        dut.io.scanoutGrant.poke(0)
        dut.io.textureCacheLoad.valid.poke(false)
        dut.io.textureCacheLoad.bits.poke(0.U.asTypeOf(new TextureCacheLoad))
        dut.io.textureCacheInvalidate.poke(false)
        dut.io.completion.ready.poke(false)
        dut.io.axi.ar.ready.poke(true)
        dut.io.axi.aw.ready.poke(true)
        dut.io.axi.w.ready.poke(true)
        dut.io.axi.r.valid.poke(false)
        dut.io.axi.r.bits.poke(0.U.asTypeOf(new Axi4ReadData))
        dut.io.axi.b.valid.poke(false)
        dut.io.axi.b.bits.poke(0.U.asTypeOf(new Axi4WriteResponse))
        dut.clock.step()
        val invalid = Seq(
          (0, 2, 16, 0x02400000L, 0x02000000L, GpuError.ZeroSize),
          (8, 0, 16, 0x02400000L, 0x02000000L, GpuError.ZeroSize),
          (8, 2, 16, 0x02000000L, 0x02000004L, GpuError.OverlappingCopy),
          (8, 2, 16, 0xfffffff0L, 0x02000000L, GpuError.AddressRange),
          (8, 2, 16, 0x02400000L, 0x0ffffff0L, GpuError.AddressRange),
          (8, 2, 16, 0x01000000L, 0x02000000L, GpuError.AddressRange),
          (65535, 65535, 131070, 0x02400000L, 0x02000000L, GpuError.AddressRange))
        for (((width, height, stride, src, dst, error), tag) <- invalid.zipWithIndex) {
          dut.io.command.bits.poke(0.U.asTypeOf(new GpuCommand))
          dut.io.command.bits.op.poke(GpuOpcode.Copy)
          dut.io.command.bits.srcAddr.poke(src)
          dut.io.command.bits.dstAddr.poke(dst)
          dut.io.command.bits.widthPixels.poke(width)
          dut.io.command.bits.heightPixels.poke(height)
          dut.io.command.bits.srcStride.poke(stride)
          dut.io.command.bits.dstStride.poke(stride)
          dut.io.command.bits.tag.poke(tag)
          dut.io.command.valid.poke(true)
          dut.io.command.ready.expect(true)
          dut.clock.step()
          dut.io.command.valid.poke(false)
          var completed = false
          for (_ <- 0 until 30 if !completed) {
            dut.io.axi.ar.valid.expect(false)
            dut.io.axi.aw.valid.expect(false)
            dut.io.axi.w.valid.expect(false)
            completed = dut.io.completion.valid.peek().litToBoolean
            if (!completed) dut.clock.step()
          }
          completed shouldBe true
          dut.io.completion.bits.error.expect(error)
          dut.io.completion.bits.tag.expect(tag)
          dut.clock.step(2)
          dut.io.completion.bits.error.expect(error)
          dut.io.completion.ready.poke(true)
          dut.clock.step(3)
          dut.io.completion.ready.poke(false)
        }
      }
    }

    it("flushes buffered Copy on whole-system reset and serializes the next Alpha after Copy B") {
      simulate(new RenderEngine) { dut =>
        dut.io.command.valid.poke(false)
        dut.io.vblank.poke(false)
        dut.io.perfClear.poke(false)
        dut.io.underflowPulse.poke(false)
        dut.io.renderGrant.poke(0)
        dut.io.scanoutGrant.poke(0)
        dut.io.textureCacheLoad.valid.poke(false)
        dut.io.textureCacheLoad.bits.poke(0.U.asTypeOf(new TextureCacheLoad))
        dut.io.textureCacheInvalidate.poke(false)
        dut.io.completion.ready.poke(true)
        dut.io.axi.ar.ready.poke(true)
        dut.io.axi.aw.ready.poke(true)
        dut.io.axi.w.ready.poke(false)
        dut.io.axi.r.valid.poke(false)
        dut.io.axi.r.bits.poke(0.U.asTypeOf(new Axi4ReadData))
        dut.io.axi.b.valid.poke(false)
        dut.io.axi.b.bits.poke(0.U.asTypeOf(new Axi4WriteResponse))
        dut.io.command.bits.poke(0.U.asTypeOf(new GpuCommand))
        dut.io.command.bits.op.poke(GpuOpcode.Copy)
        dut.io.command.bits.srcAddr.poke(0x02400000L)
        dut.io.command.bits.dstAddr.poke(0x02000000L)
        dut.io.command.bits.widthPixels.poke(32)
        dut.io.command.bits.heightPixels.poke(2)
        dut.io.command.bits.srcStride.poke(64)
        dut.io.command.bits.dstStride.poke(64)
        dut.io.command.valid.poke(true)
        dut.clock.step()
        dut.io.command.valid.poke(false)
        var addressSeen = false
        for (_ <- 0 until 30 if !addressSeen) {
          addressSeen = dut.io.axi.ar.valid.peek().litToBoolean
          dut.clock.step()
        }
        addressSeen shouldBe true
        dut.io.axi.r.valid.poke(true)
        dut.io.axi.r.bits.data.poke(0xdeadbeefL)
        for (_ <- 0 until 8) {
          dut.io.axi.r.ready.expect(true)
          dut.clock.step()
        }
        // Both the GPU and AXI peer are reset; GPU-only reset cannot cancel old AXI transactions.
        dut.io.axi.r.valid.poke(false)
        dut.reset.poke(true)
        dut.clock.step(2)
        dut.reset.poke(false)
        dut.clock.step()
        dut.io.axi.ar.valid.expect(false)
        dut.io.axi.aw.valid.expect(false)
        dut.io.axi.w.valid.expect(false)
        dut.io.completion.valid.expect(false)
        dut.io.axi.w.ready.poke(true)

        val memory = collection.mutable.Map[Long, Long](
          0x02400000L -> 0xffffffffL, 0x02400004L -> 0xffffffffL, 0x02400008L -> 0xffffffffL,
          0x02600000L -> 0L, 0x02000000L -> 0L, 0x02000004L -> 0L, 0x02000008L -> 0L)
        var submitted = 0
        var readAddress = 0L
        var readId = 0
        var readBeats = 0
        var writeAddress = 0L
        var writeBeats = 0
        var responseDelay = -1
        var copyBSeen = false
        val completed = collection.mutable.ArrayBuffer.empty[Int]
        for (_ <- 0 until 500 if completed.size < 2) {
          dut.io.command.valid.poke(submitted < 2)
          dut.io.command.bits.poke(0.U.asTypeOf(new GpuCommand))
          dut.io.command.bits.op.poke(if (submitted == 0) GpuOpcode.Copy else GpuOpcode.Alpha)
          dut.io.command.bits.srcAddr.poke(if (submitted == 0) 0x02400000L else 0x02600000L)
          dut.io.command.bits.dstAddr.poke(0x02000000L)
          dut.io.command.bits.widthPixels.poke(if (submitted == 0) 3 else 2)
          dut.io.command.bits.heightPixels.poke(if (submitted == 0) 2 else 1)
          dut.io.command.bits.srcStride.poke(if (submitted == 0) 6 else 4)
          dut.io.command.bits.dstStride.poke(if (submitted == 0) 6 else 4)
          dut.io.command.bits.alpha.poke(128)
          dut.io.command.bits.tag.poke(submitted + 10)
          dut.io.axi.ar.ready.poke(readBeats == 0)
          dut.io.axi.r.valid.poke(readBeats > 0)
          dut.io.axi.r.bits.data.poke(memory.getOrElse(readAddress, 0L))
          dut.io.axi.r.bits.id.poke(readId)
          dut.io.axi.r.bits.last.poke(readBeats == 1)
          dut.io.axi.b.valid.poke(responseDelay == 0)
          val commandFire = submitted < 2 && dut.io.command.ready.peek().litToBoolean
          val arFire = readBeats == 0 && dut.io.axi.ar.valid.peek().litToBoolean
          val rFire = readBeats > 0 && dut.io.axi.r.ready.peek().litToBoolean
          val awFire = dut.io.axi.aw.valid.peek().litToBoolean
          val wFire = dut.io.axi.w.valid.peek().litToBoolean
          val bFire = responseDelay == 0 && dut.io.axi.b.ready.peek().litToBoolean
          if (arFire) {
            readAddress = dut.io.axi.ar.bits.addr.peek().litValue.longValue
            readId = dut.io.axi.ar.bits.id.peek().litValue.toInt
            readBeats = dut.io.axi.ar.bits.len.peek().litValue.toInt + 1
            if (readAddress != 0x02400000L) { copyBSeen shouldBe true; completed.headOption shouldBe Some(10) }
          }
          if (awFire) {
            writeBeats shouldBe 0
            responseDelay shouldBe -1
            writeAddress = dut.io.axi.aw.bits.addr.peek().litValue.longValue
            writeBeats = dut.io.axi.aw.bits.len.peek().litValue.toInt + 1
          }
          if (wFire) {
            dut.io.axi.w.bits.last.expect(writeBeats == 1)
            val data = dut.io.axi.w.bits.data.peek().litValue.longValue
            val strobe = dut.io.axi.w.bits.strb.peek().litValue.toInt
            var old = memory.getOrElse(writeAddress, 0L)
            for (b <- 0 until 4 if ((strobe >> b) & 1) != 0)
              old = (old & ~(255L << (8 * b))) | (data & (255L << (8 * b)))
            memory(writeAddress) = old
            writeAddress += 4
            writeBeats -= 1
            if (writeBeats == 0) responseDelay = 30
          }
          if (dut.io.completion.valid.peek().litToBoolean) {
            copyBSeen shouldBe true
            responseDelay shouldBe -1
            dut.io.completion.bits.error.expect(GpuError.None)
            completed += dut.io.completion.bits.tag.peek().litValue.toInt
          }
          dut.clock.step()
          if (commandFire) submitted += 1
          if (rFire) { readAddress += 4; readBeats -= 1 }
          if (responseDelay > 0) responseDelay -= 1
          if (bFire) { copyBSeen = true; responseDelay = -1 }
        }
        completed.toSeq shouldBe Seq(10, 11)
        // black foreground, white background, alpha128: R/B=15, G=31.
        memory(0x02000000L) shouldBe 0x7bef7befL
        memory(0x02000004L) shouldBe 0xffffffffL
        memory(0x02000008L) shouldBe 0xffffffffL
        dut.io.perfPixels.expect(8)
        dut.io.perfWriteBytes.expect(16)
      }
    }
  }
}
