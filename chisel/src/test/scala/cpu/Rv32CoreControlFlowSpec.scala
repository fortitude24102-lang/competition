package cpu

import org.scalatest.funspec.AnyFunSpec
import org.scalatest.matchers.should.Matchers
import testutil.StableChiselSim

class Rv32CoreControlFlowSpec extends AnyFunSpec with StableChiselSim with Matchers {
  describe("Rv32Core control flow") {
    it("redirects taken branches and jumps without committing wrong-path writes") {
      val memory = new TestMemory(Seq(
        BigInt("00100093", 16), // 00: addi x1, x0, 1
        BigInt("00100113", 16), // 04: addi x2, x0, 1
        BigInt("00208463", 16), // 08: beq  x1, x2, 8
        BigInt("06300193", 16), // 12: wrong path: addi x3, x0, 99
        BigInt("00209463", 16), // 16: bne  x1, x2, 8 (not taken)
        BigInt("00300193", 16), // 20: addi x3, x0, 3
        BigInt("0080026f", 16), // 24: jal  x4, 8
        BigInt("06300293", 16), // 28: wrong path: addi x5, x0, 99
        BigInt("00500293", 16), // 32: addi x5, x0, 5
        BigInt("00000317", 16), // 36: auipc x6, 0
        BigInt("01030313", 16), // 40: addi x6, x6, 16
        BigInt("000303e7", 16), // 44: jalr x7, x6, 0
        BigInt("06300413", 16), // 48: wrong path: addi x8, x0, 99
        BigInt("00800413", 16), // 52: addi x8, x0, 8
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

        for (_ <- 0 until 180 if writes.length < 9) {
          pendingResponse match {
            case Some(address) =>
              dut.io.imem.resp.valid.poke(true)
              dut.io.imem.resp.bits.rdata.poke(memory.readWord(address))
            case None => dut.io.imem.resp.valid.poke(false)
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
          1 -> BigInt(1),
          2 -> BigInt(1),
          3 -> BigInt(3),
          4 -> BigInt(28),
          5 -> BigInt(5),
          6 -> BigInt(36),
          6 -> BigInt(52),
          7 -> BigInt(48),
          8 -> BigInt(8)
        )
      }
    }
  }
}
