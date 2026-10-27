package gpu

import chisel3._
import chisel3.util._
import scala.collection.mutable
import org.scalatest.funspec.AnyFunSpec
import org.scalatest.matchers.should.Matchers
import testutil.StableChiselSim

class CachedRowHandoffHarness extends Module {
  val io=IO(new Bundle {
    val command=Flipped(Decoupled(new GpuCommand))
    val readRequest=Decoupled(new AxiReadRequest)
    val readData=Flipped(Decoupled(new AxiReadBeat))
    val readDone=Input(Bool())
    val aw=Decoupled(new Axi4Address)
    val w=Decoupled(new Axi4WriteData)
    val b=Flipped(Decoupled(new Axi4WriteResponse))
    val completion=Decoupled(new GpuCompletion)
    val handoff=Output(Bool())
  })
  val stream=Module(new CachedKeyStream(pipelineWrites=true,allowCopyPrefetch=true,writeCredits=4))
  val writer=Module(new AxiWritePipeline(4))
  stream.io.command<>io.command;io.readRequest<>stream.io.readRequest
  stream.io.readData<>io.readData;stream.io.readDone:=io.readDone;stream.io.readError:=false.B
  writer.io.request<>stream.io.writeRequest;writer.io.data<>stream.io.writeData
  stream.io.writeDone:=writer.io.done;stream.io.writeError:=writer.io.error
  io.aw<>writer.io.axiAw;io.w<>writer.io.axiW;writer.io.axiB<>io.b
  io.completion<>stream.io.completion
  io.handoff:=stream.io.writeRequest.fire && stream.io.writeData.fire
}

