package gpu

import chisel3._
import org.scalatest.funspec.AnyFunSpec
import org.scalatest.matchers.should.Matchers
import testutil.StableChiselSim

/** Catches widened default windows, a larger per-batch limit, partial prefetch
  * leakage, wrong fourth-bank addresses and a mismatched advertised capability. */
class FrameListArenaSpec extends AnyFunSpec with StableChiselSim with Matchers {
  for(extended <- Seq(false,true)) {
    it(s"preserves 1024-item whole-bank transport and bounds with extended=$extended") {
      simulate(new FrameListReader(extendedArena=extended)) { d =>
        d.io.request.valid.poke(false);d.io.request.bits.address.poke(0);d.io.request.bits.count.poke(0)
        d.io.axiAr.ready.poke(false);d.io.axiR.valid.poke(false)
        d.io.axiR.bits.poke(0.U.asTypeOf(new Axi4ReadData));d.io.descriptor.ready.poke(false)
        def run(address:Long,count:Int,legal:Boolean):Unit={
          d.io.request.ready.expect(true);d.io.request.bits.address.poke(address)
          d.io.request.bits.count.poke(count);d.io.request.valid.poke(true)
          d.clock.step();d.io.request.valid.poke(false)
          var left=0;var fed=0;var received=0;var cycles=0;var bursts=0
          while(!d.io.done.peek().litToBoolean && cycles<25000) {
            d.io.axiAr.ready.poke(left==0 && cycles%3!=0)
            d.io.axiR.valid.poke(left>0 && cycles%5!=0)
            d.io.axiR.bits.id.poke(6);d.io.axiR.bits.resp.poke(0)
            d.io.axiR.bits.last.poke(left==1);d.io.axiR.bits.data.poke(fed+1)
            d.io.descriptor.ready.poke(cycles%4!=1)
            val ar=d.io.axiAr.valid.peek().litToBoolean && d.io.axiAr.ready.peek().litToBoolean
            val r=d.io.axiR.valid.peek().litToBoolean && d.io.axiR.ready.peek().litToBoolean
            val beats=d.io.axiAr.bits.len.peek().litValue.toInt+1
            if(!legal){d.io.axiAr.valid.expect(false);d.io.descriptor.valid.expect(false)}
            if(d.io.fetching.peek().litToBoolean)d.io.descriptor.valid.expect(false)
            if(ar) {
              d.io.axiAr.bits.addr.expect(address+fed*4);d.io.axiAr.bits.id.expect(6)
              assert(((address+fed*4)&4095)+beats*4<=4096);bursts+=1
            }
            if(d.io.descriptor.valid.peek().litToBoolean && d.io.descriptor.ready.peek().litToBoolean) {
              assert(fed==count*4)
              for(l<-0 until 4)d.io.descriptor.bits(l).expect(received*4+l+1)
              received+=1
            }
            d.clock.step();if(r){fed+=1;left-=1};if(ar)left=beats;cycles+=1
          }
          assert(cycles<25000);d.io.done.expect(true)
          d.io.error.expect(if(legal)GpuError.None else GpuError.AddressRange)
          assert(received==(if(legal)count else 0));assert(fed==(if(legal)count*4 else 0))
          if(legal && count==1024)assert(bursts==16)
          d.io.axiR.valid.poke(false);d.io.axiAr.ready.poke(false);d.clock.step()
        }
        run(0x02d27ff0L,1,true)
        run(0x02d28000L,1024,extended)
        run(0x02d2c000L,1024,extended)
        run(0x02d2fff0L,1,extended)
        for((a,n)<-Seq((0x02d2bff0L,2),(0x02d30000L,1),(0x02d28000L,1025),
          (0x02d28001L,1),(0xfffffff0L,1)))run(a,n,false)
      }
    }
  }

  it("advertises the extended arena only on the real opt-in Top") {
    for(extended<-Seq(false,true))simulate(new Efinix2dGpuTop(enableInstances=true,
      enableFrameLists=true,enableExtendedListArena=extended)) { d=>
      d.io.apb.psel.poke(false);d.io.apb.penable.poke(false);d.io.apb.pwrite.poke(false)
      d.io.apb.paddr.poke(0);d.io.apb.pwdata.poke(0)
      d.io.vblank.poke(false);d.io.scanoutLevel.poke(2048);d.io.underflow_pulse_gpu.poke(false)
      d.io.displayReady.poke(true);d.io.assetMeta.valid.poke(false);d.io.assetPayload.valid.poke(false)
      d.io.assetMeta.bits.poke(0.U.asTypeOf(new AssetPacketMeta))
      d.io.assetPayload.bits.poke(0.U.asTypeOf(new AssetPayloadByte));d.io.assetStreamError.poke(false)
      d.io.axi.aw.ready.poke(true);d.io.axi.w.ready.poke(true);d.io.axi.ar.ready.poke(true)
      d.io.axi.r.valid.poke(false);d.io.axi.r.bits.poke(0.U.asTypeOf(new Axi4ReadData))
      d.io.axi.b.valid.poke(false);d.io.axi.b.bits.poke(0.U.asTypeOf(new Axi4WriteResponse))
      d.io.apb.paddr.poke(8);d.io.apb.psel.poke(true);d.clock.step()
      d.io.apb.penable.poke(true);var wait=0
      while(!d.io.apb.pready.peek().litToBoolean && wait<10){d.clock.step();wait+=1}
      d.io.apb.pready.expect(true);d.io.apb.pslverror.expect(false)
      val status=d.io.apb.prdata.peek().litValue
      ((status>>20)&1) shouldBe (if(extended)BigInt(1) else BigInt(0))
      ((status>>15)&1) shouldBe BigInt(1)
    }
  }
}
