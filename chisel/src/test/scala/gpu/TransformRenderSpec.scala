package gpu

import chisel3._
import org.scalatest.funspec.AnyFunSpec
import org.scalatest.matchers.should.Matchers
import testutil.StableChiselSim

class TransformRenderSpec extends AnyFunSpec with StableChiselSim with Matchers {
  describe("optional transform at the queued renderer boundary") {
    it("orders transformed pixels, legacy Fill and PRESENT despite delayed B and completion stalls") {
      simulate(new RenderEngine(enableTransformBlit=true)) { d =>
        d.io.command.valid.poke(false);d.io.command.bits.poke(0.U.asTypeOf(new GpuCommand))
        d.io.vblank.poke(false);d.io.perfClear.poke(false);d.io.underflowPulse.poke(false)
        d.io.renderGrant.poke(0);d.io.scanoutGrant.poke(0)
        d.io.textureCacheLoad.valid.poke(false);d.io.textureCacheLoad.bits.poke(0.U.asTypeOf(new TextureCacheLoad))
        d.io.textureCacheInvalidate.poke(false);d.io.completion.ready.poke(false)
        d.io.axi.aw.ready.poke(false);d.io.axi.w.ready.poke(false);d.io.axi.ar.ready.poke(false)
        d.io.axi.b.valid.poke(false);d.io.axi.b.bits.poke(0.U.asTypeOf(new Axi4WriteResponse))
        d.io.axi.r.valid.poke(false);d.io.axi.r.bits.poke(0.U.asTypeOf(new Axi4ReadData))
        d.reset.poke(true);d.clock.step(2);d.reset.poke(false)
        val source=0x02400002L;val target=0x02001002L
        val memory=collection.mutable.Map.empty[Long,Int].withDefaultValue(0xa5)
        Seq(0x1111,0x2222,0x3333,0x4444).zipWithIndex.foreach { case(p,i) =>
          memory(source+i*2)=p&255;memory(source+i*2+1)=p>>8
        }
        var cycle=0;var ar=0L;var readId=0;var readLeft=0
        var aw=0L;var writeLeft=0;var bDelay = -1
        var writes=0;var completed=Vector.empty[Int];var queued=0
        while(cycle<4000 && completed.length<3) {
          d.io.command.valid.poke(queued<3)
          d.io.command.bits.poke(0.U.asTypeOf(new GpuCommand))
          d.io.command.bits.tag.poke(queued+1)
          if(queued==0) {
            d.io.command.bits.op.poke(7);d.io.command.bits.srcAddr.poke(source)
            d.io.command.bits.dstAddr.poke(target);d.io.command.bits.widthPixels.poke(4)
            d.io.command.bits.heightPixels.poke(4);d.io.command.bits.srcStride.poke(4)
            d.io.command.bits.dstStride.poke(10);d.io.command.bits.flags.poke(3)
            d.io.command.bits.srcWidthPixels.poke(2);d.io.command.bits.srcHeightPixels.poke(2)
          } else if(queued==1) {
            d.io.command.bits.op.poke(GpuOpcode.Fill);d.io.command.bits.dstAddr.poke(target+0x100)
            d.io.command.bits.widthPixels.poke(1);d.io.command.bits.heightPixels.poke(1)
            d.io.command.bits.dstStride.poke(2);d.io.command.bits.color.poke(0x9876)
          } else {
            d.io.command.bits.op.poke(GpuOpcode.Present);d.io.command.bits.dstAddr.poke(GpuMemoryMap.FramebufferB)
            d.io.command.bits.widthPixels.poke(1);d.io.command.bits.heightPixels.poke(1)
            d.io.command.bits.dstStride.poke(2)
          }
          if(cycle<=1800)d.io.frontBase.expect(GpuMemoryMap.FramebufferA)
          d.io.vblank.poke(cycle>1800)
          d.io.completion.ready.poke(cycle%7!=0)
          d.io.axi.ar.ready.poke(readLeft==0 && cycle%3!=0)
          d.io.axi.aw.ready.poke(writeLeft==0 && bDelay<0 && cycle%4!=0)
          d.io.axi.w.ready.poke(writeLeft>0 && cycle%5!=0)
          d.io.axi.r.valid.poke(readLeft>0)
          d.io.axi.r.bits.id.poke(readId);d.io.axi.r.bits.resp.poke(0)
          d.io.axi.r.bits.last.poke(readLeft==1)
          d.io.axi.r.bits.data.poke((0 until 4).map(i=>BigInt(memory(ar+i))<<(i*8)).reduce(_|_))
          d.io.axi.b.valid.poke(bDelay==0);d.io.axi.b.bits.id.poke(0);d.io.axi.b.bits.resp.poke(0)
          def fire(valid:Bool,ready:Bool)=valid.peek().litToBoolean&&ready.peek().litToBoolean
          val c=fire(d.io.command.valid,d.io.command.ready)
          val r=fire(d.io.axi.r.valid,d.io.axi.r.ready)
          val a=fire(d.io.axi.ar.valid,d.io.axi.ar.ready)
          val w=fire(d.io.axi.w.valid,d.io.axi.w.ready)
          val wa=fire(d.io.axi.aw.valid,d.io.axi.aw.ready)
          val b=fire(d.io.axi.b.valid,d.io.axi.b.ready)
          if(fire(d.io.completion.valid,d.io.completion.ready)) {
            d.io.completion.bits.error.expect(0)
            completed :+= d.io.completion.bits.tag.peek().litValue.toInt
            writeLeft shouldBe 0;bDelay shouldBe -1
          }
          if(w) {
            val value=d.io.axi.w.bits.data.peek().litValue
            val strb=d.io.axi.w.bits.strb.peek().litValue.toInt
            for(i<-0 until 4 if (strb&(1<<i))!=0) memory(aw+i)=((value>>(i*8))&255).toInt
            d.io.axi.w.bits.last.expect(writeLeft==1)
          }
          val nextRead=if(a)Some((d.io.axi.ar.bits.addr.peek().litValue.toLong,
            d.io.axi.ar.bits.len.peek().litValue.toInt+1,d.io.axi.ar.bits.id.peek().litValue.toInt))else None
          val nextWrite=if(wa)Some((d.io.axi.aw.bits.addr.peek().litValue.toLong,
            d.io.axi.aw.bits.len.peek().litValue.toInt+1))else None
          d.clock.step();cycle+=1
          if(c)queued+=1
          if(r){ar+=4;readLeft-=1}
          nextRead.foreach{case(address,n,id)=>ar=address;readLeft=n;readId=id}
          if(b)bDelay = -1 else if(bDelay>0)bDelay-=1
          if(w){aw+=4;writeLeft-=1;writes+=1;if(writeLeft==0)bDelay=6}
          nextWrite.foreach{case(address,n)=>aw=address;writeLeft=n}
        }
        completed shouldBe Vector(1,2,3);writes should be > 0
        val wanted=Seq(0x4444,0x4444,0x3333,0x3333,0x4444,0x4444,0x3333,0x3333,
          0x2222,0x2222,0x1111,0x1111,0x2222,0x2222,0x1111,0x1111)
        for(y<-0 until 4;x<-0 until 4) {
          val address=target+y*10+x*2
          (memory(address)|(memory(address+1)<<8)) shouldBe wanted(y*4+x)
        }
        memory(target-1) shouldBe 0xa5
        memory(target+8) shouldBe 0xa5
        (memory(target+0x100)|(memory(target+0x101)<<8)) shouldBe 0x9876
        d.io.perfPixels.expect(17);d.io.frontBase.expect(GpuMemoryMap.FramebufferB)
      }
    }
  }
}
