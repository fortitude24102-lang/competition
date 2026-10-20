package gpu

import chisel3._
import chisel3.util._
import org.scalatest.funspec.AnyFunSpec
import org.scalatest.matchers.should.Matchers
import scala.collection.mutable
import testutil.StableChiselSim

private class CachedKeyPipelineHarness(writeCredits:Int=2) extends Module {
  val io = IO(new Bundle {
    val command = Flipped(Decoupled(new GpuCommand))
    val readRequest = Decoupled(new AxiReadRequest)
    val readData = Flipped(Decoupled(new AxiReadBeat))
    val readDone = Input(Bool()); val readError = Input(Bool())
    val axi = new Axi4MasterPort
    val completion = Decoupled(new GpuCompletion)
    val pixels = Output(UInt(2.W))
  })
  private val k = Module(new CachedKeyStream(pipelineWrites=true,writeCredits=writeCredits))
  private val w = Module(new AxiWritePipeline(writeCredits))
  k.io.command <> io.command; io.readRequest <> k.io.readRequest; k.io.readData <> io.readData
  k.io.readDone := io.readDone; k.io.readError := io.readError
  w.io.request <> k.io.writeRequest; w.io.data <> k.io.writeData
  k.io.writeDone := w.io.done; k.io.writeError := w.io.error
  io.completion <> k.io.completion; io.pixels := k.io.wordPixelsDone
  io.axi.aw <> w.io.axiAw; io.axi.w <> w.io.axiW; w.io.axiB <> io.axi.b
  io.axi.ar.valid := false.B; io.axi.ar.bits := 0.U.asTypeOf(new Axi4Address); io.axi.r.ready := false.B
}

