package gpu

import chisel3._
import org.scalatest.funspec.AnyFunSpec
import org.scalatest.matchers.should.Matchers
import testutil.StableChiselSim

class KeyWritePipelineSpec extends AnyFunSpec with StableChiselSim with Matchers {
  it("uses four write credits, blocks the fifth and drains errors at every B position") {
    simulate(new AxiWritePipeline(writeCredits=4)) { d =>
      d.io.request.valid.poke(false); d.io.request.bits.address.poke(0); d.io.request.bits.beats.poke(1)
      d.io.data.valid.poke(false); d.io.data.bits.data.poke(0); d.io.data.bits.strb.poke(15)
      d.io.axiAw.ready.poke(true); d.io.axiW.ready.poke(true); d.io.axiB.valid.poke(false)
      d.io.axiB.bits.poke(0.U.asTypeOf(new Axi4WriteResponse))
      def request(a:Int,n:Int=1):Unit = {
        d.io.request.bits.address.poke(a); d.io.request.bits.beats.poke(n); d.io.request.valid.poke(true)
        d.io.request.ready.expect(true); d.clock.step(); d.io.request.valid.poke(false)
      }
      def burst(a:Int,n:Int):Unit = {
        d.io.axiAw.valid.expect(true); d.io.axiAw.bits.addr.expect(a); d.io.axiAw.bits.len.expect(n-1)
        d.clock.step(); d.io.data.valid.poke(true)
        for(i<-0 until n) {
          d.io.data.bits.data.poke(a+i); d.io.data.bits.strb.poke(if(i==0)0 else 15)
          d.io.axiW.valid.expect(true); d.io.axiW.bits.data.expect(a+i)
          d.io.axiW.bits.strb.expect(if(i==0)0 else 15); d.io.axiW.bits.last.expect(i==n-1)
          d.io.done.expect(false); d.clock.step()
        }
        d.io.data.valid.poke(false)
      }
      def reply(bad:Boolean,badId:Boolean=false,finalBurst:Boolean=true):Unit = {
        d.io.axiB.valid.poke(true); d.io.axiB.bits.resp.poke(if(bad && !badId)2 else 0)
        d.io.axiB.bits.id.poke(if(badId)1 else 0); d.io.axiB.ready.expect(true); d.clock.step()
        d.io.axiB.valid.poke(false); d.io.done.expect(finalBurst)
        d.io.error.expect(bad && finalBurst); d.clock.step(); d.io.done.expect(false)
      }
      // Removing a response credit must fail the fourth admission below.
      for(failed<- -1 to 4) {
        for(i<-0 until 4) { request(0x2000+i*0x100); burst(0x2000+i*0x100,1) }
        d.io.request.valid.poke(true); d.io.request.ready.expect(false)
        d.clock.step(4); d.io.done.expect(false); d.io.request.valid.poke(false)
        for(i<-0 until 4)reply(i==failed || (failed==4 && i==3),failed==4 && i==3)
        d.clock.step(2); d.io.request.ready.expect(true)
      }
      request(0xff8,4); burst(0xff8,2); burst(0x1000,2)
      request(0x3000); burst(0x3000,1); request(0x3100); burst(0x3100,1)
      d.io.request.ready.expect(false)
      reply(true,finalBurst=false)
      // Split request's first error belongs only to its final B, not later rows.
      d.io.axiB.valid.poke(true); d.io.axiB.bits.resp.poke(0); d.io.axiB.bits.id.poke(0)
      d.clock.step(); d.io.axiB.valid.poke(false); d.io.done.expect(true); d.io.error.expect(true); d.clock.step()
      reply(false); reply(false); d.clock.step(2); d.io.request.ready.expect(true)
    }
  }
  describe("Key-only two-burst writer") {
    it("issues two ordered rows before B without retiring either early or accepting a third") {
      simulate(new AxiWritePipeline) { d =>
        d.io.request.valid.poke(false); d.io.request.bits.address.poke(0); d.io.request.bits.beats.poke(0)
        d.io.data.valid.poke(false); d.io.data.bits.data.poke(0); d.io.data.bits.strb.poke(0)
        d.io.axiAw.ready.poke(true); d.io.axiW.ready.poke(true); d.io.axiB.valid.poke(false)
        d.io.axiB.bits.poke(0.U.asTypeOf(new Axi4WriteResponse))
        def request(a: Int): Unit = {
          d.io.request.bits.address.poke(a); d.io.request.bits.beats.poke(4); d.io.request.valid.poke(true)
          d.io.request.ready.expect(true); d.clock.step(); d.io.request.valid.poke(false)
          d.io.axiAw.valid.expect(true); d.io.axiAw.bits.addr.expect(a); d.io.axiAw.bits.len.expect(3)
          d.clock.step()
        }
        def row(seed: Int): Unit = {
          for(i <- 0 until 4) {
            d.io.data.valid.poke(true); d.io.data.bits.data.poke(seed+i); d.io.data.bits.strb.poke(if(i==1)0 else 15)
            d.io.axiW.valid.expect(true); d.io.axiW.bits.data.expect(seed+i)
            d.io.axiW.bits.strb.expect(if(i==1)0 else 15); d.io.axiW.bits.last.expect(i==3)
            d.io.done.expect(false); d.clock.step()
          }
          d.io.data.valid.poke(false)
        }
        request(0x1000); row(16); request(0x1800); row(32)
        d.io.request.valid.poke(true); d.io.request.bits.address.poke(0x2000)
        d.io.request.ready.expect(false); d.clock.step(5); d.io.done.expect(false)
        d.io.request.valid.poke(false)
        d.io.axiB.valid.poke(true); d.io.axiB.ready.expect(true); d.clock.step()
        d.io.axiB.valid.poke(false); d.io.done.expect(true); d.io.error.expect(false); d.clock.step()
        d.io.done.expect(false)
        d.io.axiB.valid.poke(true); d.clock.step(); d.io.axiB.valid.poke(false)
        d.io.done.expect(true); d.io.error.expect(false); d.clock.step(); d.io.done.expect(false)
        d.io.request.ready.expect(true)
      }
    }

    it("splits at 4KiB and aggregates the first B error only at final request retirement") {
      simulate(new AxiWritePipeline) { d =>
        d.io.request.valid.poke(true); d.io.request.bits.address.poke(0xff8); d.io.request.bits.beats.poke(4)
        d.io.data.valid.poke(false); d.io.data.bits.data.poke(0); d.io.data.bits.strb.poke(15)
        d.io.axiAw.ready.poke(true); d.io.axiW.ready.poke(true); d.io.axiB.valid.poke(false)
        d.io.axiB.bits.poke(0.U.asTypeOf(new Axi4WriteResponse)); d.clock.step()
        d.io.request.valid.poke(false)
        for (a <- Seq(0xff8,0x1000)) {
          d.io.axiAw.valid.expect(true); d.io.axiAw.bits.addr.expect(a); d.io.axiAw.bits.len.expect(1)
          d.clock.step(); d.io.data.valid.poke(true)
          for(i <- 0 until 2) { d.io.axiW.bits.last.expect(i==1); d.clock.step() }
          d.io.data.valid.poke(false)
        }
        d.io.axiB.valid.poke(true); d.io.axiB.bits.resp.poke(2); d.clock.step()
        d.io.axiB.valid.poke(false); d.io.done.expect(false); d.io.request.ready.expect(false)
        d.clock.step(3); d.io.axiB.bits.resp.poke(0); d.io.axiB.valid.poke(true); d.clock.step()
        d.io.axiB.valid.poke(false); d.io.done.expect(true); d.io.error.expect(true); d.clock.step(2)
        d.io.done.expect(false); d.io.request.ready.expect(true)
      }
    }

    for (failedRequest <- Seq(0, 1)) {
      it(s"drains an accepted row with AW stalled and isolates B error request=$failedRequest") {
        simulate(new AxiWritePipeline) { d =>
          d.io.request.valid.poke(false); d.io.request.bits.address.poke(0x1000); d.io.request.bits.beats.poke(1)
          d.io.data.valid.poke(false); d.io.data.bits.data.poke(0x12345678L); d.io.data.bits.strb.poke(15)
          d.io.axiAw.ready.poke(true); d.io.axiW.ready.poke(true); d.io.axiB.valid.poke(false)
          d.io.axiB.bits.poke(0.U.asTypeOf(new Axi4WriteResponse))
          def acceptRow(address: Int): Unit = {
            d.io.request.bits.address.poke(address); d.io.request.valid.poke(true)
            d.io.request.ready.expect(true); d.clock.step(); d.io.request.valid.poke(false)
          }
          def sendWord(): Unit = {
            d.io.data.valid.poke(true); d.io.axiW.valid.expect(true); d.io.axiW.bits.last.expect(true)
            d.clock.step(); d.io.data.valid.poke(false); d.io.done.expect(false)
          }
          acceptRow(0x1000); d.clock.step(); sendWord()
          acceptRow(0x1800); d.io.axiAw.ready.poke(false)
          d.io.axiAw.valid.expect(true); d.io.axiAw.bits.addr.expect(0x1800)
          d.io.axiB.valid.poke(true); d.io.axiB.bits.resp.poke(if(failedRequest==0)2 else 0)
          d.io.axiB.ready.expect(true); d.clock.step(); d.io.axiB.valid.poke(false)
          d.io.done.expect(true); d.io.error.expect(failedRequest==0)
          for (_ <- 0 until 3) {
            d.io.axiAw.valid.expect(true); d.io.axiAw.bits.addr.expect(0x1800)
            d.io.axiAw.bits.len.expect(0); d.io.request.ready.expect(false); d.clock.step()
          }
          d.io.done.expect(false); d.io.axiAw.ready.poke(true); d.clock.step(); sendWord()
          if(failedRequest==0)d.io.request.ready.expect(false)
          d.io.axiB.valid.poke(true); d.io.axiB.bits.resp.poke(if(failedRequest==1)2 else 0)
          d.clock.step(); d.io.axiB.valid.poke(false)
          d.io.done.expect(true); d.io.error.expect(failedRequest==1)
          d.clock.step(2); d.io.done.expect(false); d.io.request.ready.expect(true)
          acceptRow(0x2000); d.clock.step(); sendWord()
          d.io.axiB.bits.resp.poke(0); d.io.axiB.valid.poke(true); d.clock.step()
          d.io.axiB.valid.poke(false); d.io.done.expect(true); d.io.error.expect(false)
          d.clock.step(); d.io.done.expect(false)
        }
      }
    }
  }
}