class CachedRowHandoffSpec extends AnyFunSpec with StableChiselSim with Matchers {
  it("preserves strided row bytes, zero strobes and final-B drain across stalls and B failures") {
    simulate(new CachedRowHandoffHarness) { d =>
      for(stalled<-Seq(false,true);failedRow<-Seq(-1,0,2)) {
        d.reset.poke(true);d.clock.step(2);d.reset.poke(false)
        val base=0x02000102L;val width=8;val height=4;val stride=18;val key=0xbeef
        val pixels=(0 until width*height).map(i=>if(i/width==2 || i%5==0)key else 0x100+i)
        val words=pixels.grouped(2).map(p=>p(0).toLong|(p(1).toLong<<16)).toVector
        d.io.command.bits.poke(0.U.asTypeOf(new GpuCommand));d.io.command.bits.op.poke(GpuOpcode.ColorKey)
        d.io.command.bits.srcAddr.poke(0x02a00000L);d.io.command.bits.dstAddr.poke(base)
        d.io.command.bits.srcStride.poke(width*2);d.io.command.bits.dstStride.poke(stride)
        d.io.command.bits.widthPixels.poke(width);d.io.command.bits.heightPixels.poke(height)
        d.io.command.bits.colorKey.poke(key);d.io.command.bits.tag.poke(42)
        d.io.command.valid.poke(false);d.io.readRequest.ready.poke(true);d.io.readData.valid.poke(false)
        d.io.readData.bits.poke(0.U.asTypeOf(new AxiReadBeat));d.io.readDone.poke(false)
        d.io.aw.ready.poke(true);d.io.w.ready.poke(true);d.io.b.valid.poke(false)
        d.io.b.bits.poke(0.U.asTypeOf(new Axi4WriteResponse));d.io.completion.ready.poke(true)
        case class Burst(address:Long,var left:Int,var offset:Int,row:Int)
        val bursts=mutable.Queue.empty[Burst];val responses=mutable.Queue.empty[(Int,Int)]
        val memory=mutable.Map.empty[Long,Int]
        var sent=false;var reading=false;var readIndex=0;var readDone=false
        var awCount=0;var bCount=0;var handoffs=0;var zeroWords=0;var complete=false;var cycles=0
        while(!complete && cycles<1000) {
          d.io.command.valid.poke(!sent);d.io.readDone.poke(readDone);readDone=false
          val rvalid=reading && readIndex<words.size && (!stalled || cycles%4!=1)
          d.io.readData.valid.poke(rvalid)
          d.io.readData.bits.data.poke(if(readIndex<words.size)words(readIndex)else 0L)
          d.io.readData.bits.last.poke(readIndex==words.size-1)
          d.io.aw.ready.poke(!stalled || cycles%5!=1);d.io.w.ready.poke(!stalled || cycles%7!=2)
          val bvalid=responses.headOption.exists(_._1<=cycles)
          d.io.b.valid.poke(bvalid);d.io.b.bits.id.poke(0)
          d.io.b.bits.resp.poke(if(bvalid && responses.front._2==failedRow)2 else 0)
          if(d.io.command.valid.peek().litToBoolean && d.io.command.ready.peek().litToBoolean)sent=true
          if(d.io.readRequest.valid.peek().litToBoolean) {
            d.io.readRequest.bits.address.expect(0x02a00000L);d.io.readRequest.bits.bytes.expect(words.size*4)
            reading=true
          }
          val rf=rvalid && d.io.readData.ready.peek().litToBoolean
          val aw=d.io.aw.valid.peek().litToBoolean && d.io.aw.ready.peek().litToBoolean
          if(aw) {
            val logical=base+awCount*stride;val beats=(width*2+(logical&3).toInt+3)/4
            assert(awCount<height);d.io.aw.bits.addr.expect(logical& ~3L);d.io.aw.bits.len.expect(beats-1)
            bursts.enqueue(Burst(logical& ~3L,beats,0,awCount));awCount+=1
          }
          if(d.io.w.valid.peek().litToBoolean && d.io.w.ready.peek().litToBoolean) {
            assert(bursts.nonEmpty);val burst=bursts.front
            val data=d.io.w.bits.data.peek().litValue.toLong;val mask=d.io.w.bits.strb.peek().litValue.toInt
            d.io.w.bits.last.expect(burst.left==1);if(mask==0)zeroWords+=1
            for(lane<-0 until 4 if ((mask>>lane)&1)!=0)memory(burst.address+burst.offset+lane)=((data>>(8*lane))&255).toInt
            burst.left-=1;burst.offset+=4
            if(burst.left==0){bursts.dequeue();responses.enqueue((cycles+3,burst.row))}
          }
          if(bvalid && d.io.b.ready.peek().litToBoolean){responses.dequeue();bCount+=1}
          if(d.io.handoff.peek().litToBoolean)handoffs+=1
          complete=d.io.completion.valid.peek().litToBoolean
          if(complete){d.io.completion.bits.tag.expect(42);d.io.completion.bits.error.expect(if(failedRow>=0)GpuError.AxiResponse else GpuError.None)}
          d.clock.step();if(rf){readIndex+=1;if(readIndex==words.size)readDone=true};cycles+=1
        }
        assert(complete && sent && readIndex==words.size && bursts.isEmpty && responses.isEmpty && bCount==awCount,
          s"complete=$complete rows=$awCount responses=$bCount read=$readIndex handoffs=$handoffs bursts=${bursts.size} pendingB=${responses.size}")
        if(failedRow<0){awCount shouldBe height;zeroWords should be > 0}
        for(row<-0 until awCount;x<-0 until width) {
          val pixel=pixels(row*width+x);val address=base+row*stride+x*2
          val observed=memory.getOrElse(address,0x5a)|(memory.getOrElse(address+1,0x5a)<<8)
          observed shouldBe (if(pixel==key)0x5a5a else pixel)
        }
        println(s"ROW_HANDOFF,stalled=$stalled,failedRow=$failedRow,rows=$awCount,handoffs=$handoffs,cycles=$cycles")
        if(!stalled && failedRow<0)handoffs shouldBe height-1
      }
    }
  }
}
