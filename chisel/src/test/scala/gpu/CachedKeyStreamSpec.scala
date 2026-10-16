package gpu

import chisel3._
import org.scalatest.funspec.AnyFunSpec
import org.scalatest.matchers.should.Matchers
import testutil.StableChiselSim

class CachedKeyStreamSpec extends AnyFunSpec with StableChiselSim with Matchers {
  describe("whole-sprite cached Key prefetch") {
    for ((failWrite, failRead, width, height, stride) <- Seq(
      (false, false, 8, 4, 1920), (false, false, 8, 4, 1922),
      (true, false, 8, 4, 1920), (false, true, 8, 4, 1920), (true, false, 16, 16, 1920))) {
      it(s"keeps lanes/drains ${width}x$height stride=$stride with B error=$failWrite read error=$failRead") {
        simulate(new CachedKeyStream) { d =>
          val src = 0x02a00000L; val dst = 0x02000102L
          val pixels = (0 until width*height).map(i => if (i % 3 == 0) 0xbeef else i + 1)
          val memory = collection.mutable.Map.empty[Long, Int].withDefaultValue(0xa5)
          d.io.command.bits.poke(0.U.asTypeOf(new GpuCommand))
          d.io.command.bits.op.poke(GpuOpcode.ColorKey)
          d.io.command.bits.srcAddr.poke(src); d.io.command.bits.dstAddr.poke(dst)
          d.io.command.bits.srcStride.poke(width*2); d.io.command.bits.dstStride.poke(stride)
          d.io.command.bits.widthPixels.poke(width); d.io.command.bits.heightPixels.poke(height)
          d.io.command.bits.colorKey.poke(0xbeef); d.io.command.bits.tag.poke(71)
          d.io.command.valid.poke(false); d.io.completion.ready.poke(false)
          d.io.readRequest.ready.poke(true); d.io.readData.valid.poke(false)
          d.io.readData.bits.poke(0.U.asTypeOf(new AxiReadBeat))
          d.io.readDone.poke(false); d.io.readError.poke(false)
          d.io.writeRequest.ready.poke(true); d.io.writeData.ready.poke(false)
          d.io.writeDone.poke(false); d.io.writeError.poke(false)
          d.reset.poke(true); d.clock.step(2); d.reset.poke(false)
          d.io.eligible.expect(true)
          d.io.command.bits.widthPixels.poke(9); d.io.eligible.expect(false)
          d.io.command.bits.widthPixels.poke(width)
          var submitted = false; var reads = 0; var received = 0; var readLeft = 0
          var awCount = 0; var writeLeft = 0; var writeAddress = 0L
          var responseDelay = -1; var readDone = false; var complete = false
          var ahead = 0; var cycles = 0
          while (!complete && cycles < 1000) {
            d.io.command.valid.poke(!submitted)
            d.io.readData.valid.poke(readLeft > 0)
            val index = received * 2
            val data = if (readLeft > 0) pixels(index).toLong | (pixels(index + 1).toLong << 16) else 0L
            d.io.readData.bits.data.poke(data); d.io.readData.bits.address.poke(src + received * 4)
            d.io.readData.bits.last.poke(readLeft == 1)
            d.io.readDone.poke(readDone)
            d.io.readError.poke(readDone && failRead)
            d.io.writeRequest.ready.poke(writeLeft == 0 && responseDelay < 0)
            d.io.writeData.ready.poke(writeLeft > 0 && cycles % 5 != 0)
            val b = responseDelay == 0
            d.io.writeDone.poke(b); d.io.writeError.poke(b && failWrite && awCount == 1)
            val cmd = !submitted && d.io.command.ready.peek().litToBoolean
            val ar = d.io.readRequest.valid.peek().litToBoolean
            val r = readLeft > 0 && d.io.readData.ready.peek().litToBoolean
            val aw = d.io.writeRequest.valid.peek().litToBoolean && d.io.writeRequest.ready.peek().litToBoolean
            val w = d.io.writeData.valid.peek().litToBoolean && d.io.writeData.ready.peek().litToBoolean
            if (ar) {
              reads += 1; d.io.readRequest.bits.address.expect(src); d.io.readRequest.bits.bytes.expect(width*height*2)
              readLeft = width*height/2
            }
            if (aw) {
              val row = dst + awCount * stride
              d.io.writeRequest.bits.address.expect(row & ~3L)
              val beats=(width*2+(row&3).toInt+3)/4
              d.io.writeRequest.bits.beats.expect(beats)
              writeAddress = row & ~3L; writeLeft = beats; awCount += 1
            }
            if (w) {
              val word = d.io.writeData.bits.data.peek().litValue
              val strb = d.io.writeData.bits.strb.peek().litValue.toInt
              for (lane <- 0 until 4 if ((strb >> lane) & 1) != 0)
                memory(writeAddress + lane) = ((word >> (8 * lane)) & 255).toInt
              writeAddress += 4; writeLeft -= 1
              if (writeLeft == 0) responseDelay = 30
            }
            if (awCount == 1 && responseDelay > 0) ahead = ahead.max(received)
            complete = d.io.completion.valid.peek().litToBoolean
            if (complete) {
              d.io.completion.bits.tag.expect(71)
              d.io.completion.bits.error.expect(if (failWrite || failRead) GpuError.AxiResponse else GpuError.None)
              d.io.command.ready.expect(false)
            }
            d.clock.step(); cycles += 1
            if (cmd) submitted = true
            readDone = false
            if (r) {received += 1; readLeft -= 1; if (readLeft == 0) readDone = true}
            if (responseDelay >= 0) responseDelay -= 1
          }
          complete shouldBe true; reads shouldBe 1; received shouldBe width*height/2
          ahead should be > width/2 // Later source rows arrive while row0 waits for B.
          awCount shouldBe (if (failWrite || failRead) 1 else height)
          for (y <- 0 until awCount; x <- 0 until width) {
            val address = dst + y * stride + x * 2
            val expected = if (pixels(y * width + x) == 0xbeef) 0xa5a5 else pixels(y * width + x)
            (memory(address) | (memory(address + 1) << 8)) shouldBe expected
          }
          memory(dst - 1) shouldBe 0xa5; memory(dst + width*2) shouldBe 0xa5
          d.clock.step(3); d.io.completion.valid.expect(true)
          d.io.completion.ready.poke(true); d.clock.step(); d.io.command.ready.expect(true)
        }
      }
    }
  }
}
