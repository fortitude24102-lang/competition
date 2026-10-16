package gpu

import chisel3._
import org.scalatest.funspec.AnyFunSpec
import org.scalatest.matchers.should.Matchers
import testutil.StableChiselSim

class CopyBurstBufferSpec extends AnyFunSpec with StableChiselSim with Matchers {
  describe("burst-sized Copy staging") {
    it("accepts a complete source burst while writes stall, then drains data and errors before completion") {
      // A too-small/full FIFO must fail this prefetch contract, not silently backpressure R.
      for (fail <- Seq(false, true)) simulate(new CopyStreamEngine(bufferWords = 256)) { d =>
        d.io.command.valid.poke(false)
        d.io.command.bits.poke(0.U.asTypeOf(new GpuCommand))
        d.io.command.bits.op.poke(GpuOpcode.Copy)
        d.io.command.bits.srcAddr.poke(0x02400c00L)
        d.io.command.bits.dstAddr.poke(0x02000c00L)
        d.io.command.bits.srcStride.poke(1024)
        d.io.command.bits.dstStride.poke(1024)
        d.io.command.bits.widthPixels.poke(512)
        d.io.command.bits.heightPixels.poke(2)
        d.io.command.bits.tag.poke(23)
        d.io.readRequest.ready.poke(true); d.io.writeRequest.ready.poke(true)
        d.io.readData.valid.poke(false); d.io.readData.bits.poke(0.U.asTypeOf(new AxiReadBeat))
        d.io.readDone.poke(false); d.io.readError.poke(false)
        d.io.writeData.ready.poke(false); d.io.writeDone.poke(false); d.io.writeError.poke(false)
        d.io.completion.ready.poke(false)
        d.reset.poke(true); d.clock.step(2); d.reset.poke(false)
        d.io.command.valid.poke(true); d.io.command.ready.expect(true); d.clock.step()
        d.io.command.valid.poke(false)
        d.io.readRequest.valid.expect(true); d.io.readRequest.bits.bytes.expect(2048)
        d.io.writeRequest.valid.expect(true); d.io.writeRequest.bits.beats.expect(512)
        d.clock.step()
        for (i <- 0 until 256) {
          d.io.readData.valid.poke(true); d.io.readData.bits.data.poke(0x10000L+i)
          d.io.readData.ready.expect(true); d.io.completion.valid.expect(false); d.clock.step()
        }
        d.io.readData.ready.expect(false)
        var read = 256; var written = 0; var cycles = 0; var lastRead = false
        while (written < 512 && cycles < 1300) {
          d.io.readData.valid.poke(read < 512)
          d.io.readData.bits.data.poke(0x10000L+read)
          d.io.readData.bits.last.poke(read == 511)
          d.io.readDone.poke(lastRead); d.io.readError.poke(lastRead && fail)
          d.io.writeData.ready.poke(cycles%5 != 0)
          val r = read < 512 && d.io.readData.ready.peek().litToBoolean
          val w = cycles%5 != 0 && d.io.writeData.valid.peek().litToBoolean
          if (w) {d.io.writeData.bits.data.expect(0x10000L+written);d.io.writeData.bits.strb.expect(15)}
          d.io.completion.valid.expect(false);d.clock.step()
          if (r) read += 1
          if (w) written += 1
          lastRead = r && read == 512;cycles += 1
        }
        read shouldBe 512;written shouldBe 512
        d.io.readData.valid.poke(false);d.io.readDone.poke(false);d.io.readError.poke(false)
        d.clock.step(20);d.io.completion.valid.expect(false)
        d.io.writeDone.poke(true);d.io.writeError.poke(fail);d.clock.step()
        d.io.writeDone.poke(false);d.io.writeError.poke(false);d.clock.step(2)
        d.io.completion.valid.expect(true);d.io.completion.bits.tag.expect(23)
        d.io.completion.bits.error.expect(if(fail) GpuError.AxiResponse else GpuError.None)
        d.clock.step(3);d.io.completion.valid.expect(true)
        d.io.completion.ready.poke(true);d.clock.step();d.io.command.ready.expect(true)
      }
    }
  }
}
