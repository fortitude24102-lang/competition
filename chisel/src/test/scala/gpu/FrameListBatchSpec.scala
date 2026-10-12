package gpu

import chisel3._
import org.scalatest.funspec.AnyFunSpec
import org.scalatest.matchers.should.Matchers
import testutil.StableChiselSim

/** Breaks: early done before delayed B, switched read ownership, double Alpha,
  * unlocked templates, leaked commands on late fetch failure, stale epoch. */
class FrameListBatchSpec extends AnyFunSpec with StableChiselSim with Matchers {
  it("executes whole DDR lists through the real Top and waits for pixel retirement") {
    simulate(new Efinix2dGpuTop(false,false,true)) { d =>
      d.io.apb.psel.poke(false);d.io.apb.penable.poke(false);d.io.apb.pwrite.poke(false)
      d.io.apb.paddr.poke(0);d.io.apb.pwdata.poke(0)
      d.io.vblank.poke(false);d.io.scanoutLevel.poke(2048);d.io.displayReady.poke(true)
      d.io.underflow_pulse_gpu.poke(false);d.io.assetStreamError.poke(false)
      d.io.assetMeta.valid.poke(false);d.io.assetMeta.bits.poke(0.U.asTypeOf(new AssetPacketMeta))
      d.io.assetPayload.valid.poke(false);d.io.assetPayload.bits.poke(0.U.asTypeOf(new AssetPayloadByte))
      d.io.axi.ar.ready.poke(false);d.io.axi.aw.ready.poke(false);d.io.axi.w.ready.poke(false)
      d.io.axi.r.valid.poke(false);d.io.axi.r.bits.poke(0.U.asTypeOf(new Axi4ReadData))
      d.io.axi.b.valid.poke(false);d.io.axi.b.bits.poke(0.U.asTypeOf(new Axi4WriteResponse))
      d.reset.poke(true);d.clock.step(2);d.reset.poke(false)
      val src=BigInt("02a00000",16);val dst=BigInt("02200000",16);val list=BigInt("02d20ff0",16)
      val memory=collection.mutable.Map[BigInt,BigInt](src->0x07e0,(src+4)->0xf81f,(src+8)->0xf800,dst->BigInt("55441111",16))
      var ra=BigInt(0);var rid=BigInt(0);var rn=0
      var wa=BigInt(0);var wid=BigInt(0);var wn=0;var bdelay=0
      var cycles=0;var writes=0;var fetchWords=0;var faultFetch=false
      def tick():Unit = {
        d.io.axi.ar.ready.poke(rn==0 && cycles%3!=0)
        d.io.axi.aw.ready.poke(wn==0 && bdelay==0 && cycles%5!=0)
        d.io.axi.w.ready.poke(wn>0 && cycles%4!=0)
        d.io.axi.r.valid.poke(rn>0 && cycles%5!=0)
        d.io.axi.r.bits.id.poke(rid);d.io.axi.r.bits.data.poke(memory.getOrElse(ra,BigInt(0)))
        d.io.axi.r.bits.last.poke(rn==1)
        d.io.axi.r.bits.resp.poke(if(faultFetch && rid==6 && fetchWords==11) 2 else 0)
        d.io.axi.b.valid.poke(bdelay==1);d.io.axi.b.bits.id.poke(wid);d.io.axi.b.bits.resp.poke(0)
        val ar=d.io.axi.ar.valid.peek().litToBoolean && d.io.axi.ar.ready.peek().litToBoolean
        val aw=d.io.axi.aw.valid.peek().litToBoolean && d.io.axi.aw.ready.peek().litToBoolean
        val r=d.io.axi.r.valid.peek().litToBoolean && d.io.axi.r.ready.peek().litToBoolean
        val w=d.io.axi.w.valid.peek().litToBoolean && d.io.axi.w.ready.peek().litToBoolean
        val b=d.io.axi.b.valid.peek().litToBoolean && d.io.axi.b.ready.peek().litToBoolean
        val nextRa=d.io.axi.ar.bits.addr.peek().litValue;val nextRn=d.io.axi.ar.bits.len.peek().litValue.toInt+1
        val nextRid=d.io.axi.ar.bits.id.peek().litValue
        val nextWa=d.io.axi.aw.bits.addr.peek().litValue;val nextWn=d.io.axi.aw.bits.len.peek().litValue.toInt+1
        val nextWid=d.io.axi.aw.bits.id.peek().litValue
        if(w) {
          d.io.axi.w.bits.last.expect(wn==1)
          val strb=d.io.axi.w.bits.strb.peek().litValue.toInt
          val data=d.io.axi.w.bits.data.peek().litValue
          var value=memory.getOrElse(wa,BigInt(0))
          for(i<-0 until 4 if (strb&(1<<i))!=0) value=(value & ~(BigInt(255)<<(8*i))) | (data & (BigInt(255)<<(8*i)))
          memory(wa)=value;if(strb!=0) writes+=1
        }
        d.clock.step();cycles+=1
        if(bdelay>1) bdelay-=1
        if(b) bdelay=0
        if(r) {if(rid==6)fetchWords+=1;ra+=4;rn-=1}
        if(w) {wa+=4;wn-=1;if(wn==0)bdelay=12}
        if(ar) {rn shouldBe 0;ra=nextRa;rn=nextRn;rid=nextRid}
        if(aw) {wn shouldBe 0;wa=nextWa;wn=nextWn;wid=nextWid}
      }
      def access(a:Int,v:BigInt=0,wr:Boolean=true,bad:Boolean=false):BigInt = {
        d.io.apb.paddr.poke(a);d.io.apb.pwdata.poke(v);d.io.apb.pwrite.poke(wr)
        d.io.apb.psel.poke(true);d.io.apb.penable.poke(false);tick();d.io.apb.penable.poke(true)
        var wait=0;while(!d.io.apb.pready.peek().litToBoolean && wait<5){tick();wait+=1}
        d.io.apb.pready.expect(true);d.io.apb.pslverror.expect(bad)
        val result=d.io.apb.prdata.peek().litValue
        if(a==0x504 && !wr && bdelay>0) (result&2) shouldBe BigInt(0)
        tick();d.io.apb.psel.poke(false);d.io.apb.penable.poke(false);result
      }
      def fillList(badHeader:Boolean=false):Unit = {
        for(i<-0 until 3) {
          val header=if(i==2) BigInt("00800102",16) else if(i==1 && badHeader) BigInt(0x10000001) else BigInt(i)
          Seq(header,dst,BigInt(0),BigInt(0x00010001)).zipWithIndex.foreach{case(v,j)=>memory(list+i*16+j*4)=v}
        }
      }
      def start(epoch:Int,address:BigInt=list,count:Int=3):Unit = {
        access(0x50c,address);access(0x510,count);access(0x514,65535);access(0x518,epoch);access(0x508,1)
      }
      def finish():BigInt = {
        var status=BigInt(0);var tries=0
        while((status&2)==0 && tries<1000){status=access(0x504,wr=false);tries+=1}
        withClue(s"status=$status fetch=$fetchWords writes=$writes:"){(status&2) shouldBe BigInt(2);(status&1) shouldBe BigInt(0)}
        status
      }
      (access(GpuRegisterMap.Status,wr=false)&(1<<15)) shouldBe BigInt(1<<15)
      access(0x500,wr=false) shouldBe BigInt("464c5431",16)
      for((op,i)<-Seq(2,3,4).zipWithIndex) {
        access(0x40c,i);Seq[BigInt](op,src+i*4,2,2,1,1,0xf81f).zipWithIndex.foreach{case(v,f)=>access(0x410+f*4,v)}
      }
      fillList();start(7)
      access(0x518,99,bad=true) // Cannot mutate accepted epoch.
      access(GpuRegisterMap.Control,1,bad=true) // Legacy submit is locked.
      finish() shouldBe BigInt(2)
      fetchWords shouldBe 12;writes shouldBe 2;memory(dst) shouldBe BigInt("554483e0",16)
      access(0x51c,wr=false) shouldBe 7;access(0x520,wr=false) shouldBe 1
      access(0x524,wr=false) shouldBe 3;access(GpuRegisterMap.LastDone,wr=false) shouldBe 1
      access(0x528,wr=false) shouldBe 48
      // A late transport error outputs NO command, even though eleven words succeeded.
      val oldWrites=writes;faultFetch=true;fetchWords=0;start(8)
      ((finish()>>8)&255) shouldBe GpuError.AxiResponse;writes shouldBe oldWrites
      access(0x524,wr=false) shouldBe 0;access(0x51c,wr=false) shouldBe 8
      faultFetch=false;fetchWords=0;fillList(badHeader=true);start(9)
      ((finish()>>8)&255) shouldBe GpuError.AddressRange
      writes shouldBe oldWrites+1;access(0x524,wr=false) shouldBe 1 // Copy prefix only, no Alpha replay.
      access(0x408,4);fetchWords=0;start(10,BigInt("02d23ff0",16),2)
      ((finish()>>8)&255) shouldBe GpuError.AddressRange;fetchWords shouldBe 0
      access(0x508,4);access(0x504,wr=false) shouldBe 0
    }
  }
}
