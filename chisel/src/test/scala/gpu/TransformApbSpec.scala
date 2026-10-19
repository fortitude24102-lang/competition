package gpu

import chisel3._
import org.scalatest.funspec.AnyFunSpec
import org.scalatest.matchers.should.Matchers
import testutil.StableChiselSim

class TransformApbSpec extends AnyFunSpec with StableChiselSim with Matchers {
  private def init(d: GpuApbRegs): Unit = {
    d.io.psel.poke(false);d.io.penable.poke(false);d.io.pwrite.poke(false)
    d.io.paddr.poke(0);d.io.pwdata.poke(0);d.io.command.ready.poke(true)
    d.io.queueLevel.poke(0);d.io.queueHighWater.poke(0);d.io.queueFull.poke(false)
    d.io.queueEmpty.poke(true);d.io.engineBusy.poke(false);d.io.irqPending.poke(false)
    d.io.lastDoneTag.poke(0);d.io.lastError.poke(0)
    d.io.frontBuffer.poke(GpuMemoryMap.FramebufferA);d.io.backBuffer.poke(GpuMemoryMap.FramebufferB)
    d.io.perfCycles.poke(0);d.io.perfPixels.poke(0);d.io.perfReadBytes.poke(0)
    d.io.perfWriteBytes.poke(0);d.io.perfStalls.poke(0);d.io.perfUnderflows.poke(0)
    d.io.perfRenderGrants.poke(0);d.io.perfScanoutGrants.poke(0);d.io.perfCacheBytes.poke(0)
    d.io.textureCacheValid.poke(false);d.io.textureCacheBusy.poke(false);d.io.textureCacheError.poke(false)
    d.reset.poke(true);d.clock.step(2);d.reset.poke(false)
  }

  private def transfer(d:GpuApbRegs, offset:Int, write:Boolean, value:BigInt=0,
    check:()=>Unit=()=>()):(BigInt,Boolean) = {
    d.io.paddr.poke(offset);d.io.pwrite.poke(write);d.io.pwdata.poke(value)
    d.io.psel.poke(true);d.io.penable.poke(false);d.clock.step()
    d.io.penable.poke(true);d.io.pready.expect(true);check()
    val result=d.io.prdata.peek().litValue -> d.io.pslverror.peek().litToBoolean
    d.clock.step();d.io.psel.poke(false);d.io.penable.poke(false);result
  }

  describe("optional Transform APB ABI") {
    it("advertises and latches source dimensions without changing output size or tag") {
      simulate(new GpuApbRegs(instancePresent=true,frameListPresent=true,transformPresent=true)) { d =>
        init(d)
        transfer(d,0x08,false) shouldBe (BigInt(0x2c020),false)
        transfer(d,0xa8,true,0x00030005)._2 shouldBe false
        transfer(d,0xa8,false) shouldBe (BigInt(0x00030005),false)
        transfer(d,0x10,true,7);transfer(d,0x1c,true,0x00070009);transfer(d,0x30,true,42)
        transfer(d,0x0c,true,1,()=>{
          d.io.command.valid.expect(true);d.io.command.bits.op.expect(7)
          d.io.command.bits.srcWidthPixels.expect(5);d.io.command.bits.srcHeightPixels.expect(3)
          d.io.command.bits.widthPixels.expect(9);d.io.command.bits.heightPixels.expect(7)
          d.io.command.bits.tag.expect(42)
        })._2 shouldBe false
        d.io.command.valid.expect(false)
      }
    }
    it("leaves the default build capability off and rejects the optional offset") {
      simulate(new GpuApbRegs) { d =>
        init(d);transfer(d,0x08,false) shouldBe (BigInt(0x20),false)
        transfer(d,0xa8,true,0x00030005)._2 shouldBe true
        transfer(d,0xa8,false) shouldBe (BigInt(0),true)
        transfer(d,0x10,true,GpuOpcode.Fill)
        transfer(d,0x0c,true,1,()=>{
          d.io.command.bits.srcWidthPixels.expect(0);d.io.command.bits.srcHeightPixels.expect(0)
          d.io.command.bits.op.expect(GpuOpcode.Fill)
        })._2 shouldBe false
      }
    }
  }
}