class CachedKeyPipelineSpec extends AnyFunSpec with StableChiselSim with Matchers {
  describe("cached Key row issue and retirement") {
    val cases=(for(phase<-Seq(0,2);fault<-Seq("none","B","cache"))yield(2,phase,fault)) ++
      Seq((4,0,"none"),(4,2,"none"),(4,2,"B"),(4,0,"cache"))
    for((credits,phase,fault) <- cases) {
      it(s"preserves pixels and drains every promised row credits=$credits phase=$phase fault=$fault") {
        simulate(new CachedKeyPipelineHarness(credits)) { d =>
          val pattern = Vector(0xf81f,0x1234,0x5678,0xf81f,0xffff,0x9abc,0xf81f,0,
            0x101,0x202,0x303,0x404,0xf81f,0xf81f,0x707,0x808,
            0xf81f,0xf81f,0x1111,0x2222,0x3333,0x4444,0x5555,0x6666)
          val pixels=if(credits==4)pattern++pattern else pattern
          val height=pixels.size/8
          val words = pixels.grouped(2).map(p => BigInt(p(0)) | (BigInt(p(1)) << 16)).toVector
          val base = 0x4000+phase
          val memory = mutable.Map.empty[Int,Int].withDefaultValue(0x5a)
          val writes = mutable.Queue.empty[(Int,Int)]
          val replies = mutable.Queue.empty[(Int,Int)]
          var offset=0; var source=0; var cacheActive=false; var sendDone=false
          var awCount=0; var bCount=0; var maxReplies=0; var processed=0; var finished=false
          d.io.command.bits.poke(0.U.asTypeOf(new GpuCommand))
          d.io.command.bits.op.poke(GpuOpcode.ColorKey); d.io.command.bits.srcAddr.poke(0x2000)
          d.io.command.bits.dstAddr.poke(base); d.io.command.bits.srcStride.poke(16)
          d.io.command.bits.dstStride.poke(1920); d.io.command.bits.widthPixels.poke(8)
          d.io.command.bits.heightPixels.poke(height); d.io.command.bits.colorKey.poke(0xf81f); d.io.command.bits.tag.poke(7)
          d.io.command.valid.poke(true); d.io.completion.ready.poke(true)
          d.io.readRequest.ready.poke(false); d.io.readData.valid.poke(false)
          d.io.readData.bits.poke(0.U.asTypeOf(new AxiReadBeat)); d.io.readDone.poke(false); d.io.readError.poke(false)
          d.io.axi.aw.ready.poke(false); d.io.axi.w.ready.poke(false); d.io.axi.ar.ready.poke(false)
          d.io.axi.r.valid.poke(false); d.io.axi.r.bits.poke(0.U.asTypeOf(new Axi4ReadData))
          d.io.axi.b.valid.poke(false); d.io.axi.b.bits.poke(0.U.asTypeOf(new Axi4WriteResponse))
          d.io.command.ready.expect(true); d.clock.step(); d.io.command.valid.poke(false)
          var cycle=0
          while(!finished && cycle<2000) {
            d.io.readRequest.ready.poke(true)
            d.io.readData.valid.poke(cacheActive && source<words.size && cycle%3!=1)
            d.io.readData.bits.data.poke(if(source<words.size)words(source) else BigInt(0))
            d.io.readDone.poke(sendDone); d.io.readError.poke(sendDone && fault=="cache")
            d.io.axi.aw.ready.poke(cycle%7!=3); d.io.axi.w.ready.poke(cycle%5!=1)
            val reply = replies.headOption.filter(_._1<=cycle)
            d.io.axi.b.valid.poke(reply.nonEmpty); d.io.axi.b.bits.resp.poke(reply.map(_._2).getOrElse(0))
            if(d.io.readRequest.valid.peek().litToBoolean) {
              d.io.readRequest.bits.address.expect(0x2000); d.io.readRequest.bits.bytes.expect(pixels.size*2); cacheActive=true
            }
            val inputFire=d.io.readData.valid.peek().litToBoolean && d.io.readData.ready.peek().litToBoolean
            sendDone=inputFire && source==words.size-1
            if(inputFire)source+=1
            if(d.io.axi.aw.valid.peek().litToBoolean && d.io.axi.aw.ready.peek().litToBoolean) {
              writes.enqueue((d.io.axi.aw.bits.addr.peek().litValue.toInt,d.io.axi.aw.bits.len.peek().litValue.toInt+1))
              awCount+=1
            }
            if(d.io.axi.w.valid.peek().litToBoolean && d.io.axi.w.ready.peek().litToBoolean) {
              assert(writes.nonEmpty,"W without its AW")
              val (address,beats)=writes.head; val word=d.io.axi.w.bits.data.peek().litValue
              val strobe=d.io.axi.w.bits.strb.peek().litValue.toInt
              for(lane<-0 until 4 if (strobe&(1<<lane))!=0)memory(address+offset*4+lane)=((word>>(lane*8))&255).toInt
              d.io.axi.w.bits.last.expect(offset==beats-1); offset+=1
              if(offset==beats) {
                writes.dequeue(); offset=0
                replies.enqueue((cycle+80,if(fault=="B" && awCount==1)2 else 0))
                maxReplies=math.max(maxReplies,replies.size)
              }
            }
            if(reply.nonEmpty && d.io.axi.b.ready.peek().litToBoolean) {replies.dequeue();bCount+=1}
            processed+=d.io.pixels.peek().litValue.toInt
            if(d.io.completion.valid.peek().litToBoolean) {
              assert(replies.isEmpty && writes.isEmpty,"command retired before promised W/B")
              d.io.completion.bits.tag.expect(7)
              d.io.completion.bits.error.expect(if(fault=="none")GpuError.None else GpuError.AxiResponse)
              finished=true
            }
            d.clock.step(); cycle+=1
          }
          assert(finished,s"timeout source=$source AW=$awCount B=$bCount")
          source shouldBe words.size; bCount shouldBe awCount
          if(fault=="none") {awCount shouldBe height; maxReplies shouldBe credits}
          else if(fault=="B") awCount shouldBe credits
          else assert(awCount>=1 && awCount<=height)
          processed shouldBe awCount*8
          for(y<-0 until height; byte<- -2 until 20) {
            val x=byte/2
            val want=if(y<awCount && byte>=0 && byte<16 && pixels(y*8+x)!=0xf81f)
              (pixels(y*8+x)>>((byte&1)*8))&255 else 0x5a
            memory(base+y*1920+byte) shouldBe want
          }
        }
      }
    }
  }
}
