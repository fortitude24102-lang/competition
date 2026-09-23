package gpu

import chisel3._
import org.scalatest.funspec.AnyFunSpec
import org.scalatest.matchers.should.Matchers
import testutil.StableChiselSim

class DdrQosArbiterSpec extends AnyFunSpec with StableChiselSim with Matchers {
  describe("DdrQosArbiter") {
    it("drains a full Render burst before serving Scanout despite Render response backpressure") {
      simulate(new DdrQosArbiter) { dut =>
        dut.io.lowWatermark.poke(10)
        dut.io.highWatermark.poke(20)
        dut.io.adaptiveEnable.poke(true)
        dut.io.scanoutLevel.poke(20)
        for (port <- Seq(dut.io.render, dut.io.scanout, dut.io.asset)) {
          port.ar.bits.poke(0.U.asTypeOf(new Axi4Address))
          port.aw.bits.poke(0.U.asTypeOf(new Axi4Address))
          port.w.bits.poke(0.U.asTypeOf(new Axi4WriteData))
          port.ar.valid.poke(false)
          port.aw.valid.poke(false)
          port.w.valid.poke(false)
          port.r.ready.poke(false)
          port.b.ready.poke(true)
        }
        dut.io.axi.ar.ready.poke(true)
        dut.io.axi.aw.ready.poke(true)
        dut.io.axi.w.ready.poke(true)
        dut.io.axi.r.valid.poke(false)
        dut.io.axi.r.bits.poke(0.U.asTypeOf(new Axi4ReadData))
        dut.io.axi.b.valid.poke(false)
        dut.io.axi.b.bits.poke(0.U.asTypeOf(new Axi4WriteResponse))
        dut.io.render.ar.bits.addr.poke(0x1000)
        dut.io.render.ar.bits.len.poke(255)
        dut.io.render.ar.valid.poke(true)
        dut.clock.step(2)
        dut.io.render.ar.valid.poke(false)
        dut.io.scanoutLevel.poke(0)
        dut.io.scanout.ar.bits.addr.poke(0x2000)
        dut.io.scanout.ar.valid.poke(true)
        dut.io.scanout.r.ready.poke(true)
        for (beat <- 0 until 256) {
          dut.io.axi.r.valid.poke(true)
          dut.io.axi.r.bits.data.poke(0x10000 + beat)
          dut.io.axi.r.bits.id.poke(1)
          dut.io.axi.r.bits.resp.poke(if (beat == 17) 2 else 0)
          dut.io.axi.r.bits.last.poke(beat == 255)
          dut.io.axi.r.ready.expect(true)
          dut.clock.step()
        }
        dut.io.axi.r.valid.poke(false)
        dut.clock.step()
        dut.io.axi.ar.valid.expect(true)
        dut.io.axi.ar.bits.addr.expect(0x2000)
        dut.clock.step()
        dut.io.scanout.ar.valid.poke(false)
        dut.io.axi.r.bits.id.poke(0)
        dut.io.axi.r.bits.data.poke(0xabcdef)
        dut.io.axi.r.bits.resp.poke(0)
        dut.io.axi.r.bits.last.poke(true)
        dut.io.axi.r.valid.poke(true)
        dut.io.scanout.r.valid.expect(true)
        dut.io.scanout.r.bits.data.expect(0xabcdef)
        dut.clock.step()
        dut.io.axi.r.valid.poke(false)
        dut.io.scanoutLevel.poke(20)
        dut.io.render.ar.bits.addr.poke(0x3000)
        dut.io.render.ar.valid.poke(true)
        dut.clock.step(3)
        dut.io.axi.ar.valid.expect(false) // Reserve a whole burst, not residual capacity.
        dut.io.render.r.ready.poke(true)
        for (beat <- 0 until 256) {
          dut.io.render.r.valid.expect(true)
          dut.io.render.r.bits.data.expect(0x10000 + beat)
          dut.io.render.r.bits.id.expect(1)
          dut.io.render.r.bits.resp.expect(if (beat == 17) 2 else 0)
          dut.io.render.r.bits.last.expect(beat == 255)
          dut.clock.step()
        }
        dut.clock.step()
        dut.io.axi.ar.valid.expect(true)
        dut.io.axi.ar.bits.addr.expect(0x3000)
      }
    }

    it("cancels unpresented addresses at emergency entry but holds presented AXI VALID") {
      simulate(new DdrQosArbiter) { dut =>
        dut.io.lowWatermark.poke(10)
        dut.io.highWatermark.poke(20)
        dut.io.adaptiveEnable.poke(true)
        dut.io.scanoutLevel.poke(15)
        dut.io.render.ar.bits.poke(0.U.asTypeOf(new Axi4Address))
        dut.io.render.ar.bits.addr.poke(0x1000)
        dut.io.render.ar.valid.poke(true)
        dut.io.render.aw.valid.poke(false)
        dut.io.render.w.valid.poke(false)
        dut.io.render.r.ready.poke(true)
        dut.io.render.b.ready.poke(true)
        dut.io.scanout.ar.valid.poke(false)
        dut.io.scanout.aw.valid.poke(false)
        dut.io.scanout.w.valid.poke(false)
        dut.io.scanout.r.ready.poke(true)
        dut.io.scanout.b.ready.poke(true)
        dut.io.asset.ar.valid.poke(false)
        dut.io.asset.aw.bits.poke(0.U.asTypeOf(new Axi4Address))
        dut.io.asset.aw.bits.addr.poke(0x4000)
        dut.io.asset.aw.valid.poke(true)
        dut.io.asset.w.valid.poke(false)
        dut.io.asset.r.ready.poke(true)
        dut.io.asset.b.ready.poke(true)
        dut.io.axi.ar.ready.poke(false)
        dut.io.axi.aw.ready.poke(false)
        dut.io.axi.w.ready.poke(false)
        dut.io.axi.r.valid.poke(false)
        dut.io.axi.r.bits.poke(0.U.asTypeOf(new Axi4ReadData))
        dut.io.axi.b.valid.poke(false)
        dut.io.axi.b.bits.poke(0.U.asTypeOf(new Axi4WriteResponse))

        dut.clock.step() // Both clients selected, but no address has been presented.
        dut.io.scanoutLevel.poke(10)
        dut.io.scanoutPriority.expect(true)
        dut.io.axi.ar.valid.expect(false)
        dut.io.axi.aw.valid.expect(false)
        dut.clock.step()
        dut.io.axi.ar.valid.expect(false)
        dut.io.axi.aw.valid.expect(false)

        dut.io.scanoutLevel.poke(20)
        dut.clock.step()
        dut.io.axi.ar.valid.expect(true)
        dut.io.axi.ar.bits.addr.expect(0x1000)
        dut.io.axi.aw.valid.expect(true)
        dut.io.axi.aw.bits.addr.expect(0x4000)
        dut.clock.step() // Backpressure leaves both VALID signals outstanding.
        dut.io.scanoutLevel.poke(10)
        dut.io.axi.ar.valid.expect(true)
        dut.io.axi.ar.bits.addr.expect(0x1000)
        dut.io.axi.aw.valid.expect(true)
        dut.io.axi.aw.bits.addr.expect(0x4000)
      }
    }

    it("locks response ownership for complete read and write transactions and rotates priority") {
      simulate(new DdrQosArbiter) { dut =>
        dut.io.scanoutLevel.poke(4095)
        dut.io.lowWatermark.poke(256)
        dut.io.highWatermark.poke(1536)
        dut.io.adaptiveEnable.poke(false)
        def pokeClientAddress(address: Axi4Address, value: Long): Unit = {
          address.addr.poke(value)
          address.id.poke(0)
          address.len.poke(1)
          address.size.poke(Axi4.WordSize)
          address.burst.poke(Axi4.Incrementing)
          address.lock.poke(false)
          address.cache.poke(0)
          address.prot.poke(0)
          address.qos.poke(0)
          address.region.poke(0)
        }

        pokeClientAddress(dut.io.render.ar.bits, 0x1000)
        pokeClientAddress(dut.io.scanout.ar.bits, 0x2000)
        pokeClientAddress(dut.io.render.aw.bits, 0x3000)
        pokeClientAddress(dut.io.asset.aw.bits, 0x4000)
        dut.io.render.ar.valid.poke(true)
        dut.io.scanout.ar.valid.poke(true)
        dut.io.render.aw.valid.poke(true)
        dut.io.asset.aw.valid.poke(true)
        dut.io.render.w.valid.poke(true)
        dut.io.render.w.bits.data.poke(0x11112222L)
        dut.io.render.w.bits.strb.poke(0xf)
        dut.io.render.w.bits.last.poke(false)
        dut.io.asset.w.valid.poke(true)
        dut.io.asset.w.bits.data.poke(0x33334444L)
        dut.io.asset.w.bits.strb.poke(0xf)
        dut.io.asset.w.bits.last.poke(true)
        dut.io.render.r.ready.poke(true)
        dut.io.scanout.r.ready.poke(true)
        dut.io.render.b.ready.poke(true)
        dut.io.scanout.b.ready.poke(true)
        dut.io.asset.b.ready.poke(true)
        dut.io.asset.ar.valid.poke(false)
        dut.io.asset.r.ready.poke(true)
        dut.io.axi.ar.ready.poke(false)
        dut.io.axi.aw.ready.poke(false)
        dut.io.axi.w.ready.poke(false)
        dut.io.axi.r.valid.poke(false)
        dut.io.axi.r.bits.id.poke(0)
        dut.io.axi.r.bits.data.poke(0)
        dut.io.axi.r.bits.resp.poke(0)
        dut.io.axi.r.bits.last.poke(false)
        dut.io.axi.b.valid.poke(false)
        dut.io.axi.b.bits.id.poke(0)
        dut.io.axi.b.bits.resp.poke(0)

        dut.clock.step()
        dut.io.axi.ar.valid.expect(true)
        dut.io.axi.ar.bits.addr.expect(0x1000)
        dut.io.axi.aw.valid.expect(true)
        dut.io.axi.aw.bits.addr.expect(0x3000)

        dut.io.axi.ar.ready.poke(true)
        dut.io.axi.aw.ready.poke(true)
        dut.clock.step()
        dut.io.render.ar.valid.poke(false)
        dut.io.render.aw.valid.poke(false)
        dut.io.axi.ar.ready.poke(false)
        dut.io.axi.aw.ready.poke(false)

        dut.io.axi.r.valid.poke(true)
        dut.io.axi.r.bits.data.poke(0xaaaabbbbL)
        dut.io.axi.r.bits.last.poke(false)
        dut.io.render.r.ready.poke(false)
        dut.io.render.r.valid.expect(true)
        dut.io.render.r.bits.data.expect(0xaaaabbbbL)
        dut.io.scanout.r.valid.expect(false)
        dut.io.axi.r.ready.expect(true) // Buffered without blocking the physical read channel.
        dut.io.axi.w.valid.expect(true)
        dut.io.axi.w.bits.data.expect(0x11112222L)
        dut.io.render.w.ready.expect(false)
        dut.clock.step()

        dut.io.render.r.ready.poke(true)
        dut.io.axi.r.valid.poke(false) // First beat was accepted into the response FIFO.
        dut.io.axi.w.ready.poke(true)
        dut.clock.step()

        dut.io.axi.r.valid.poke(true)
        dut.io.axi.r.bits.data.poke(0xccccddddL)
        dut.io.axi.r.bits.last.poke(true)
        dut.io.render.w.bits.data.poke(0x55556666L)
        dut.io.render.w.bits.last.poke(true)
        dut.io.render.r.valid.expect(true)
        dut.io.scanout.r.valid.expect(false)
        dut.io.axi.w.valid.expect(true)
        dut.io.axi.w.bits.data.expect(0x55556666L)
        dut.clock.step()

        dut.io.axi.r.valid.poke(false)
        dut.io.render.w.valid.poke(false)
        dut.io.axi.w.ready.poke(false)
        dut.io.axi.b.valid.poke(true)
        dut.io.render.b.ready.poke(false)
        dut.io.render.b.valid.expect(true)
        dut.io.asset.b.valid.expect(false)
        dut.io.axi.b.ready.expect(false)
        dut.clock.step()

        dut.io.render.b.ready.poke(true)
        dut.clock.step()
        dut.io.axi.b.valid.poke(false)

        dut.clock.step()
        dut.io.axi.ar.valid.expect(true)
        dut.io.axi.ar.bits.addr.expect(0x2000)
        dut.io.axi.aw.valid.expect(true)
        dut.io.axi.aw.bits.addr.expect(0x4000)

        dut.io.axi.ar.ready.poke(true)
        dut.io.axi.aw.ready.poke(true)
        dut.clock.step()
        dut.io.scanout.ar.valid.poke(false)
        dut.io.asset.aw.valid.poke(false)
        dut.io.axi.r.valid.poke(true)
        dut.io.axi.r.bits.data.poke(0xccccddddL)
        dut.io.axi.r.bits.last.poke(true)
        dut.io.scanout.r.valid.expect(true)
        dut.io.render.r.valid.expect(false)
        dut.io.axi.w.ready.poke(true)
        dut.io.axi.w.valid.expect(true)
        dut.io.axi.w.bits.data.expect(0x33334444L)
        dut.clock.step()
      }
    }

    it("pauses render and asset admissions during scanout emergency and resumes after high watermark") {
      simulate(new DdrQosArbiter(maxRenderWait = 3)) { dut =>
        def address(port: Axi4Address, value: Long): Unit = {
          port.addr.poke(value)
          port.id.poke(0)
          port.len.poke(0)
          port.size.poke(Axi4.WordSize)
          port.burst.poke(Axi4.Incrementing)
          port.lock.poke(false)
          port.cache.poke(0)
          port.prot.poke(0)
          port.qos.poke(0)
          port.region.poke(0)
        }

        dut.io.lowWatermark.poke(10)
        dut.io.highWatermark.poke(20)
        dut.io.adaptiveEnable.poke(true)
        dut.io.scanoutLevel.poke(15)
        dut.io.render.ar.valid.poke(false)
        dut.io.scanout.ar.valid.poke(false)
        dut.io.render.aw.valid.poke(false)
        dut.io.scanout.aw.valid.poke(false)
        dut.io.asset.aw.valid.poke(false)
        dut.io.render.w.valid.poke(false)
        dut.io.scanout.w.valid.poke(false)
        dut.io.asset.w.valid.poke(false)
        dut.io.render.r.ready.poke(true)
        dut.io.scanout.r.ready.poke(true)
        dut.io.asset.r.ready.poke(true)
        dut.io.render.b.ready.poke(true)
        dut.io.scanout.b.ready.poke(true)
        dut.io.asset.b.ready.poke(true)
        dut.io.axi.ar.ready.poke(true)
        dut.io.axi.aw.ready.poke(true)
        dut.io.axi.w.ready.poke(true)
        dut.io.axi.r.valid.poke(false)
        dut.io.axi.r.bits.poke(0.U.asTypeOf(new Axi4ReadData))
        dut.io.axi.b.valid.poke(false)
        dut.io.axi.b.bits.poke(0.U.asTypeOf(new Axi4WriteResponse))
        address(dut.io.render.ar.bits, 0x1000)
        address(dut.io.scanout.ar.bits, 0x2000)
        address(dut.io.render.aw.bits, 0)
        address(dut.io.scanout.aw.bits, 0)
        address(dut.io.asset.aw.bits, 0x3000)
        address(dut.io.asset.ar.bits, 0)
        dut.clock.step()
        dut.io.scanoutPriority.expect(false)
        dut.io.scanoutLevel.poke(10)
        dut.clock.step()
        dut.io.scanoutPriority.expect(true)
        dut.io.scanoutLevel.poke(11)
        dut.clock.step(2)
        dut.io.scanoutPriority.expect(true)
        dut.io.scanoutLevel.poke(20)
        dut.clock.step()
        dut.io.scanoutPriority.expect(false)

        dut.io.scanoutLevel.poke(0)
        dut.clock.step()
        dut.io.render.ar.valid.poke(true)
        dut.io.scanout.ar.valid.poke(true)
        dut.io.asset.aw.valid.poke(true)
        var grants = Seq.empty[Long]
        var responsePending = false
        for (_ <- 0 until 40) {
          dut.io.axi.r.valid.poke(responsePending)
          dut.io.axi.r.bits.id.poke(0)
          dut.io.axi.r.bits.data.poke(0)
          dut.io.axi.r.bits.resp.poke(Axi4.Okay)
          dut.io.axi.r.bits.last.poke(true)
          val arFire = dut.io.axi.ar.valid.peek().litToBoolean && dut.io.axi.ar.ready.peek().litToBoolean
          val rFire = dut.io.axi.r.valid.peek().litToBoolean && dut.io.axi.r.ready.peek().litToBoolean
          if (arFire) grants :+= dut.io.axi.ar.bits.addr.peek().litValue.longValue
          dut.clock.step()
          if (rFire) responsePending = false
          if (arFire) responsePending = true
        }
        grants should not be empty
        grants.forall(_ == 0x2000L) shouldBe true
        dut.io.axi.aw.valid.expect(false)
        dut.io.scanoutLevel.poke(20)
        dut.io.scanoutPriority.expect(false)
        for (_ <- 0 until 8 if !grants.contains(0x1000L)) {
          dut.io.axi.r.valid.poke(responsePending)
          val arFire = dut.io.axi.ar.valid.peek().litToBoolean && dut.io.axi.ar.ready.peek().litToBoolean
          val rFire = dut.io.axi.r.valid.peek().litToBoolean && dut.io.axi.r.ready.peek().litToBoolean
          if (arFire) grants :+= dut.io.axi.ar.bits.addr.peek().litValue.longValue
          dut.clock.step()
          if (rFire) responsePending = false
          if (arFire) responsePending = true
        }
        grants should contain (0x1000L)
      }
    }

    it("alternates continuously requested Render and Asset writes by complete transaction") {
      simulate(new DdrQosArbiter) { dut =>
        dut.io.scanoutLevel.poke(2048)
        dut.io.lowWatermark.poke(256)
        dut.io.highWatermark.poke(1536)
        dut.io.adaptiveEnable.poke(true)
        dut.io.render.ar.valid.poke(false)
        dut.io.scanout.ar.valid.poke(false)
        dut.io.asset.ar.valid.poke(false)
        dut.io.render.r.ready.poke(true)
        dut.io.scanout.r.ready.poke(true)
        dut.io.asset.r.ready.poke(true)
        dut.io.render.aw.bits.poke(0.U.asTypeOf(new Axi4Address))
        dut.io.render.aw.bits.addr.poke(0x3000)
        dut.io.asset.aw.bits.poke(0.U.asTypeOf(new Axi4Address))
        dut.io.asset.aw.bits.addr.poke(0x4000)
        dut.io.render.aw.valid.poke(true)
        dut.io.asset.aw.valid.poke(true)
        dut.io.scanout.aw.valid.poke(false)
        dut.io.render.w.valid.poke(true)
        dut.io.render.w.bits.poke(0.U.asTypeOf(new Axi4WriteData))
        dut.io.render.w.bits.last.poke(true)
        dut.io.asset.w.valid.poke(true)
        dut.io.asset.w.bits.poke(0.U.asTypeOf(new Axi4WriteData))
        dut.io.asset.w.bits.last.poke(true)
        dut.io.scanout.w.valid.poke(false)
        dut.io.render.b.ready.poke(true)
        dut.io.asset.b.ready.poke(true)
        dut.io.scanout.b.ready.poke(true)
        dut.io.axi.ar.ready.poke(true)
        dut.io.axi.r.valid.poke(false)
        dut.io.axi.r.bits.poke(0.U.asTypeOf(new Axi4ReadData))
        dut.io.axi.aw.ready.poke(true)
        dut.io.axi.w.ready.poke(true)
        dut.io.axi.b.valid.poke(true)
        dut.io.axi.b.bits.poke(0.U.asTypeOf(new Axi4WriteResponse))
        var grants = Seq.empty[BigInt]
        for (_ <- 0 until 40) {
          if (dut.io.axi.aw.valid.peek().litToBoolean) {
            grants :+= dut.io.axi.aw.bits.addr.peek().litValue
          }
          dut.clock.step()
        }
        grants.size should be >= 8
        grants.take(8) shouldBe Seq.fill(4)(Seq(BigInt(0x3000), BigInt(0x4000))).flatten
      }
    }

    it("services a draining scanout FIFO under continuous Asset write pressure") {
      simulate(new DdrQosArbiter) { dut =>
        dut.io.lowWatermark.poke(4)
        dut.io.highWatermark.poke(12)
        dut.io.adaptiveEnable.poke(true)
        dut.io.render.ar.valid.poke(false)
        dut.io.render.aw.valid.poke(false)
        dut.io.render.w.valid.poke(false)
        dut.io.render.r.ready.poke(true)
        dut.io.render.b.ready.poke(true)
        dut.io.scanout.ar.bits.poke(0.U.asTypeOf(new Axi4Address))
        dut.io.scanout.ar.bits.addr.poke(0x2000)
        dut.io.scanout.aw.valid.poke(false)
        dut.io.scanout.w.valid.poke(false)
        dut.io.scanout.r.ready.poke(true)
        dut.io.scanout.b.ready.poke(true)
        dut.io.asset.ar.valid.poke(false)
        dut.io.asset.aw.bits.poke(0.U.asTypeOf(new Axi4Address))
        dut.io.asset.aw.bits.addr.poke(0x4000)
        dut.io.asset.aw.valid.poke(true)
        dut.io.asset.w.bits.poke(0.U.asTypeOf(new Axi4WriteData))
        dut.io.asset.w.bits.last.poke(true)
        dut.io.asset.w.valid.poke(true)
        dut.io.asset.r.ready.poke(true)
        dut.io.asset.b.ready.poke(true)
        dut.io.axi.ar.ready.poke(true)
        dut.io.axi.aw.ready.poke(true)
        dut.io.axi.w.ready.poke(true)
        dut.io.axi.r.bits.poke(0.U.asTypeOf(new Axi4ReadData))
        dut.io.axi.r.bits.last.poke(true)
        dut.io.axi.b.bits.poke(0.U.asTypeOf(new Axi4WriteResponse))
        var level = 8
        var readPending = false
        var writePending = false
        var scanoutReads = 0
        var assetWrites = 0
        for (cycle <- 0 until 240) {
          dut.io.scanoutLevel.poke(level)
          dut.io.scanout.ar.valid.poke(level <= 16)
          dut.io.axi.r.valid.poke(readPending)
          dut.io.axi.b.valid.poke(writePending)
          val arFire = dut.io.axi.ar.valid.peek().litToBoolean && dut.io.axi.ar.ready.peek().litToBoolean
          val awFire = dut.io.axi.aw.valid.peek().litToBoolean && dut.io.axi.aw.ready.peek().litToBoolean
          val wFire = dut.io.axi.w.valid.peek().litToBoolean && dut.io.axi.w.ready.peek().litToBoolean
          val rFire = dut.io.axi.r.valid.peek().litToBoolean && dut.io.axi.r.ready.peek().litToBoolean
          val bFire = dut.io.axi.b.valid.peek().litToBoolean && dut.io.axi.b.ready.peek().litToBoolean
          if (level <= 4) dut.io.axi.aw.valid.expect(false)
          if (arFire) scanoutReads += 1
          if (awFire) assetWrites += 1
          dut.clock.step()
          if (cycle % 2 == 0) {
            withClue(s"scanout underflow at cycle $cycle: ") { level should be > 0 }
            level -= 1
          }
          if (rFire) level = math.min(20, level + 2)
          if (rFire) readPending = false
          if (arFire) readPending = true
          if (bFire) writePending = false
          if (wFire) writePending = true
        }
        scanoutReads should be > 30
        assetWrites should be > 0
      }
    }

    it("bounds three-client waits on a bandwidth-limited shared DDR without scanout underflow") {
      simulate(new DdrQosArbiter) { dut =>
        dut.io.lowWatermark.poke(24)
        dut.io.highWatermark.poke(48)
        dut.io.adaptiveEnable.poke(true)
        for ((port, base, beats) <- Seq(
          (dut.io.render.ar.bits, 0x1000, 4), (dut.io.scanout.ar.bits, 0x2000, 8),
          (dut.io.render.aw.bits, 0x3000, 4), (dut.io.asset.aw.bits, 0x4000, 8))) {
          port.poke(0.U.asTypeOf(new Axi4Address))
          port.addr.poke(base)
          port.len.poke(beats - 1)
          port.size.poke(Axi4.WordSize)
          port.burst.poke(Axi4.Incrementing)
        }
        dut.io.render.ar.valid.poke(true)
        dut.io.render.aw.valid.poke(true)
        dut.io.asset.aw.valid.poke(true)
        dut.io.asset.ar.valid.poke(false)
        dut.io.scanout.aw.valid.poke(false)
        dut.io.scanout.w.valid.poke(false)
        dut.io.render.w.valid.poke(true)
        dut.io.asset.w.valid.poke(true)
        dut.io.render.w.bits.poke(0.U.asTypeOf(new Axi4WriteData))
        dut.io.asset.w.bits.poke(0.U.asTypeOf(new Axi4WriteData))
        dut.io.render.w.bits.strb.poke(15)
        dut.io.asset.w.bits.strb.poke(15)
        for (port <- Seq(dut.io.render, dut.io.scanout, dut.io.asset)) {
          port.r.ready.poke(true)
          port.b.ready.poke(true)
        }
        dut.io.axi.r.bits.poke(0.U.asTypeOf(new Axi4ReadData))
        dut.io.axi.b.bits.poke(0.U.asTypeOf(new Axi4WriteResponse))
        var level = 56
        var readsLeft = 0
        var writesLeft = 0
        var scanoutOwner = false
        var assetOwner = false
        var bDelay = -1
        var preferWrite = false
        var scanoutRequested = false
        var renderWait = 0
        var assetWait = 0
        var emergencies = 0
        var emergencyExits = 0
        var wasEmergency = false
        var renderReads = 0
        var renderWrites = 0
        var assetWrites = 0
        var scanoutReads = 0
        for (cycle <- 0 until 1600) {
          if (level <= 64) scanoutRequested = true
          dut.io.scanoutLevel.poke(level)
          dut.io.scanout.ar.valid.poke(scanoutRequested)
          val emergency = dut.io.scanoutPriority.peek().litToBoolean
          if (emergency && !wasEmergency) emergencies += 1
          if (!emergency && wasEmergency) emergencyExits += 1
          wasEmergency = emergency
          // Exactly one shared data beat every two cycles, plus address stalls
          // and a delayed B response; reads and writes cannot bypass bandwidth.
          val serveWrite = cycle % 2 == 0 && writesLeft > 0 && (readsLeft == 0 || preferWrite)
          val serveRead = cycle % 2 == 0 && readsLeft > 0 && !serveWrite
          dut.io.axi.ar.ready.poke(readsLeft == 0 && cycle % 5 != 0)
          dut.io.axi.aw.ready.poke(writesLeft == 0 && bDelay < 0 && cycle % 7 != 0)
          dut.io.axi.r.valid.poke(serveRead)
          dut.io.axi.r.bits.last.poke(readsLeft == 1)
          dut.io.axi.w.ready.poke(serveWrite)
          dut.io.render.w.bits.last.poke(writesLeft == 1)
          dut.io.asset.w.bits.last.poke(writesLeft == 1)
          dut.io.axi.b.valid.poke(bDelay == 0)
          val ar = dut.io.axi.ar.valid.peek().litToBoolean && dut.io.axi.ar.ready.peek().litToBoolean
          val aw = dut.io.axi.aw.valid.peek().litToBoolean && dut.io.axi.aw.ready.peek().litToBoolean
          val r = serveRead && dut.io.axi.r.ready.peek().litToBoolean
          val w = serveWrite && dut.io.axi.w.valid.peek().litToBoolean
          val b = bDelay == 0 && dut.io.axi.b.ready.peek().litToBoolean
          val arScanout = dut.io.axi.ar.bits.addr.peek().litValue == 0x2000
          val awAsset = dut.io.axi.aw.bits.addr.peek().litValue == 0x4000
          if (r) {
            dut.io.scanout.r.valid.expect(scanoutOwner)
            dut.io.render.r.valid.expect(!scanoutOwner)
          }
          if (b) {
            dut.io.asset.b.valid.expect(assetOwner)
            dut.io.render.b.valid.expect(!assetOwner)
          }
          if (!emergency) {
            if (r && readsLeft == 1 && scanoutOwner) renderWait += 1
            if (b && assetOwner) renderWait += 1
            if (b && !assetOwner) assetWait += 1
          }
          if ((ar && !arScanout) || (aw && !awAsset)) renderWait = 0
          if (aw && awAsset) assetWait = 0
          renderWait should be <= 8
          assetWait should be <= 8
          dut.clock.step()
          if (cycle % 2 == 0) {
            withClue(s"FIFO underflow at cycle $cycle: ") { level should be > 0 }
            level -= 1
          }
          if (r) {
            if (scanoutOwner) level += 2
            readsLeft -= 1
            preferWrite = true
          }
          if (w) { writesLeft -= 1; preferWrite = false }
          if (b) bDelay = -1 else if (bDelay > 0) bDelay -= 1
          if (w && writesLeft == 0) bDelay = 2
          if (ar) {
            scanoutOwner = arScanout
            readsLeft = if (arScanout) 8 else 4
            if (arScanout) { scanoutReads += 1; scanoutRequested = false }
            else renderReads += 1
          }
          if (aw) {
            assetOwner = awAsset
            writesLeft = if (awAsset) 8 else 4
            if (awAsset) assetWrites += 1 else renderWrites += 1
          }
          level should be <= 96
        }
        Seq(renderReads, renderWrites, scanoutReads, assetWrites).foreach(_ should be > 0)
        emergencies should be > 0
        emergencyExits should be > 0
      }
    }

    it("counts simultaneous Scanout and Asset grants against the Render wait bound") {
      simulate(new DdrQosArbiter(maxRenderWait = 2)) { dut =>
        dut.io.scanoutLevel.poke(2048)
        dut.io.lowWatermark.poke(256)
        dut.io.highWatermark.poke(1536)
        dut.io.adaptiveEnable.poke(true)
        dut.io.render.ar.bits.poke(0.U.asTypeOf(new Axi4Address))
        dut.io.render.ar.bits.addr.poke(0x1000)
        dut.io.render.ar.valid.poke(true)
        dut.io.render.aw.valid.poke(false)
        dut.io.render.w.valid.poke(false)
        dut.io.render.r.ready.poke(true)
        dut.io.render.b.ready.poke(true)
        dut.io.scanout.ar.bits.poke(0.U.asTypeOf(new Axi4Address))
        dut.io.scanout.ar.bits.addr.poke(0x2000)
        dut.io.scanout.ar.valid.poke(false)
        dut.io.scanout.aw.valid.poke(false)
        dut.io.scanout.w.valid.poke(false)
        dut.io.scanout.r.ready.poke(true)
        dut.io.scanout.b.ready.poke(true)
        dut.io.asset.ar.valid.poke(false)
        dut.io.asset.aw.bits.poke(0.U.asTypeOf(new Axi4Address))
        dut.io.asset.aw.bits.addr.poke(0x4000)
        dut.io.asset.aw.valid.poke(false)
        dut.io.asset.w.bits.poke(0.U.asTypeOf(new Axi4WriteData))
        dut.io.asset.w.bits.last.poke(true)
        dut.io.asset.w.valid.poke(true)
        dut.io.asset.r.ready.poke(true)
        dut.io.asset.b.ready.poke(true)
        dut.io.axi.ar.ready.poke(true)
        dut.io.axi.aw.ready.poke(true)
        dut.io.axi.w.ready.poke(true)
        dut.io.axi.r.valid.poke(false)
        dut.io.axi.r.bits.poke(0.U.asTypeOf(new Axi4ReadData))
        dut.io.axi.r.bits.last.poke(true)
        dut.io.axi.b.valid.poke(false)
        dut.io.axi.b.bits.poke(0.U.asTypeOf(new Axi4WriteResponse))

        dut.clock.step()
        dut.io.axi.ar.bits.addr.expect(0x1000)
        dut.clock.step()
        dut.io.axi.r.valid.poke(true)
        dut.clock.step()
        dut.io.axi.r.valid.poke(false)

        dut.io.scanout.ar.valid.poke(true)
        dut.io.asset.aw.valid.poke(true)
        dut.clock.step()
        dut.io.axi.ar.bits.addr.expect(0x2000)
        dut.io.axi.aw.bits.addr.expect(0x4000)
        dut.clock.step()
        dut.io.scanout.ar.valid.poke(false)
        dut.clock.step()
        dut.io.axi.b.valid.poke(true)
        dut.clock.step()
        dut.io.axi.b.valid.poke(false)
        dut.clock.step()
        dut.io.axi.aw.valid.expect(false)
      }
    }
  }
}
