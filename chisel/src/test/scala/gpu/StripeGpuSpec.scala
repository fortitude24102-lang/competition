package gpu

import chisel3._
import org.scalatest.funspec.AnyFunSpec
import org.scalatest.matchers.should.Matchers
import testutil.StableChiselSim

class StripeGpuSpec extends AnyFunSpec with StableChiselSim with Matchers {
  it("composes Fill/cached Key/Alpha locally then copies exact pixels through the list-enabled top") {
    simulate(new Efinix2dGpuTop(enableFrameLists = true, enableKeyPrefetch = true,
      enableStripeScratchpad = true)) { d =>
      val base=0x02e00000L; val atlas=0x02400000L; val dst=0x02000100L
      val mem=collection.mutable.Map.empty[Long,Int].withDefaultValue(0xa5)
      val fg=(0 until 16).map(i => if(i%3==0) 0xbeef else (i*0x123+1)&65535)
      for(i<-fg.indices) {mem(atlas+i*2)=fg(i)&255;mem(atlas+i*2+1)=fg(i)>>8}
      d.io.apb.psel.poke(false);d.io.apb.penable.poke(false);d.io.apb.paddr.poke(0)
      d.io.apb.pwrite.poke(false);d.io.apb.pwdata.poke(0)
      d.io.vblank.poke(false);d.io.scanoutLevel.poke(2048);d.io.underflow_pulse_gpu.poke(false)
      d.io.displayReady.poke(true);d.io.assetMeta.valid.poke(false);d.io.assetPayload.valid.poke(false)
      d.io.assetMeta.bits.poke(0.U.asTypeOf(new AssetPacketMeta))
      d.io.assetPayload.bits.poke(0.U.asTypeOf(new AssetPayloadByte));d.io.assetStreamError.poke(false)
      d.io.axi.aw.ready.poke(false);d.io.axi.w.ready.poke(false);d.io.axi.ar.ready.poke(false)
      d.io.axi.b.valid.poke(false);d.io.axi.b.bits.poke(0.U.asTypeOf(new Axi4WriteResponse))
      d.io.axi.r.valid.poke(false);d.io.axi.r.bits.poke(0.U.asTypeOf(new Axi4ReadData))
      d.reset.poke(true);d.clock.step(2);d.reset.poke(false)
      var ra=0L;var rn=0;var rid=0;var wa=0L;var wn=0;var b=false;var cycle=0
      def tick(): Unit = {
        d.io.axi.aw.ready.poke(wn==0 && !b && cycle%3!=0);d.io.axi.w.ready.poke(wn>0 && cycle%4!=0)
        d.io.axi.ar.ready.poke(rn==0);d.io.axi.r.valid.poke(rn>0)
        d.io.axi.r.bits.id.poke(rid);d.io.axi.r.bits.last.poke(rn==1)
        d.io.axi.r.bits.data.poke((0 until 4).map(i=>mem(ra+i).toLong<<(i*8)).reduce(_|_))
        d.io.axi.b.valid.poke(b)
        val ar=d.io.axi.ar.valid.peek().litToBoolean && rn==0
        val aw=d.io.axi.aw.valid.peek().litToBoolean && d.io.axi.aw.ready.peek().litToBoolean
        val r=rn>0 && d.io.axi.r.ready.peek().litToBoolean
        val w=d.io.axi.w.valid.peek().litToBoolean && d.io.axi.w.ready.peek().litToBoolean
        val br=b && d.io.axi.b.ready.peek().litToBoolean
        if(ar) {ra=d.io.axi.ar.bits.addr.peek().litValue.longValue;rn=d.io.axi.ar.bits.len.peek().litValue.toInt+1;rid=d.io.axi.ar.bits.id.peek().litValue.toInt; assert((ra>>16)!=0x02e0)}
        if(aw) {wa=d.io.axi.aw.bits.addr.peek().litValue.longValue;wn=d.io.axi.aw.bits.len.peek().litValue.toInt+1; assert((wa>>16)!=0x02e0)}
        if(w) {
          val data=d.io.axi.w.bits.data.peek().litValue;val mask=d.io.axi.w.bits.strb.peek().litValue
          d.io.axi.w.bits.last.expect(wn==1)
          for(i<-0 until 4 if mask.testBit(i))mem(wa+i)=((data>>(i*8))&255).toInt
        }
        d.clock.step();cycle+=1
        if(r) {ra+=4;rn-=1};if(w) {wa+=4;wn-=1;if(wn==0)b=true};if(br)b=false
      }
      def apb(a:Int,v:Long=0,write:Boolean=false):BigInt = {
        d.io.apb.paddr.poke(a);d.io.apb.pwdata.poke(v);d.io.apb.pwrite.poke(write)
        d.io.apb.psel.poke(true);d.io.apb.penable.poke(false);tick();d.io.apb.penable.poke(true)
        var n=0;while(!d.io.apb.pready.peek().litToBoolean && n<20) {tick();n+=1}
        d.io.apb.pready.expect(true);d.io.apb.pslverror.expect(false)
        val result=d.io.apb.prdata.peek().litValue;tick();d.io.apb.psel.poke(false);d.io.apb.penable.poke(false);result
      }
      def waitTag(tag:Int):Unit = {
        var n=0;while(apb(GpuRegisterMap.LastDone)!=tag && n<1500)n+=1
        assert(n<1500);apb(GpuRegisterMap.Error) shouldBe BigInt(0)
      }
      def command(op:Int,src:Long,to:Long,w:Int,h:Int,ss:Int,ds:Int,tag:Int):Unit = {
        for((a,v)<-Seq(GpuRegisterMap.Op->op.toLong,GpuRegisterMap.SrcAddr->src,GpuRegisterMap.DstAddr->to,
          GpuRegisterMap.Size->(w.toLong|(h.toLong<<16)),GpuRegisterMap.SrcStride->ss.toLong,
          GpuRegisterMap.DstStride->ds.toLong,GpuRegisterMap.ColorKey->0xbeef07e0L,
          GpuRegisterMap.AlphaFlags->128L,GpuRegisterMap.Tag->tag.toLong,GpuRegisterMap.Control->1L))apb(a,v,true)
        waitTag(tag)
      }
      (apb(GpuRegisterMap.Status)&0x1c000) shouldBe BigInt(0x1c000)
      command(GpuOpcode.Fill,0,base,8,4,0,1920,1)
      apb(GpuRegisterMap.TextureCacheBase,atlas,true);apb(GpuRegisterMap.TextureCacheBytes,32,true)
      apb(GpuRegisterMap.TextureCacheControl,1,true)
      var polls=0;while((apb(GpuRegisterMap.TextureCacheStatus)&2)!=0 && polls<1000)polls+=1
      (apb(GpuRegisterMap.TextureCacheStatus)&1) shouldBe BigInt(1)
      command(GpuOpcode.ColorKey,atlas,base+1920+2,4,2,8,1920,2)
      command(GpuOpcode.Alpha,atlas+16,base+1920+4,3,2,8,1920,3)
      command(GpuOpcode.Copy,base,dst,8,4,1920,1920,4)
      def blend(f:Int,b:Int):Int = {
        Seq((11,31),(5,63),(0,31)).map {case(sh,m)=>((((f>>sh)&m)*128+((b>>sh)&m)*127+127)/255)<<sh}.reduce(_|_)
      }
      for(y<-0 until 4;x<-0 until 8) {
        var expected=0x07e0
        if(y>=1 && y<3 && x>=1 && x<5) {val f=fg((y-1)*4+x-1);if(f!=0xbeef)expected=f}
        if(y>=1 && y<3 && x>=2 && x<5)expected=blend(fg(8+(y-1)*4+x-2),expected)
        val a=dst+y*1920+x*2;(mem(a)|(mem(a+1)<<8)) shouldBe expected
      }
      mem(dst-1) shouldBe 0xa5;mem(dst+16) shouldBe 0xa5
    }
  }
}
