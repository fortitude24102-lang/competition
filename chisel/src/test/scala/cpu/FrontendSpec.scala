package cpu

import org.scalatest.funspec.AnyFunSpec
import testutil.StableChiselSim

class FrontendSpec extends AnyFunSpec with StableChiselSim {
  private def defaults(dut: Frontend): Unit = {
    dut.io.imem.req.ready.poke(false)
    dut.io.imem.resp.valid.poke(false)
    dut.io.imem.resp.bits.rdata.poke(0)
    dut.io.imem.resp.bits.error.poke(false)
    dut.io.output.ready.poke(false)
    dut.io.redirectValid.poke(false)
    dut.io.redirectPc.poke(0)
  }

  private def acceptRequest(dut: Frontend, expectedAddress: BigInt): Unit = {
    dut.io.imem.req.valid.expect(true)
    dut.io.imem.req.bits.addr.expect(expectedAddress)
    dut.io.imem.req.bits.write.expect(false)
    dut.io.imem.req.bits.size.expect(2)
    dut.io.imem.req.ready.poke(true)
    dut.clock.step()
    dut.io.imem.req.ready.poke(false)
  }

  private def returnInstruction(dut: Frontend, instruction: BigInt, error: Boolean = false): Unit = {
    dut.io.imem.resp.bits.rdata.poke(instruction)
    dut.io.imem.resp.bits.error.poke(error)
    dut.io.imem.resp.valid.poke(true)
    dut.io.imem.resp.ready.expect(true)
    dut.clock.step()
    dut.io.imem.resp.valid.poke(false)
  }

  describe("Frontend") {
    it("issues sequential word requests with only one outstanding") {
      simulate(new Frontend()) { dut =>
        defaults(dut)
        acceptRequest(dut, 0)
        dut.io.imem.req.valid.expect(false)
        returnInstruction(dut, BigInt("00000013", 16))

        dut.io.output.valid.expect(true)
        dut.io.output.bits.pc.expect(0)
        dut.io.output.bits.inst.expect(BigInt("00000013", 16))
        acceptRequest(dut, 4)
      }
    }

    it("buffers two responses and applies downstream backpressure") {
      simulate(new Frontend()) { dut =>
        defaults(dut)
        acceptRequest(dut, 0)
        returnInstruction(dut, 0x13)
        acceptRequest(dut, 4)
        returnInstruction(dut, BigInt("00100093", 16))

        dut.io.imem.req.valid.expect(false)
        dut.io.output.valid.expect(true)
        dut.io.output.bits.pc.expect(0)
        dut.io.output.ready.poke(true)
        dut.clock.step()
        dut.io.output.bits.pc.expect(4)
        dut.io.output.bits.inst.expect(BigInt("00100093", 16))
      }
    }

    it("drops an old outstanding response after redirect") {
      simulate(new Frontend()) { dut =>
        defaults(dut)
        acceptRequest(dut, 0)

        dut.io.redirectPc.poke(0x100)
        dut.io.redirectValid.poke(true)
        dut.clock.step()
        dut.io.redirectValid.poke(false)

        returnInstruction(dut, BigInt("deadbeef", 16))
        dut.io.output.valid.expect(false)
        acceptRequest(dut, 0x100)
        returnInstruction(dut, BigInt("12345678", 16))

        dut.io.output.valid.expect(true)
        dut.io.output.bits.pc.expect(0x100)
        dut.io.output.bits.inst.expect(BigInt("12345678", 16))
      }
    }

    it("flushes queued wrong-path instructions on redirect") {
      simulate(new Frontend()) { dut =>
        defaults(dut)
        acceptRequest(dut, 0)
        returnInstruction(dut, 0x13)
        dut.io.output.valid.expect(true)

        dut.io.redirectPc.poke(0x80)
        dut.io.redirectValid.poke(true)
        dut.clock.step()
        dut.io.redirectValid.poke(false)
        dut.io.output.valid.expect(false)
        acceptRequest(dut, 0x80)
      }
    }
  }
}
