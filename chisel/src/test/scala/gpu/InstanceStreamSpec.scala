package gpu

import chisel3._
import org.scalatest.funspec.AnyFunSpec
import org.scalatest.matchers.should.Matchers
import testutil.StableChiselSim

/** Break caught: optional window isn't decoded, or shares legacy submission. */
class InstanceStreamSpec extends AnyFunSpec with StableChiselSim with Matchers {
  describe("compact instance integration") {
    it("executes Copy, transparent Key and Alpha in order, then returns the queue to legacy commands") {
      simulate(new Efinix2dGpuTop(false,true)) { d =>
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
        val base=BigInt("02a00000",16);val dst=BigInt("02200000",16)
        val memory=collection.mutable.Map[BigInt,Int](base->0x07e0,(base+4)->0xf81f,(base+8)->0xf800)
        var read:Option[BigInt]=None;var write:Option[BigInt]=None;var response=false
        var readId=BigInt(0)
        var writes=0;var cycles=0
        def tick():Unit = {
          // Real AXI request/response handshakes, with bounded address/data stalls.
          d.io.axi.ar.ready.poke(read.isEmpty && cycles%3!=0)
          d.io.axi.aw.ready.poke(write.isEmpty && !response && cycles%5!=0)
          d.io.axi.w.ready.poke(write.nonEmpty && cycles%4!=0)
          d.io.axi.r.valid.poke(read.nonEmpty)
          d.io.axi.r.bits.id.poke(readId)
          d.io.axi.r.bits.data.poke(memory.getOrElse(read.getOrElse(BigInt(0)),0))
          d.io.axi.r.bits.last.poke(true);d.io.axi.b.valid.poke(response)
          val ar=d.io.axi.ar.valid.peek().litToBoolean && d.io.axi.ar.ready.peek().litToBoolean
          val aw=d.io.axi.aw.valid.peek().litToBoolean && d.io.axi.aw.ready.peek().litToBoolean
          val r=read.nonEmpty && d.io.axi.r.ready.peek().litToBoolean
          val w=write.nonEmpty && d.io.axi.w.ready.peek().litToBoolean && d.io.axi.w.valid.peek().litToBoolean
          val b=response && d.io.axi.b.ready.peek().litToBoolean
          val ra=d.io.axi.ar.bits.addr.peek().litValue;val wa=d.io.axi.aw.bits.addr.peek().litValue
          val rid=d.io.axi.ar.bits.id.peek().litValue
          if(ar) d.io.axi.ar.bits.len.expect(0)
          if(aw) d.io.axi.aw.bits.len.expect(0)
          if(w) {
            d.io.axi.w.bits.last.expect(true)
            val strb=d.io.axi.w.bits.strb.peek().litValue.toInt
            Set(0,3) should contain(strb)
            if(strb==3) { // Transparent Key may issue a legal all-masked AXI beat.
              memory(write.get)=d.io.axi.w.bits.data.peek().litValue.toInt & 65535;writes+=1
            }
          }
          d.clock.step();cycles+=1
          if(r) read=None
          if(b) response=false
          if(w) {write=None;response=true}
          if(ar) {read=Some(ra);readId=rid}
          if(aw) write=Some(wa)
        }
        def access(a:Int,v:BigInt=0,wr:Boolean=true):BigInt = {
          d.io.apb.paddr.poke(a);d.io.apb.pwdata.poke(v);d.io.apb.pwrite.poke(wr)
          d.io.apb.psel.poke(true);d.io.apb.penable.poke(false);tick()
          d.io.apb.penable.poke(true);d.io.apb.pready.expect(false)
          var waits=0
          while(!d.io.apb.pready.peek().litToBoolean && waits<3) {tick();waits+=1}
          d.io.apb.pready.expect(true);d.io.apb.pslverror.expect(false)
          val result=d.io.apb.prdata.peek().litValue;tick()
          d.io.apb.psel.poke(false);d.io.apb.penable.poke(false);result
        }
        for((op,i)<-Seq(2,3,4).zipWithIndex) {
          access(0x40c,i)
          Seq[BigInt](op,base+i*4,2,2,1,1,0xf81f).zipWithIndex.foreach {case(v,f)=>access(0x410+f*4,v)}
        }
        access(0x444,65535);access(0x408,1)
        for(i<-0 until 3) {
          val header=if(i==2) BigInt("00800102",16) else BigInt(i)
          Seq(header,dst,BigInt(0),BigInt(0x00010001)).zipWithIndex.foreach {case(v,f)=>access(0x430+f*4,v)}
          access(0x440,1)
        }
        var idle=false
        for(_<-0 until 500 if !idle) idle=(access(0x404,wr=false)&4)!=0
        withClue(s"front=${access(0x404,wr=false)}, done=${access(GpuRegisterMap.LastDone,wr=false)}, error=${access(GpuRegisterMap.Error,wr=false)}, R=$read/$readId W=$write B=$response: ") {
          idle shouldBe true
        }
        access(GpuRegisterMap.LastDone,wr=false) shouldBe 1
        access(GpuRegisterMap.Error,wr=false) shouldBe 0
        writes shouldBe 2 // Key is fully transparent, never overwrites the copied background.
        memory(dst) shouldBe 0x83e0
        access(0x408,2)
        access(GpuRegisterMap.Op,1);access(GpuRegisterMap.DstAddr,dst)
        access(GpuRegisterMap.Size,0x00010001);access(GpuRegisterMap.DstStride,2)
        access(GpuRegisterMap.ColorKey,0x001f);access(GpuRegisterMap.Tag,2);access(GpuRegisterMap.Control,1)
        var done=false
        for(_<-0 until 500 if !done) done=access(GpuRegisterMap.LastDone,wr=false)==2
        done shouldBe true;memory(dst) shouldBe 0x001f;writes shouldBe 3
      }
    }
    it("exposes the frozen 0400 window without altering the legacy GPU identity") {
      simulate(new Efinix2dGpuTop(false,true)) { d =>
        d.io.apb.psel.poke(false); d.io.apb.penable.poke(false)
        d.io.apb.paddr.poke(0); d.io.apb.pwrite.poke(false); d.io.apb.pwdata.poke(0)
        d.io.vblank.poke(false); d.io.scanoutLevel.poke(2048)
        d.io.underflow_pulse_gpu.poke(false); d.io.displayReady.poke(true)
        d.io.assetMeta.valid.poke(false); d.io.assetMeta.bits.poke(0.U.asTypeOf(new AssetPacketMeta))
        d.io.assetPayload.valid.poke(false); d.io.assetPayload.bits.poke(0.U.asTypeOf(new AssetPayloadByte))
        d.io.assetStreamError.poke(false)
        d.io.axi.ar.ready.poke(false); d.io.axi.aw.ready.poke(false); d.io.axi.w.ready.poke(false)
        d.io.axi.r.valid.poke(false); d.io.axi.r.bits.poke(0.U.asTypeOf(new Axi4ReadData))
        d.io.axi.b.valid.poke(false); d.io.axi.b.bits.poke(0.U.asTypeOf(new Axi4WriteResponse))
        d.reset.poke(true); d.clock.step(2); d.reset.poke(false)
        def read(a: Int): (BigInt,Boolean) = {
          d.io.apb.paddr.poke(a); d.io.apb.psel.poke(true); d.io.apb.penable.poke(false)
          d.clock.step(); d.io.apb.penable.poke(true); d.io.apb.pready.expect(false)
          d.clock.step();d.io.apb.pready.expect(true)
          val v=(d.io.apb.prdata.peek().litValue,d.io.apb.pslverror.peek().litToBoolean)
          d.clock.step(); d.io.apb.psel.poke(false); d.io.apb.penable.poke(false); v
        }
        read(0)._1 shouldBe BigInt("32444750",16)
        (read(GpuRegisterMap.Status)._1 & (1 << 14)) shouldBe BigInt(1 << 14)
        read(0x400) shouldBe (BigInt("494e5331",16),false)
        def write(a: Int,v: BigInt): Boolean = {
          d.io.apb.paddr.poke(a);d.io.apb.pwrite.poke(true);d.io.apb.pwdata.poke(v)
          d.io.apb.psel.poke(true);d.io.apb.penable.poke(false);d.clock.step()
          d.io.apb.penable.poke(true);d.io.apb.pready.expect(false);d.clock.step();d.io.apb.pready.expect(true)
          val bad=d.io.apb.pslverror.peek().litToBoolean
          d.clock.step();d.io.apb.psel.poke(false);d.io.apb.penable.poke(false);d.io.apb.pwrite.poke(false);bad
        }
        write(0x408,1) shouldBe false
        write(GpuRegisterMap.Control,1) shouldBe true // Cannot interleave legacy producer.
        d.clock.step(5);d.io.axi.aw.valid.expect(false);d.io.axi.ar.valid.expect(false)
        write(0x408,2) shouldBe false
        // AssetDmaRegs has combinational access, unlike the pending GPU windows.
        // Its START must execute once while the upstream response waits.
        write(AssetDmaRegisterMap.Session,0x12345678) shouldBe false
        write(AssetDmaRegisterMap.DstAddr,BigInt("02a00000",16)) shouldBe false
        write(AssetDmaRegisterMap.MaxLength,1024) shouldBe false
        read(AssetDmaRegisterMap.Session) shouldBe (BigInt("12345678",16),false)
        write(AssetDmaRegisterMap.Control,1) shouldBe false
        read(AssetDmaRegisterMap.Status) shouldBe (BigInt(1),false)
        d.io.assetSession.expect(BigInt("12345678",16));d.io.assetActive.expect(true)
        write(AssetDmaRegisterMap.Status,0) shouldBe true
        read(0x400) shouldBe (BigInt("494e5331",16),false)
        // A reset cancels a captured error before it can complete upstream.
        d.io.apb.paddr.poke(0x448);d.io.apb.psel.poke(true);d.io.apb.penable.poke(false)
        d.clock.step();d.io.apb.penable.poke(true);d.clock.step()
        d.io.apb.pready.expect(true);d.io.apb.pslverror.expect(true)
        d.reset.poke(true);d.clock.step();d.io.apb.pready.expect(false);d.io.apb.pslverror.expect(false)
        d.io.apb.psel.poke(false);d.io.apb.penable.poke(false);d.reset.poke(false)
        read(0)._1 shouldBe BigInt("32444750",16)
        d.io.assetActive.expect(false)
      }
    }
  }
  describe("instance expansion and acceptance") {
    it("holds complete fields under backpressure, freezes templates and advances tags only once") {
      simulate(new InstanceStream) { d =>
        d.io.apb.psel.poke(false);d.io.apb.penable.poke(false);d.io.apb.pwrite.poke(false)
        d.io.apb.paddr.poke(0);d.io.apb.pwdata.poke(0);d.io.idle.poke(true)
        d.io.hardwareError.poke(0);d.io.command.ready.poke(false)
        d.reset.poke(true);d.clock.step(2);d.reset.poke(false)
        def access(a:Int,v:BigInt=0,wr:Boolean=true): (BigInt,Boolean) = {
          d.io.apb.paddr.poke(a);d.io.apb.pwdata.poke(v);d.io.apb.pwrite.poke(wr)
          d.io.apb.psel.poke(true);d.io.apb.penable.poke(false);d.clock.step()
          d.io.apb.penable.poke(true);d.io.apb.pready.expect(true)
          val r=(d.io.apb.prdata.peek().litValue,d.io.apb.pslverror.peek().litToBoolean)
          d.clock.step();d.io.apb.psel.poke(false);d.io.apb.penable.poke(false);r
        }
        access(0x40c,15)._2 shouldBe false
        Seq[BigInt](4,BigInt("02a00400",16),24,1920,12,12,0xf81f).zipWithIndex.foreach { case(v,i) =>
          access(0x410+i*4,v)._2 shouldBe false
        }
        access(0x444,65535)._2 shouldBe false
        access(0x408,1)._2 shouldBe false
        Seq[BigInt](BigInt("0070010f",16),BigInt("02221c00",16),26,BigInt("000a000b",16)).zipWithIndex.foreach { case(v,i) =>
          access(0x430+i*4,v)._2 shouldBe false
        }
        access(0x440,1)._2 shouldBe false
        for(_ <- 0 until 5) {
          d.io.command.valid.expect(true);d.io.command.bits.op.expect(4)
          d.io.command.bits.srcAddr.expect(BigInt("02a0041a",16));d.io.command.bits.dstAddr.expect(BigInt("02221c00",16))
          d.io.command.bits.srcStride.expect(24);d.io.command.bits.dstStride.expect(1920)
          d.io.command.bits.widthPixels.expect(11);d.io.command.bits.heightPixels.expect(10)
          d.io.command.bits.color.expect(0);d.io.command.bits.colorKey.expect(0xf81f)
          d.io.command.bits.flags.expect(0);d.io.command.bits.alpha.expect(112);d.io.command.bits.tag.expect(65535)
          d.clock.step()
        }
        // END/template edits must not discard or alter an accepted stalled Alpha.
        access(0x408,2)._2 shouldBe true
        access(0x410,2)._2 shouldBe true
        d.io.command.bits.op.expect(4);d.io.command.bits.tag.expect(65535)
        d.io.command.ready.poke(true);d.clock.step();d.io.command.valid.expect(false)
        access(0x408,2)._2 shouldBe false
        access(0x408,4)._2 shouldBe false
        access(0x408,1)._2 shouldBe false
        Seq[BigInt](BigInt("0040010f",16),BigInt("02221c00",16),0,BigInt("000c000c",16)).zipWithIndex.foreach { case(v,i) => access(0x430+i*4,v) }
        access(0x440,1)._2 shouldBe false
        d.io.command.valid.expect(true);d.io.command.bits.tag.expect(0);d.clock.step()
        access(0x408,2)._2 shouldBe false
        // A stale shadow without four NEW words cannot duplicate that Alpha.
        access(0x408,1)._2 shouldBe false
        access(0x440,1)._2 shouldBe true;d.io.command.valid.expect(false)
      }
    }
    it("rejects partial templates, malformed offsets/headers/sizes and a faulted backend before enqueue") {
      simulate(new InstanceStream) { d =>
        d.io.apb.psel.poke(false);d.io.apb.penable.poke(false);d.io.apb.pwrite.poke(false)
        d.io.apb.paddr.poke(0);d.io.apb.pwdata.poke(0);d.io.idle.poke(true)
        d.io.hardwareError.poke(0);d.io.command.ready.poke(false)
        d.reset.poke(true);d.clock.step(2);d.reset.poke(false)
        def write(a:Int,v:BigInt):Boolean = {
          d.io.apb.paddr.poke(a);d.io.apb.pwdata.poke(v);d.io.apb.pwrite.poke(true)
          d.io.apb.psel.poke(true);d.io.apb.penable.poke(false);d.clock.step()
          d.io.apb.penable.poke(true);val bad=d.io.apb.pslverror.peek().litToBoolean
          d.clock.step();d.io.apb.psel.poke(false);d.io.apb.penable.poke(false);bad
        }
        write(0x40c,16) shouldBe true;write(0x408,4) shouldBe false
        write(0x40c,0) shouldBe false
        Seq[BigInt](3,BigInt("02a00000",16),16,1920,8,8).zipWithIndex.foreach {case(v,i)=>write(0x410+i*4,v)}
        def reject(header:BigInt,offset:BigInt,size:BigInt):Unit = {
          write(0x408,1) shouldBe false
          Seq(header,BigInt("02200000",16),offset,size).zipWithIndex.foreach {case(v,i)=>write(0x430+i*4,v)}
          write(0x440,1) shouldBe true;d.io.command.valid.expect(false)
          write(0x408,2) shouldBe false;write(0x408,4) shouldBe false
        }
        reject(0,0,0x00080008) // Seventh template word never written.
        write(0x428,0xf81f) shouldBe false
        write(0x424,65536) shouldBe false
        reject(0,0,0x00010001) // Narrowed arithmetic cannot legalize oversized metadata.
        write(0x424,8) shouldBe false
        write(0x420,65536) shouldBe false
        reject(0,0,0x00010001)
        write(0x420,8) shouldBe false
        reject(16,0,0x00080008);reject(0x01000000,0,0x00080008)
        reject(0,BigInt("fffffffe",16),0x00010001);reject(0,126,0x00020002)
        reject(0,0,0x00010009);reject(0,1,0x00010001);reject(0,0,0)
        d.io.hardwareError.poke(9);write(0x408,1) shouldBe true
        d.io.hardwareError.poke(0);write(0x408,4) shouldBe false
        d.io.idle.poke(false);write(0x40c,1) shouldBe true;write(0x408,1) shouldBe true
        d.io.idle.poke(true)
        d.reset.poke(true);d.clock.step();d.reset.poke(false)
        reject(0,0,0x00080008) // Reset invalidates unreset template RAM.
      }
    }
  }
}
