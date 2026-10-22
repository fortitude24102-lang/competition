package gpu

import chisel3._
import org.scalatest.funspec.AnyFunSpec
import org.scalatest.matchers.should.Matchers
import scala.collection.mutable
import testutil.StableChiselSim

/** A byte model, not a busy-only test: truncation, crossed pages, lost banks,
  * early completion, unstable promises, failed-response replay and reset loss. */
class WideCopyDmaSpec extends AnyFunSpec with StableChiselSim with Matchers {
  private def init(d:WideCopyDma):Unit = {
    d.io.request.valid.poke(false);d.io.request.bits.poke(0.U.asTypeOf(new WideCopyRequest))
    d.io.completion.ready.poke(false);d.io.abort.poke(false)
    d.io.axi.ar.ready.poke(false);d.io.axi.aw.ready.poke(false);d.io.axi.w.ready.poke(false)
    d.io.axi.r.valid.poke(false);d.io.axi.r.bits.poke(0.U.asTypeOf(new Axi128ReadData))
    d.io.axi.b.valid.poke(false);d.io.axi.b.bits.poke(0.U.asTypeOf(new Axi128WriteResponse))
    d.clock.step()
  }
  private def run(d:WideCopyDma,src:Long,dst:Long,n:Int,tag:Int,
    fault:Int=0,abortAt:String="",faultBeat:Int=3,scenario:String=""):Unit = {
    val mem=mutable.Map.empty[Long,Int].withDefaultValue(0xa5)
    for(i<-0 until n)mem(src+i)=((i*37)^(i>>7)^0x39)&255
    val reads=mutable.Queue.empty[(Long,Int)]
    val writes=mutable.Queue.empty[(Long,Int)]
    val replies=mutable.Queue.empty[Int]
    var ro=0;var wo=0;var rBeats=0;var ar=0;var aw=0;var bs=0
    var accepted=false;var done=false;var cycle=0;var aborted=false;var abortCycle= -1
    var heldAR:Option[Vector[BigInt]]=None;var heldAW:Option[Vector[BigInt]]=None;var heldW:Option[Vector[BigInt]]=None
    var peakR=0;var peakW=0;var overlapped=false
    var sawFaultPrecondition=false
    while(!done && cycle<14000) {
      d.io.request.valid.poke(!accepted)
      d.io.request.bits.srcAddr.poke(src);d.io.request.bits.dstAddr.poke(dst)
      d.io.request.bits.bytes.poke(n);d.io.request.bits.tag.poke(tag)
      d.io.axi.ar.ready.poke(cycle%7>=3)
      d.io.axi.aw.ready.poke(cycle%11>=5)
      d.io.axi.w.ready.poke(cycle%5!=1)
      val waitForWrite=scenario=="read-after-aw" && rBeats>=64 && aw==0
      val waitForB=scenario=="b-during-r" && rBeats>=64 && bs==0
      val rv=reads.nonEmpty && cycle%4!=0 && !waitForWrite && !waitForB
      d.io.axi.r.valid.poke(rv)
      val (ra,rn)=reads.headOption.getOrElse((0L,1))
      d.io.axi.r.bits.data.poke((0 until 16).foldLeft(BigInt(0))((v,b)=>v|(BigInt(mem(ra+ro*16+b))<<(b*8))))
      d.io.axi.r.bits.id.poke(if(fault==2 && rBeats==faultBeat)7 else 0)
      d.io.axi.r.bits.resp.poke(if(fault==1 && rBeats==faultBeat)2 else 0)
      d.io.axi.r.bits.last.poke(if(fault==3 && rBeats==faultBeat)ro!=rn-1 else ro==rn-1)
      val bv=replies.headOption.exists(_<=cycle)
      d.io.axi.b.valid.poke(bv);d.io.axi.b.bits.id.poke(if(fault==5 && bs==0)9 else 0)
      d.io.axi.b.bits.resp.poke(if(fault==4 && bs==0)2 else 0)
      def yes(b:Bool)=b.peek().litToBoolean
      def fire(v:Bool,r:Bool)=yes(v)&&yes(r)
      // Hold abort for three cycles; the fabric reset is deliberately untouched.
      val trigger=abortAt match {
        case "ar"=>yes(d.io.axi.ar.valid)&& !yes(d.io.axi.ar.ready)
        case "r"=>rBeats>=5
        case "aw"=>yes(d.io.axi.aw.valid)&& !yes(d.io.axi.aw.ready)
        case "w"=>writes.nonEmpty && wo>=3
        case "b"=>replies.nonEmpty
        case "completion"=>yes(d.io.completion.valid)
        case _=>false
      }
      if(!aborted && trigger){aborted=true;abortCycle=cycle}
      d.io.abort.poke(aborted && cycle<abortCycle+3)
      def snapshot(bits:Bundle):Vector[BigInt]=bits.elements.values.map(_.asInstanceOf[UInt].peek().litValue).toVector
      def stable(old:Option[Vector[BigInt]],valid:Bool,bits:Bundle):Unit=old.foreach { v =>
        assert(yes(valid),s"VALID withdrawn at $cycle/$abortAt")
        snapshot(bits) shouldBe v
      }
      stable(heldAR,d.io.axi.ar.valid,d.io.axi.ar.bits)
      stable(heldAW,d.io.axi.aw.valid,d.io.axi.aw.bits)
      stable(heldW,d.io.axi.w.valid,d.io.axi.w.bits)
      val rf=fire(d.io.axi.r.valid,d.io.axi.r.ready)
      if(scenario=="read-after-aw" && rf && rBeats==faultBeat) {
        assert(writes.nonEmpty && aw>bs,"R fault did not occur while a committed bank still owed W")
        sawFaultPrecondition=true
      }
      if(scenario=="b-during-r" && bv && yes(d.io.axi.b.ready) && bs==0) {
        assert(reads.nonEmpty && rBeats==64 && yes(d.io.axi.r.ready) && !rv,
          "bad B did not occur with the other accepted read still stalled")
        sawFaultPrecondition=true
      }
      if(fire(d.io.request.valid,d.io.request.ready))accepted=true
      if(fire(d.io.axi.ar.valid,d.io.axi.ar.ready)) {
        val a=d.io.axi.ar.bits.addr.peek().litValue.longValue
        val beats=d.io.axi.ar.bits.len.peek().litValue.toInt+1
        d.io.axi.ar.bits.size.expect(4);d.io.axi.ar.bits.burst.expect(1)
        assert(beats<=64 && (a&4095)+beats*16<=4096)
        reads.enqueue((a,beats));ar+=1;peakR=peakR.max(reads.size);assert(reads.size<=2)
      }
      if(fire(d.io.axi.aw.valid,d.io.axi.aw.ready)) {
        val a=d.io.axi.aw.bits.addr.peek().litValue.longValue
        val beats=d.io.axi.aw.bits.len.peek().litValue.toInt+1
        d.io.axi.aw.bits.size.expect(4);d.io.axi.aw.bits.burst.expect(1)
        assert(beats<=64 && (a&4095)+beats*16<=4096)
        writes.enqueue((a,beats));aw+=1;peakW=peakW.max(aw-bs);assert(aw-bs<=2)
      }
      if(fire(d.io.axi.w.valid,d.io.axi.w.ready)) {
        assert(writes.nonEmpty);val(a,beats)=writes.head
        d.io.axi.w.bits.strb.expect(65535);d.io.axi.w.bits.last.expect(wo==beats-1)
        val data=d.io.axi.w.bits.data.peek().litValue
        for(b<-0 until 16) {
          val byte=((data>>(8*b))&255).toInt
          // Required even on fault/abort: promised W must retain source bytes.
          byte shouldBe mem(src+(a-dst)+wo*16+b)
          mem(a+wo*16+b)=byte
        }
        wo+=1;if(wo==beats){writes.dequeue();wo=0;replies.enqueue(cycle+170)}
        if(rv)overlapped=true
      }
      if(bv && yes(d.io.axi.b.ready)){replies.dequeue();bs+=1}
      if(yes(d.io.completion.valid) && !aborted) {
        assert(accepted && reads.isEmpty && writes.isEmpty && replies.isEmpty && aw==bs,"early retirement")
        d.io.completion.bits.tag.expect(tag)
        d.io.completion.bits.error.expect(if(fault==0)GpuError.None else GpuError.AxiResponse)
        // Exercise completion backpressure too.
        if(cycle%5==0){d.io.completion.ready.poke(true);done=true}
      }
      def hold(v:Bool,r:Bool,b:Bundle)=if(yes(v)&& !yes(r))Some(snapshot(b))else None
      heldAR=hold(d.io.axi.ar.valid,d.io.axi.ar.ready,d.io.axi.ar.bits)
      heldAW=hold(d.io.axi.aw.valid,d.io.axi.aw.ready,d.io.axi.aw.bits)
      heldW=hold(d.io.axi.w.valid,d.io.axi.w.ready,d.io.axi.w.bits)
      d.clock.step()
      if(rf){ro+=1;rBeats+=1;if(ro==rn){reads.dequeue();ro=0}}
      if(aborted && cycle>abortCycle+3 && yes(d.io.request.ready)) {
        assert(reads.isEmpty && writes.isEmpty && replies.isEmpty && aw==bs,"abort lost accepted transaction")
        d.io.completion.valid.expect(false);done=true
      }
      cycle+=1
    }
    assert(done,s"timeout fault=$fault abort=$abortAt ar=$ar aw=$aw b=$bs")
    if(abortAt.nonEmpty)assert(aborted,s"abort trigger not reached: $abortAt")
    if(scenario.nonEmpty){assert(sawFaultPrecondition);aw shouldBe 1}
    if(fault==0 && !aborted) {
      for(i<-0 until n)mem(dst+i) shouldBe mem(src+i)
      mem(dst-1) shouldBe 0xa5;mem(dst+n) shouldBe 0xa5
      assert(overlapped,"read/write never overlap")
      assert(peakR==2 && peakW==2,"two-bank credit unused")
    }
    d.io.request.valid.poke(false);d.io.completion.ready.poke(false);d.io.abort.poke(false)
    d.io.axi.r.valid.poke(false);d.io.axi.b.valid.poke(false);d.clock.step(3)
  }
  it("copies all128-bit lanes across both page boundaries with two banks and final-B fencing") {
    simulate(new WideCopyDma) { d=>
      init(d)
      run(d,0x02400ff0L,0x02000fe0L,4096,1)
      run(d,0x02400000L,0x02000800L,16384,2)
    }
  }
  it("drains response/ID/last faults and accepts a clean successor without replay") {
    simulate(new WideCopyDma) { d=>
      init(d)
      for(f<-1 to 5) {
        run(d,0x02400000L,0x02000000L,8192,f,fault=f)
        run(d,0x02400000L,0x02000000L,4096,100+f)
      }
      // Wrong marker on the expected last beat must not leave a live bank.
      run(d,0x02400000L,0x02000000L,8192,30,fault=3,faultBeat=63)
    }
  }
  it("preserves every promised transaction through GPU-only abort and suppresses stale completion") {
    simulate(new WideCopyDma) { d=>
      init(d)
      for(point<-Seq("ar","r","aw","w","b","completion")) {
        run(d,0x02400000L,0x02000000L,8192,60,abortAt=point)
        run(d,0x02400000L,0x02000000L,4096,61)
      }
    }
  }
  it("preserves committed W bytes on a later R failure and a bad B with future R still stalled") {
    simulate(new WideCopyDma) { d=>
      init(d)
      run(d,0x02400000L,0x02000000L,4096,201,fault=1,faultBeat=70,scenario="read-after-aw")
      run(d,0x02400000L,0x02000000L,4096,202)
      run(d,0x02400000L,0x02000000L,4096,203,fault=4,scenario="b-during-r")
      run(d,0x02400000L,0x02000000L,4096,204)
    }
  }
}
