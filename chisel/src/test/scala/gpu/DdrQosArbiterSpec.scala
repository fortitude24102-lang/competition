package gpu

import chisel3._
import org.scalatest.funspec.AnyFunSpec
import org.scalatest.matchers.should.Matchers
import testutil.StableChiselSim

class DdrQosArbiterSpec extends AnyFunSpec with StableChiselSim with Matchers {
  describe("DdrQosArbiter") {
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
        pokeClientAddress(dut.io.scanout.aw.bits, 0x4000)
        dut.io.render.ar.valid.poke(true)
        dut.io.scanout.ar.valid.poke(true)
        dut.io.render.aw.valid.poke(true)
        dut.io.scanout.aw.valid.poke(true)
        dut.io.render.w.valid.poke(true)
        dut.io.render.w.bits.data.poke(0x11112222L)
        dut.io.render.w.bits.strb.poke(0xf)
        dut.io.render.w.bits.last.poke(false)
        dut.io.scanout.w.valid.poke(true)
        dut.io.scanout.w.bits.data.poke(0x33334444L)
        dut.io.scanout.w.bits.strb.poke(0xf)
        dut.io.scanout.w.bits.last.poke(true)
        dut.io.render.r.ready.poke(true)
        dut.io.scanout.r.ready.poke(true)
        dut.io.render.b.ready.poke(true)
        dut.io.scanout.b.ready.poke(true)
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
        dut.io.axi.r.ready.expect(false)
        dut.io.axi.w.valid.expect(true)
        dut.io.axi.w.bits.data.expect(0x11112222L)
        dut.io.render.w.ready.expect(false)
        dut.clock.step()

        dut.io.render.r.ready.poke(true)
        dut.io.axi.w.ready.poke(true)
        dut.clock.step()

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
        dut.io.scanout.b.valid.expect(false)
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
        dut.io.scanout.aw.valid.poke(false)
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

    it("uses low/high hysteresis and still grants a waiting renderer at low scanout level") {
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
        dut.io.render.w.valid.poke(false)
        dut.io.scanout.w.valid.poke(false)
        dut.io.render.r.ready.poke(true)
        dut.io.scanout.r.ready.poke(true)
        dut.io.render.b.ready.poke(true)
        dut.io.scanout.b.ready.poke(true)
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
        var grants = Seq.empty[Long]
        var responsePending = false
        for (_ <- 0 until 40 if !grants.contains(0x1000L)) {
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
        grants.take(3) shouldBe Seq.fill(3)(0x2000L)
        grants(3) shouldBe 0x1000L
      }
    }
  }
}
