package gpu

import chisel3._
import org.scalatest.funspec.AnyFunSpec
import org.scalatest.matchers.should.Matchers
import testutil.StableChiselSim

/** Breaks caught: wrong burst boundaries/word order, leaked partial batch on
  * late AXI error, wrapping bank range, unstable backpressure or stale RAM. */
class FrameListReaderSpec extends AnyFunSpec with StableChiselSim with Matchers {
  describe("whole-list AXI prefetch") {
    it("prefetches ordered descriptors with burst/backpressure and rejects whole malformed batches") {
      simulate(new FrameListReader()) { d =>
        d.io.request.valid.poke(false);d.io.request.bits.address.poke(0);d.io.request.bits.count.poke(0)
        d.io.axiAr.ready.poke(false);d.io.axiR.valid.poke(false)
        d.io.axiR.bits.id.poke(6);d.io.axiR.bits.data.poke(0)
        d.io.axiR.bits.resp.poke(0);d.io.axiR.bits.last.poke(false)
        d.io.descriptor.ready.poke(false)
        d.reset.poke(true);d.clock.step(2);d.reset.poke(false);d.clock.step(2)
        def word(i:Int):BigInt = BigInt("10203040",16) ^ (BigInt(i)*0x010203)
        def run(address:BigInt,count:Int,errorAt:Int = -1,badId:Boolean = false,
          expectedError:Int = 0):Vector[(BigInt,Int)] = {
          d.io.request.ready.expect(true)
          d.io.request.bits.address.poke(address);d.io.request.bits.count.poke(count)
          d.io.request.valid.poke(true);d.clock.step();d.io.request.valid.poke(false)
          var remaining=0;var fed=0;var received=0;var cycles=0
          var addresses=Vector.empty[(BigInt,Int)]
          var held:Option[Vector[BigInt]]=None
          var heldAr:Option[(BigInt,BigInt)]=None
          while(!d.io.done.peek().litToBoolean && cycles<40000) {
            d.io.axiAr.ready.poke(remaining==0 && cycles%3!=0)
            d.io.axiR.valid.poke(remaining>0 && cycles%5!=0)
            d.io.axiR.bits.data.poke(word(fed))
            d.io.axiR.bits.id.poke(if(badId && fed==errorAt) 7 else 6)
            d.io.axiR.bits.resp.poke(if(!badId && fed==errorAt) 2 else 0)
            d.io.axiR.bits.last.poke(remaining==1)
            d.io.descriptor.ready.poke(cycles%7!=0 && cycles%7!=1)
            d.io.fetchedBytes.expect(fed*4)
            if(d.io.fetching.peek().litToBoolean) d.io.descriptor.valid.expect(false)
            held.foreach { values =>
              d.io.descriptor.valid.expect(true)
              (0 until 4).foreach(i=>d.io.descriptor.bits(i).expect(values(i)))
            }
            heldAr.foreach { case(a,len)=>
              d.io.axiAr.valid.expect(true);d.io.axiAr.bits.addr.expect(a);d.io.axiAr.bits.len.expect(len)
            }
            val ar=d.io.axiAr.valid.peek().litToBoolean && d.io.axiAr.ready.peek().litToBoolean
            val r=d.io.axiR.valid.peek().litToBoolean && d.io.axiR.ready.peek().litToBoolean
            val valid=d.io.descriptor.valid.peek().litToBoolean
            if(expectedError!=0) d.io.descriptor.valid.expect(false)
            val consume=valid && d.io.descriptor.ready.peek().litToBoolean
            if(consume) {
              fed shouldBe count*4
              (0 until 4).foreach(i=>d.io.descriptor.bits(i).expect(word(received*4+i)))
              received+=1
            }
            held=if(valid && !consume) Some((0 until 4).map(i=>d.io.descriptor.bits(i).peek().litValue).toVector) else None
            heldAr=if(d.io.axiAr.valid.peek().litToBoolean && !ar)
              Some((d.io.axiAr.bits.addr.peek().litValue,d.io.axiAr.bits.len.peek().litValue)) else None
            val a=d.io.axiAr.bits.addr.peek().litValue
            val beats=d.io.axiAr.bits.len.peek().litValue.toInt+1
            if(ar) {
              remaining shouldBe 0
              d.io.axiAr.bits.id.expect(6);d.io.axiAr.bits.size.expect(2);d.io.axiAr.bits.burst.expect(1)
              a shouldBe address+fed*4
              ((a & 4095)+beats*4) should be <= BigInt(4096)
              addresses :+= ((a,beats))
            }
            d.clock.step();cycles+=1
            if(r) {remaining-=1;fed+=1}
            if(ar) remaining=beats
          }
          cycles should be < 40000
          d.io.done.expect(true);d.io.busy.expect(false);d.io.error.expect(expectedError)
          if(expectedError==0) {received shouldBe count;fed shouldBe count*4}
          else received shouldBe 0
          d.io.axiR.valid.poke(false);d.io.axiAr.ready.poke(false);d.clock.step()
          d.io.done.expect(false);d.io.descriptor.valid.expect(false)
          addresses
        }
        val bank=BigInt("02d20000",16)
        run(bank+0xff0,3) shouldBe Vector((bank+0xff0,4),(bank+0x1000,8))
        run(bank,65) shouldBe Vector((bank,256),(bank+1024,4))
        run(bank,1024).length shouldBe 16
        run(BigInt("02d27ff0",16),1).length shouldBe 1 // Exact end of second bank.
        for((a,n)<-Seq((bank,0),(bank,1025),(bank+1,1),(bank-16,1),
          (bank+0x3ff0,2),(BigInt("02d28000",16),1),(BigInt("fffffff0",16),1))) {
          run(a,n,expectedError=GpuError.AddressRange).length shouldBe 0
        }
        run(bank,3,errorAt=0,expectedError=GpuError.AxiResponse)
        run(bank,3,errorAt=11,expectedError=GpuError.AxiResponse)
        run(bank,3,errorAt=11,badId=true,expectedError=GpuError.AxiResponse)
        run(bank,1).length shouldBe 1 // No leaked content/error from prior failed list.
        // A reset must discard a descriptor stalled after a complete AXI read.
        d.io.request.bits.address.poke(bank);d.io.request.bits.count.poke(1)
        d.io.request.valid.poke(true);d.clock.step();d.io.request.valid.poke(false)
        d.io.axiAr.ready.poke(true);d.io.descriptor.ready.poke(false)
        var wait=0
        while(!d.io.axiAr.valid.peek().litToBoolean && wait<20) {d.clock.step();wait+=1}
        d.io.axiAr.valid.expect(true);d.clock.step();d.io.axiAr.ready.poke(false)
        for(i<-0 until 4) {
          d.io.axiR.valid.poke(true);d.io.axiR.bits.data.poke(word(i))
          d.io.axiR.bits.resp.poke(0);d.io.axiR.bits.id.poke(6);d.io.axiR.bits.last.poke(i==3)
          d.io.axiR.ready.expect(true);d.clock.step()
        }
        d.io.axiR.valid.poke(false);d.clock.step(5)
        d.io.descriptor.valid.expect(true);d.io.busy.expect(true);d.io.done.expect(false)
        d.io.request.ready.expect(false) // Never accept another list while stalled.
        d.reset.poke(true);d.clock.step(2);d.reset.poke(false);d.clock.step(2)
        d.io.descriptor.valid.expect(false);d.io.request.ready.expect(true)
        run(bank+16,1).length shouldBe 1
      }
    }
  }
}
