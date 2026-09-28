package gpu

import chisel3._
import org.scalatest.funspec.AnyFunSpec
import org.scalatest.matchers.should.Matchers
import testutil.StableChiselSim

class TextureCacheSpec extends AnyFunSpec with StableChiselSim with Matchers {
  private val base = GpuMemoryMap.DenseAssets

  private def init(dut: TextureCache): Unit = {
    dut.io.load.valid.poke(false)
    dut.io.load.bits.base.poke(0)
    dut.io.load.bits.bytes.poke(0)
    dut.io.invalidate.poke(false)
    dut.io.readRequest.valid.poke(false)
    dut.io.readRequest.bits.address.poke(0)
    dut.io.readRequest.bits.bytes.poke(0)
    dut.io.readData.ready.poke(false)
    dut.io.perfClear.poke(false)
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

  private def startLoad(dut: TextureCache, address: BigInt, bytes: Int): Unit = {
    dut.io.load.bits.base.poke(address)
    dut.io.load.bits.bytes.poke(bytes)
    dut.io.load.valid.poke(true)
    dut.io.load.ready.expect(true)
    dut.clock.step()
    dut.io.load.valid.poke(false)
  }

  private def feedLoad(dut: TextureCache, address: BigInt, words: Int,
                       failAt: Int = -1): Unit = {
    var sent = 0
    while (sent < words) {
      val burstWords = math.min(256, words - sent)
      dut.io.axi.ar.valid.expect(true)
      dut.io.axi.ar.bits.addr.expect(address + sent * 4)
      dut.io.axi.ar.bits.len.expect(burstWords - 1)
      dut.io.axi.ar.ready.poke(true)
      dut.clock.step()
      dut.io.axi.ar.ready.poke(false)

      for (beat <- 0 until burstWords) {
        val index = sent + beat
        dut.io.axi.r.valid.poke(true)
        dut.io.axi.r.bits.id.poke(0)
        dut.io.axi.r.bits.data.poke(0x5a000000L | index)
        dut.io.axi.r.bits.resp.poke(if (index == failAt) 2 else Axi4.Okay)
        dut.io.axi.r.bits.last.poke(beat == burstWords - 1)
        dut.io.axi.r.ready.expect(true)
        dut.clock.step()
      }
      dut.io.axi.r.valid.poke(false)
      sent += burstWords
    }
    dut.clock.step()
  }

  private def startRead(dut: TextureCache, address: BigInt, bytes: Int): Unit = {
    dut.io.readRequest.bits.address.poke(address)
    dut.io.readRequest.bits.bytes.poke(bytes)
    dut.io.readRequest.valid.poke(true)
    dut.io.readRequest.ready.expect(true)
    dut.clock.step()
    dut.io.readRequest.valid.poke(false)
  }

  describe("TextureCache") {
    it("preloads 3104 bytes and serves unaligned word streams") {
      simulate(new TextureCache) { dut =>
        init(dut)
        startLoad(dut, base, 3104)
        dut.io.busy.expect(true)
        dut.io.valid.expect(false)
        feedLoad(dut, base, 776)
        dut.io.busy.expect(false)
        dut.io.valid.expect(true)
        dut.io.error.expect(false)
        dut.io.base.expect(base)
        dut.io.bytes.expect(3104)

        startRead(dut, base + 2, 6)
        dut.io.readData.ready.poke(true)
        var latency = 0
        while (!dut.io.readData.valid.peek().litToBoolean && latency < 4) {
          dut.clock.step()
          latency += 1
        }
        dut.io.readData.valid.expect(true)
        dut.io.readData.bits.address.expect(base)
        dut.io.readData.bits.data.expect(0x5a000000L)
        dut.io.readData.bits.last.expect(false)
        dut.clock.step()
        dut.io.readData.valid.expect(true)
        dut.io.readData.bits.address.expect(base + 4)
        dut.io.readData.bits.data.expect(0x5a000001L)
        dut.io.readData.bits.last.expect(true)
        dut.clock.step()
        dut.io.readDone.expect(true)
        dut.io.readError.expect(false)
        dut.io.hitBytes.expect(8)
        dut.io.perfClear.poke(true)
        dut.clock.step()
        dut.io.perfClear.poke(false)
        dut.io.hitBytes.expect(0)
      }
    }

    it("splits a maximum preload at 4 KiB and holds data under backpressure") {
      simulate(new TextureCache) { dut =>
        init(dut)
        startLoad(dut, base + 0x2000, 4096)
        feedLoad(dut, base + 0x2000, 1024)
        dut.io.valid.expect(true)

        startRead(dut, base + 0x2ffc, 4)
        dut.io.readData.ready.poke(false)
        dut.clock.step(3)
        dut.io.readData.valid.expect(true)
        dut.io.readData.bits.address.expect(base + 0x2ffc)
        dut.io.readData.bits.data.expect(0x5a0003ffL)
        dut.io.readData.bits.last.expect(true)
        dut.io.readData.ready.poke(true)
        dut.clock.step()
        dut.io.readDone.expect(true)
      }
    }

    it("keeps the old image invalid during reload") {
      simulate(new TextureCache) { dut =>
        init(dut)
        startLoad(dut, base, 4)
        feedLoad(dut, base, 1)
        dut.io.valid.expect(true)

        startLoad(dut, base + 0x1000, 4)
        dut.io.valid.expect(false)
        dut.io.busy.expect(true)
        dut.io.readRequest.valid.poke(true)
        dut.io.readRequest.bits.address.poke(base)
        dut.io.readRequest.bits.bytes.poke(4)
        dut.io.readRequest.ready.expect(false)
        dut.io.readRequest.valid.poke(false)
        feedLoad(dut, base + 0x1000, 1)
        dut.io.valid.expect(true)
        dut.io.base.expect(base + 0x1000)

        dut.io.invalidate.poke(true)
        dut.clock.step()
        dut.io.invalidate.poke(false)
        dut.io.valid.expect(false)
        dut.io.busy.expect(false)
      }
    }

    it("rejects an errored AXI preload without partial validity") {
      simulate(new TextureCache) { dut =>
        init(dut)
        startLoad(dut, base, 8)
        feedLoad(dut, base, 2, failAt = 1)
        dut.io.busy.expect(false)
        dut.io.valid.expect(false)
        dut.io.error.expect(true)
        dut.io.readRequest.ready.expect(false)

        Seq(
          (base + 2, 4),
          (base, 0),
          (base, 4100),
          (GpuMemoryMap.AssetStart - 4, 4),
          (GpuMemoryMap.AssetEndExclusive - 4, 8),
          (BigInt("fffffffc", 16), 8)
        ).foreach { case (address, bytes) =>
          startLoad(dut, address, bytes)
          dut.io.busy.expect(false)
          dut.io.valid.expect(false)
          dut.io.error.expect(true)
          dut.io.axi.ar.valid.expect(false)
        }
      }
    }
  }
}
