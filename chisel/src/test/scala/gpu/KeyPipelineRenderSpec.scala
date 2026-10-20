package gpu

import chisel3._
import org.scalatest.funspec.AnyFunSpec
import org.scalatest.matchers.should.Matchers
import scala.collection.mutable
import testutil.StableChiselSim

class KeyPipelineRenderSpec extends AnyFunSpec with StableChiselSim with Matchers {
  for(bError <- Seq(false,true)) {
  it(s"uses the Key-only writer across 4KiB and drains B before queued Fill and Alpha B-error=$bError") {
    simulate(new RenderEngine(enableKeyPrefetch=true,enableKeyWritePipeline=true)) { d =>
      val src=GpuMemoryMap.DenseAssets.longValue; val dst=0x02000ffeL
      val pixels=Vector(0xf81f,0x1234,0x5678,0xf81f,0xffff,0x9abc,0xf81f,0,
        0x101,0x202,0x303,0x404,0xf81f,0xf81f,0x707,0x808,
        0xf81f,0xf81f,0x1111,0x2222,0x3333,0x4444,0x5555,0x6666)
      val mem=mutable.Map.empty[Long,Int].withDefaultValue(0x5a)
      for(i<-pixels.indices; lane<-0 until 2)mem(src+i*2+lane)=(pixels(i)>>(lane*8))&255
      val writes=mutable.Queue.empty[(Long,Int)]
      val replies=mutable.Queue.empty[Int]
      val addresses=mutable.ArrayBuffer.empty[(Long,Int)]
      val completions=mutable.ArrayBuffer.empty[Int]
      var rAddress=0L; var rLeft=0; var rId=0; var wOffset=0
      var submitted=0; var bCount=0; var overlap=false; var cycles=0
      val keyBursts=if(bError)2 else 4
      d.io.command.valid.poke(false); d.io.command.bits.poke(0.U.asTypeOf(new GpuCommand))
      d.io.completion.ready.poke(true); d.io.vblank.poke(false); d.io.perfClear.poke(false)
      d.io.underflowPulse.poke(false); d.io.renderGrant.poke(0); d.io.scanoutGrant.poke(0)
      d.io.textureCacheInvalidate.poke(false); d.io.textureCacheLoad.valid.poke(true)
      d.io.textureCacheLoad.bits.base.poke(src); d.io.textureCacheLoad.bits.bytes.poke(48)
      d.io.axi.ar.ready.poke(false); d.io.axi.aw.ready.poke(false); d.io.axi.w.ready.poke(false)
      d.io.axi.r.valid.poke(false); d.io.axi.r.bits.poke(0.U.asTypeOf(new Axi4ReadData))
      d.io.axi.b.valid.poke(false); d.io.axi.b.bits.poke(0.U.asTypeOf(new Axi4WriteResponse))
      d.clock.step(); d.io.textureCacheLoad.valid.poke(false)
      while(completions.size<3 && cycles<3000) {
        val offer=submitted<3 && d.io.textureCacheValid.peek().litToBoolean
        d.io.command.valid.poke(offer); d.io.command.bits.poke(0.U.asTypeOf(new GpuCommand))
        d.io.command.bits.op.poke(if(submitted==0)GpuOpcode.ColorKey else if(submitted==1)GpuOpcode.Fill else GpuOpcode.Alpha)
        d.io.command.bits.srcAddr.poke(if(submitted==0)src else if(submitted==2)src+2 else 0L)
        d.io.command.bits.dstAddr.poke(if(submitted==0)dst else if(submitted==1)0x02010000L else 0x02011000L)
        d.io.command.bits.widthPixels.poke(if(submitted==0)8 else 1)
        d.io.command.bits.heightPixels.poke(if(submitted==0)3 else 1)
        d.io.command.bits.srcStride.poke(if(submitted==0)16 else 2)
        d.io.command.bits.dstStride.poke(if(submitted==0)1920 else 2)
        d.io.command.bits.colorKey.poke(0xf81f); d.io.command.bits.color.poke(0xf800)
        d.io.command.bits.alpha.poke(255); d.io.command.bits.tag.poke(10+submitted)
        d.io.axi.ar.ready.poke(rLeft==0)
        d.io.axi.r.valid.poke(rLeft>0 && cycles%3!=1)
        d.io.axi.r.bits.id.poke(rId); d.io.axi.r.bits.resp.poke(0); d.io.axi.r.bits.last.poke(rLeft==1)
        d.io.axi.r.bits.data.poke((0 until 4).foldLeft(BigInt(0))((v,l)=>v|(BigInt(mem(rAddress+l))<<(8*l))))
        d.io.axi.aw.ready.poke(cycles%7!=3); d.io.axi.w.ready.poke(cycles%5!=1)
        val bValid=replies.headOption.exists(_<=cycles)
        d.io.axi.b.valid.poke(bValid); d.io.axi.b.bits.id.poke(0)
        d.io.axi.b.bits.resp.poke(if(bError && bCount==0)2 else 0)
        def fire(v:Bool,r:Bool):Boolean=v.peek().litToBoolean && r.peek().litToBoolean
        val cFire=fire(d.io.command.valid,d.io.command.ready)
        val rFire=fire(d.io.axi.r.valid,d.io.axi.r.ready)
        if(fire(d.io.axi.ar.valid,d.io.axi.ar.ready)) {
          rAddress=d.io.axi.ar.bits.addr.peek().litValue.longValue
          rLeft=d.io.axi.ar.bits.len.peek().litValue.toInt+1; rId=d.io.axi.ar.bits.id.peek().litValue.toInt
        }
        if(fire(d.io.axi.aw.valid,d.io.axi.aw.ready)) {
          val a=d.io.axi.aw.bits.addr.peek().litValue.longValue
          val n=d.io.axi.aw.bits.len.peek().litValue.toInt+1
          if(a==0x0200177cL && bCount<2)overlap=true
          if(a==0x02010000L || a==0x02011000L)assert(bCount>=keyBursts,"next command started before Key B retired")
          addresses+=((a,n)); writes.enqueue((a,n))
        }
        if(fire(d.io.axi.w.valid,d.io.axi.w.ready)) {
          assert(writes.nonEmpty); val (a,n)=writes.head
          val word=d.io.axi.w.bits.data.peek().litValue; val strobe=d.io.axi.w.bits.strb.peek().litValue.toInt
          for(l<-0 until 4 if (strobe&(1<<l))!=0)mem(a+wOffset*4+l)=((word>>(8*l))&255).toInt
          d.io.axi.w.bits.last.expect(wOffset==n-1); wOffset+=1
          if(wOffset==n) {writes.dequeue();wOffset=0;replies.enqueue(cycles+80)}
        }
        if(bValid && d.io.axi.b.ready.peek().litToBoolean) {replies.dequeue();bCount+=1}
        if(d.io.completion.valid.peek().litToBoolean) {
          d.io.completion.bits.tag.expect(10+completions.size)
          d.io.completion.bits.error.expect(if(bError && completions.isEmpty)GpuError.AxiResponse else GpuError.None)
          assert(bCount==keyBursts+completions.size,"completion did not match final B")
          completions+=d.io.completion.bits.tag.peek().litValue.toInt
        }
        d.clock.step(); if(cFire)submitted+=1
        if(rFire) {rAddress+=4;rLeft-=1}
        cycles+=1
      }
      completions.toSeq shouldBe Seq(10,11,12); if(!bError)assert(overlap)
      addresses.take(keyBursts).toSeq shouldBe
        Seq((0x02000ffcL,1),(0x02001000L,4),(0x0200177cL,5),(0x02001efcL,5)).take(keyBursts)
      for(y<-0 until 3; byte<- -2 until 20) {
        val pixel=if(byte>=0 && byte<16)pixels(y*8+byte/2) else 0xf81f
        val want=if(pixel!=0xf81f && (!bError || y==0))(pixel>>((byte&1)*8))&255 else 0x5a
        mem(dst+y*1920+byte) shouldBe want
      }
      mem(0x02010000L) shouldBe 0; mem(0x02010001L) shouldBe 0xf8
      mem(0x02011000L) shouldBe 0x34; mem(0x02011001L) shouldBe 0x12
      d.io.perfPixels.expect(if(bError)10 else 26)
    }
  }
  }
}
