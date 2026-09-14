package gpu

import chisel3._
import org.scalatest.funspec.AnyFunSpec
import testutil.StableChiselSim

class Efinix2dGpuTopSpec extends AnyFunSpec with StableChiselSim {
  describe("Efinix2dGpuTop") {
    it("keeps scanout off until software requests the first frame swap") {
      simulate(new Efinix2dGpuTop) { dut =>
        dut.io.apb.paddr.poke(0.U)
        dut.io.apb.psel.poke(false.B)
        dut.io.apb.penable.poke(false.B)
        dut.io.apb.pwrite.poke(false.B)
        dut.io.apb.pwdata.poke(0.U)
        dut.io.vblank.poke(false.B)
        dut.io.scanoutLevel.poke(0.U)
        dut.io.displayReady.poke(true.B)
        dut.io.axi.aw.ready.poke(true.B)
        dut.io.axi.w.ready.poke(true.B)
        dut.io.axi.b.valid.poke(false.B)
        dut.io.axi.b.bits.poke(0.U.asTypeOf(new Axi4WriteResponse))
        dut.io.axi.ar.ready.poke(true.B)
        dut.io.axi.r.valid.poke(false.B)
        dut.io.axi.r.bits.poke(0.U.asTypeOf(new Axi4ReadData))

        dut.reset.poke(true.B)
        dut.clock.step(2)
        dut.reset.poke(false.B)
        for (_ <- 0 until 12) {
          dut.io.axi.ar.valid.expect(false.B)
          dut.clock.step()
        }
      }
    }
  }
}
