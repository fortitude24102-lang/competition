package cpu

import org.scalatest.funspec.AnyFunSpec
import org.scalatest.matchers.should.Matchers
import testutil.StableChiselSim

class Rv32CoreCsrSpec extends AnyFunSpec with StableChiselSim with Matchers {
  private case class TrapEvent(interrupt: Boolean, cause: Int, pc: BigInt)
  private case class RunResult(writes: Vector[(Int, BigInt)], traps: Vector[TrapEvent], halted: Boolean)

  private def run(words: Seq[BigInt], timerInterrupt: Boolean = false): RunResult = {
    val memory = new TestMemory(words)
    var result = RunResult(Vector.empty, Vector.empty, halted = false)

    simulate(new Rv32Core(enableMachineMode = true, haltOnEbreak = true)) { dut =>
      dut.io.timerInterrupt.poke(timerInterrupt)
      dut.io.imem.req.ready.poke(true)
      dut.io.imem.resp.valid.poke(false)
      dut.io.imem.resp.bits.rdata.poke(0)
      dut.io.imem.resp.bits.error.poke(false)
      dut.io.dmem.req.ready.poke(true)
      dut.io.dmem.resp.valid.poke(false)
      dut.io.dmem.resp.bits.rdata.poke(0)
      dut.io.dmem.resp.bits.error.poke(false)

      var fetchResponse = Option.empty[BigInt]
      var writes = Vector.empty[(Int, BigInt)]
      var traps = Vector.empty[TrapEvent]
      var haltedCycles = 0

      for (_ <- 0 until 300 if haltedCycles < 2) {
        fetchResponse match {
          case Some(address) =>
            dut.io.imem.resp.valid.poke(true)
            dut.io.imem.resp.bits.rdata.poke(memory.readWord(address))
          case None =>
            dut.io.imem.resp.valid.poke(false)
        }

        val responseFires = fetchResponse.nonEmpty && dut.io.imem.resp.ready.peek().litToBoolean
        val requestFires = dut.io.imem.req.valid.peek().litToBoolean
        val requestAddress = if (requestFires) Some(dut.io.imem.req.bits.addr.peek().litValue) else None

        if (dut.io.commit.valid.peek().litToBoolean && dut.io.commit.writeEnable.peek().litToBoolean) {
          writes :+= dut.io.commit.rd.peek().litValue.toInt -> dut.io.commit.data.peek().litValue
        }
        if (dut.io.trap.valid.peek().litToBoolean) {
          traps :+= TrapEvent(
            dut.io.trap.interrupt.peek().litToBoolean,
            dut.io.trap.cause.peek().litValue.toInt,
            dut.io.trap.pc.peek().litValue
          )
        }
        if (dut.io.halted.peek().litToBoolean) haltedCycles += 1

        dut.clock.step()

        if (responseFires) fetchResponse = None
        requestAddress.foreach(address => fetchResponse = Some(address))
      }

      result = RunResult(writes, traps, dut.io.halted.peek().litToBoolean)
    }
    result
  }

  describe("Rv32Core machine-mode CSR path") {
    it("enters mtvec on ECALL, records state, returns with MRET, and resumes") {
      val program = Seq(
        BigInt("04000093", 16), // addi x1, x0, 0x40
        BigInt("30509073", 16), // csrw mtvec, x1
        BigInt("00000073", 16), // ecall
        BigInt("00400213", 16), // addi x4, x0, 4
        BigInt("00100073", 16)  // ebreak
      ) ++ Seq.fill(11)(BigInt("00000013", 16)) ++ Seq(
        BigInt("34202173", 16), // csrr x2, mcause
        BigInt("341021f3", 16), // csrr x3, mepc
        BigInt("00418193", 16), // addi x3, x3, 4
        BigInt("34119073", 16), // csrw mepc, x3
        BigInt("30200073", 16)  // mret
      )

      val result = run(program)

      result.traps shouldBe Vector(
        TrapEvent(interrupt = false, cause = 11, pc = 8),
        TrapEvent(interrupt = false, cause = 3, pc = 16)
      )
      result.writes should contain inOrderOnly (
        1 -> BigInt(64),
        2 -> BigInt(11),
        3 -> BigInt(8),
        3 -> BigInt(12),
        4 -> BigInt(4)
      )
      result.halted shouldBe true
    }

    it("executes back-to-back CSR read-modify-write operations in program order") {
      val result = run(Seq(
        BigInt("00500093", 16), // addi x1, x0, 5
        BigInt("34009173", 16), // csrrw x2, mscratch, x1
        BigInt("3400a1f3", 16), // csrrs x3, mscratch, x1
        BigInt("3400f273", 16), // csrci x4, mscratch, 1
        BigInt("340022f3", 16), // csrr x5, mscratch
        BigInt("00100073", 16)  // ebreak
      ))

      result.writes should contain inOrderOnly (
        1 -> BigInt(5),
        2 -> BigInt(0),
        3 -> BigInt(5),
        4 -> BigInt(5),
        5 -> BigInt(4)
      )
      result.halted shouldBe true
    }

    it("takes a machine timer interrupt between instructions and preserves precise retirement") {
      val program = Seq(
        BigInt("04000093", 16), // addi x1, x0, 0x40
        BigInt("30509073", 16), // csrw mtvec, x1
        BigInt("08000093", 16), // addi x1, x0, 0x80
        BigInt("30409073", 16), // csrw mie, x1
        BigInt("00500293", 16), // addi x5, x0, 5
        BigInt("30046073", 16), // csrsi mstatus, 8
        BigInt("00600313", 16), // addi x6, x0, 6 (must not retire before the handler)
        BigInt("0000006f", 16)  // jal x0, 0
      ) ++ Seq.fill(8)(BigInt("00000013", 16)) ++ Seq(
        BigInt("34202173", 16), // csrr x2, mcause
        BigInt("341021f3", 16), // csrr x3, mepc
        BigInt("00700393", 16), // addi x7, x0, 7
        BigInt("00100073", 16)  // ebreak
      )

      val result = run(program, timerInterrupt = true)

      result.traps shouldBe Vector(
        TrapEvent(interrupt = true, cause = 7, pc = 24),
        TrapEvent(interrupt = false, cause = 3, pc = 76)
      )
      result.writes should contain inOrderOnly (
        1 -> BigInt(64),
        1 -> BigInt(128),
        5 -> BigInt(5),
        2 -> BigInt("80000007", 16),
        3 -> BigInt(24),
        7 -> BigInt(7)
      )
      result.writes.map(_._1) should not contain 6
      result.halted shouldBe true
    }
  }
}
