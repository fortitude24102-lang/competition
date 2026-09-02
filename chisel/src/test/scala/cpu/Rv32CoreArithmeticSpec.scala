package cpu

import org.scalatest.funspec.AnyFunSpec
import org.scalatest.matchers.should.Matchers
import testutil.StableChiselSim

class Rv32CoreArithmeticSpec extends AnyFunSpec with StableChiselSim with Matchers {
  describe("Rv32Core arithmetic pipeline") {
    it("commits dependent ALU instructions with EX/MEM and MEM/WB forwarding") {
      val memory = new TestMemory(Seq(
        BigInt("00500093", 16), // addi x1, x0, 5
        BigInt("00308113", 16), // addi x2, x1, 3
        BigInt("001101b3", 16), // add  x3, x2, x1
        BigInt("40118233", 16), // sub  x4, x3, x1
        BigInt("00221293", 16), // slli x5, x4, 2
        BigInt("0282a313", 16), // slti x6, x5, 40
        BigInt("0042c3b3", 16), // xor  x7, x5, x4
        BigInt("00000013", 16),
        BigInt("00000013", 16),
        BigInt("00000013", 16)
      ))

      simulate(new Rv32Core()) { dut =>
        dut.io.timerInterrupt.poke(false)
        dut.io.imem.req.ready.poke(true)
        dut.io.imem.resp.valid.poke(false)
        dut.io.imem.resp.bits.rdata.poke(0)
        dut.io.imem.resp.bits.error.poke(false)
        dut.io.dmem.req.ready.poke(true)
        dut.io.dmem.resp.valid.poke(false)
        dut.io.dmem.resp.bits.rdata.poke(0)
        dut.io.dmem.resp.bits.error.poke(false)

        var pendingResponse = Option.empty[BigInt]
        var writes = Vector.empty[(Int, BigInt)]

        for (_ <- 0 until 100 if writes.length < 7) {
          pendingResponse match {
            case Some(address) =>
              dut.io.imem.resp.valid.poke(true)
              dut.io.imem.resp.bits.rdata.poke(memory.readWord(address))
            case None =>
              dut.io.imem.resp.valid.poke(false)
          }

          val responseFires = pendingResponse.nonEmpty && dut.io.imem.resp.ready.peek().litToBoolean
          val requestFires = dut.io.imem.req.valid.peek().litToBoolean
          val requestAddress = if (requestFires) Some(dut.io.imem.req.bits.addr.peek().litValue) else None

          if (dut.io.commit.valid.peek().litToBoolean && dut.io.commit.writeEnable.peek().litToBoolean) {
            writes :+= dut.io.commit.rd.peek().litValue.toInt -> dut.io.commit.data.peek().litValue
          }

          dut.clock.step()

          if (responseFires) pendingResponse = None
          requestAddress.foreach(address => pendingResponse = Some(address))
        }

        writes shouldBe Vector(
          1 -> BigInt(5),
          2 -> BigInt(8),
          3 -> BigInt(13),
          4 -> BigInt(8),
          5 -> BigInt(32),
          6 -> BigInt(1),
          7 -> BigInt(40)
        )
        dut.io.halted.expect(false)
        dut.io.trap.valid.expect(false)
      }
    }
  }
}
