package cpu

import chisel3.simulator.scalatest.ChiselSim
import org.scalatest.funspec.AnyFunSpec

class PipelineControlSpec extends AnyFunSpec with ChiselSim {
  private def defaults(dut: PipelineControl): Unit = {
    dut.io.exRs1.poke(0)
    dut.io.exRs2.poke(0)
    dut.io.exRs1Used.poke(false)
    dut.io.exRs2Used.poke(false)
    dut.io.exMemValid.poke(false)
    dut.io.exMemRegWrite.poke(false)
    dut.io.exMemResultReady.poke(false)
    dut.io.exMemRd.poke(0)
    dut.io.memWbValid.poke(false)
    dut.io.memWbRegWrite.poke(false)
    dut.io.memWbRd.poke(0)
    dut.io.idRs1.poke(0)
    dut.io.idRs2.poke(0)
    dut.io.idRs1Used.poke(false)
    dut.io.idRs2Used.poke(false)
    dut.io.idExValid.poke(false)
    dut.io.idExMemRead.poke(false)
    dut.io.idExRd.poke(0)
    dut.io.resetActive.poke(false)
    dut.io.trap.poke(false)
    dut.io.redirect.poke(false)
    dut.io.memoryWait.poke(false)
  }

  describe("PipelineControl") {
    it("forwards the newest available result and never forwards x0") {
      simulate(new PipelineControl) { dut =>
        defaults(dut)
        dut.io.exRs1.poke(5)
        dut.io.exRs1Used.poke(true)
        dut.io.exMemValid.poke(true)
        dut.io.exMemRegWrite.poke(true)
        dut.io.exMemResultReady.poke(true)
        dut.io.exMemRd.poke(5)
        dut.io.memWbValid.poke(true)
        dut.io.memWbRegWrite.poke(true)
        dut.io.memWbRd.poke(5)
        dut.io.forwardRs1.expect(ForwardSel.ExMem)

        dut.io.exMemRd.poke(0)
        dut.io.memWbRd.poke(5)
        dut.io.forwardRs1.expect(ForwardSel.MemWb)

        dut.io.memWbRd.poke(0)
        dut.io.forwardRs1.expect(ForwardSel.Reg)
        dut.io.exRs1Used.poke(false)
        dut.io.exMemRd.poke(5)
        dut.io.forwardRs1.expect(ForwardSel.Reg)
      }
    }

    it("forwards each source independently") {
      simulate(new PipelineControl) { dut =>
        defaults(dut)
        dut.io.exRs2.poke(9)
        dut.io.exRs2Used.poke(true)
        dut.io.memWbValid.poke(true)
        dut.io.memWbRegWrite.poke(true)
        dut.io.memWbRd.poke(9)
        dut.io.forwardRs1.expect(ForwardSel.Reg)
        dut.io.forwardRs2.expect(ForwardSel.MemWb)
      }
    }

    it("stalls only for a used source that depends on an active load") {
      simulate(new PipelineControl) { dut =>
        defaults(dut)
        dut.io.idExValid.poke(true)
        dut.io.idExMemRead.poke(true)
        dut.io.idExRd.poke(4)
        dut.io.idRs1.poke(4)
        dut.io.idRs1Used.poke(true)
        dut.io.loadUseStall.expect(true)
        dut.io.action.expect(PipelineAction.LoadUseStall)

        dut.io.idRs1Used.poke(false)
        dut.io.loadUseStall.expect(false)
        dut.io.idRs2.poke(4)
        dut.io.idRs2Used.poke(true)
        dut.io.loadUseStall.expect(true)

        dut.io.idExRd.poke(0)
        dut.io.loadUseStall.expect(false)
      }
    }

    it("applies reset trap redirect memory and hazard priority") {
      simulate(new PipelineControl) { dut =>
        defaults(dut)
        dut.io.memoryWait.poke(true)
        dut.io.redirect.poke(true)
        dut.io.trap.poke(true)
        dut.io.resetActive.poke(true)
        dut.io.action.expect(PipelineAction.Reset)

        dut.io.resetActive.poke(false)
        dut.io.action.expect(PipelineAction.Trap)
        dut.io.trap.poke(false)
        dut.io.action.expect(PipelineAction.Redirect)
        dut.io.redirect.poke(false)
        dut.io.action.expect(PipelineAction.MemoryWait)
        dut.io.memoryWait.poke(false)
        dut.io.action.expect(PipelineAction.Advance)
      }
    }
  }
}
