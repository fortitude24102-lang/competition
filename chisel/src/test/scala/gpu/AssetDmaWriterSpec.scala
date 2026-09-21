package gpu

import chisel3._
import org.scalatest.funspec.AnyFunSpec
import org.scalatest.matchers.should.Matchers
import scala.collection.mutable.ArrayBuffer
import scala.util.Random
import testutil.StableChiselSim

class AssetDmaWriterSpec extends AnyFunSpec with StableChiselSim with Matchers {
  private def initialize(dut: AssetDmaWriter): Unit = {
    dut.io.descriptor.poke(0.U.asTypeOf(new AssetDmaDescriptor))
    dut.io.meta.valid.poke(false)
    dut.io.meta.bits.poke(0.U.asTypeOf(new AssetPacketMeta))
    dut.io.payload.valid.poke(false)
    dut.io.payload.bits.poke(0.U.asTypeOf(new AssetPayloadByte))
    dut.io.abort.poke(false)
    dut.io.axi.aw.ready.poke(false)
    dut.io.axi.w.ready.poke(false)
    dut.io.axi.b.valid.poke(false)
    dut.io.axi.b.bits.id.poke(0)
    dut.io.axi.b.bits.resp.poke(Axi4.Okay)
    dut.io.axi.ar.ready.poke(false)
    dut.io.axi.r.valid.poke(false)
    dut.io.axi.r.bits.poke(0.U.asTypeOf(new Axi4ReadData))
    dut.reset.poke(true)
    dut.clock.step(2)
    dut.reset.poke(false)
  }

  private def sendPacket(dut: AssetDmaWriter, address: BigInt, bytes: Seq[Int],
                         random: Random, response: Int = Axi4.Okay):
      (Seq[(BigInt, Int)], Seq[(BigInt, Int, Boolean)]) = {
    dut.io.descriptor.dstAddr.poke(address)
    dut.io.meta.bits.session.poke(1)
    dut.io.meta.bits.assetId.poke(2)
    dut.io.meta.bits.offset.poke(0)
    dut.io.meta.bits.length.poke(bytes.length)
    dut.io.meta.bits.flags.poke(1)
    dut.io.meta.bits.sequence.poke(0)
    dut.io.meta.bits.crc32.poke(0)
    dut.io.meta.valid.poke(true)
    while (!dut.io.meta.ready.peek().litToBoolean) dut.clock.step()
    dut.clock.step()
    dut.io.meta.valid.poke(false)

    for ((byte, index) <- bytes.zipWithIndex) {
      dut.io.payload.valid.poke(true)
      dut.io.payload.bits.data.poke(byte)
      dut.io.payload.bits.last.poke(index == bytes.length - 1)
      while (!dut.io.payload.ready.peek().litToBoolean) dut.clock.step()
      dut.clock.step()
    }
    dut.io.payload.valid.poke(false)

    val addresses = ArrayBuffer.empty[(BigInt, Int)]
    val writes = ArrayBuffer.empty[(BigInt, Int, Boolean)]
    var responsePending = false
    var finished = false
    var cycles = 0
    while (!finished && cycles < 10000) {
      dut.io.axi.aw.ready.poke(random.nextBoolean())
      dut.io.axi.w.ready.poke(random.nextBoolean())
      dut.io.axi.b.valid.poke(responsePending)
      dut.io.axi.b.bits.resp.poke(response)

      val awFire = dut.io.axi.aw.valid.peek().litToBoolean && dut.io.axi.aw.ready.peek().litToBoolean
      val wFire = dut.io.axi.w.valid.peek().litToBoolean && dut.io.axi.w.ready.peek().litToBoolean
      val bFire = dut.io.axi.b.valid.peek().litToBoolean && dut.io.axi.b.ready.peek().litToBoolean
      if (awFire) addresses += dut.io.axi.aw.bits.addr.peek().litValue ->
        (dut.io.axi.aw.bits.len.peek().litValue.toInt + 1)
      if (wFire) writes += ((dut.io.axi.w.bits.data.peek().litValue,
        dut.io.axi.w.bits.strb.peek().litValue.toInt,
        dut.io.axi.w.bits.last.peek().litToBoolean))
      if (bFire) responsePending = false
      if (wFire && dut.io.axi.w.bits.last.peek().litToBoolean) responsePending = true
      finished = dut.io.packetCommitted.peek().litToBoolean || dut.io.packetFailed.peek().litToBoolean
      if (!finished) {
        dut.clock.step()
        cycles += 1
      }
    }
    assert(finished, "Asset DMA packet did not finish")
    if (response == Axi4.Okay) {
      dut.io.packetCommitted.expect(true)
      dut.io.packetBytes.expect(bytes.length)
      dut.io.packetLast.expect(true)
    } else {
      dut.io.packetFailed.expect(true)
      dut.io.packetError.expect(AssetDmaError.AxiResponse)
    }
    dut.clock.step()
    addresses.toSeq -> writes.toSeq
  }

  describe("AssetDmaWriter") {
    it("packs 1/2/3/1023/1024 bytes exactly under deterministic AXI backpressure") {
      simulate(new AssetDmaWriter) { dut =>
        initialize(dut)
        for (length <- Seq(1, 2, 3, 1023, 1024)) {
          val bytes = (0 until length).map(_ & 0xff)
          val (addresses, writes) = sendPacket(
            dut, GpuMemoryMap.DenseAssets, bytes, new Random(0x5eedL + length))
          addresses shouldBe Seq(GpuMemoryMap.DenseAssets -> ((length + 3) / 4))
          writes.length shouldBe (length + 3) / 4
          writes.head._1 shouldBe
            (BigInt("03020100", 16) & ((BigInt(1) << (length.min(4) * 8)) - 1))
          writes.last._2 shouldBe ((1 << (((length - 1) & 3) + 1)) - 1)
          writes.last._3 shouldBe true
        }
      }
    }

    it("splits at 4 KiB, reports B errors, and aborts a buffered packet before issuing AXI") {
      simulate(new AssetDmaWriter) { dut =>
        initialize(dut)
        val bytes = (0 until 1024).map(_ & 0xff)
        val (addresses, _) = sendPacket(
          dut, GpuMemoryMap.DenseAssets + 0xe00, bytes, new Random(7))
        addresses shouldBe Seq(
          (GpuMemoryMap.DenseAssets + 0xe00) -> 128,
          (GpuMemoryMap.DenseAssets + 0x1000) -> 128
        )

        sendPacket(dut, GpuMemoryMap.DenseAssets, Seq(1, 2, 3, 4),
          new Random(9), response = 2)

        dut.io.descriptor.dstAddr.poke(GpuMemoryMap.DenseAssets)
        dut.io.meta.bits.length.poke(4)
        dut.io.meta.bits.flags.poke(1)
        dut.io.meta.valid.poke(true)
        dut.clock.step()
        dut.io.meta.valid.poke(false)
        dut.io.payload.valid.poke(true)
        dut.io.payload.bits.data.poke(0xaa)
        dut.io.payload.bits.last.poke(false)
        dut.clock.step()
        dut.io.payload.valid.poke(false)
        dut.io.abort.poke(true)
        dut.clock.step()
        dut.io.abort.poke(false)
        dut.io.abortDone.expect(true)
        dut.io.axi.aw.valid.expect(false)
      }
    }
  }
}
