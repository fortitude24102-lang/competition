package cpu

import chisel3.simulator.scalatest.ChiselSim
import org.scalatest.funspec.AnyFunSpec
import org.scalatest.matchers.should.Matchers

class Rv32CoreTrapSpec extends AnyFunSpec with ChiselSim with Matchers {
  private case class TrapEvent(cause: Int, pc: BigInt, inst: BigInt)
  private case class RunResult(
    traps: Vector[TrapEvent],
    writes: Vector[(Int, BigInt)],
    dataRequests: Vector[(BigInt, Boolean)],
    halted: Boolean,
    resetClearedHalt: Boolean
  )

  private def run(
    words: Seq[BigInt],
    instructionErrorAddresses: Set[BigInt] = Set.empty,
    dataError: Boolean = false,
    dataResponseDelay: Int = 1,
    dataReadValue: BigInt = 0,
    resetAfterHalt: Boolean = false
  ): RunResult = {
    val instructions = new TestMemory(words)
    var result = RunResult(Vector.empty, Vector.empty, Vector.empty, halted = false, resetClearedHalt = false)

    simulate(new Rv32Core()) { dut =>
      dut.io.imem.req.ready.poke(true)
      dut.io.imem.resp.valid.poke(false)
      dut.io.imem.resp.bits.rdata.poke(0)
      dut.io.imem.resp.bits.error.poke(false)
      dut.io.dmem.req.ready.poke(true)
      dut.io.dmem.resp.valid.poke(false)
      dut.io.dmem.resp.bits.rdata.poke(0)
      dut.io.dmem.resp.bits.error.poke(false)
      dut.reset.poke(false)

      var fetchResponse = Option.empty[BigInt]
      var dataResponse = Option.empty[Int]
      var traps = Vector.empty[TrapEvent]
      var writes = Vector.empty[(Int, BigInt)]
      var requests = Vector.empty[(BigInt, Boolean)]
      var everHalted = false
      var haltedCycles = 0
      var resetClearedHalt = false
      var active = true

      for (_ <- 0 until 120 if active) {
        fetchResponse match {
          case Some(address) =>
            dut.io.imem.resp.valid.poke(true)
            dut.io.imem.resp.bits.rdata.poke(instructions.readWord(address))
            dut.io.imem.resp.bits.error.poke(instructionErrorAddresses.contains(address))
          case None =>
            dut.io.imem.resp.valid.poke(false)
            dut.io.imem.resp.bits.error.poke(false)
        }
        dataResponse match {
          case Some(0) =>
            dut.io.dmem.resp.valid.poke(true)
            dut.io.dmem.resp.bits.rdata.poke(dataReadValue)
            dut.io.dmem.resp.bits.error.poke(dataError)
          case _ =>
            dut.io.dmem.resp.valid.poke(false)
            dut.io.dmem.resp.bits.error.poke(false)
        }

        val haltedNow = dut.io.halted.peek().litToBoolean
        everHalted ||= haltedNow
        if (haltedNow) haltedCycles += 1
        val applyReset = resetAfterHalt && haltedCycles == 3
        dut.reset.poke(applyReset)

        val fetchResponseFires = fetchResponse.nonEmpty && dut.io.imem.resp.ready.peek().litToBoolean
        val fetchRequestFires = dut.io.imem.req.valid.peek().litToBoolean
        val fetchAddress = if (fetchRequestFires) Some(dut.io.imem.req.bits.addr.peek().litValue) else None
        val dataResponseFires = dataResponse.contains(0) && dut.io.dmem.resp.ready.peek().litToBoolean
        val dataRequestFires = dut.io.dmem.req.valid.peek().litToBoolean

        if (dataRequestFires) {
          requests :+= dut.io.dmem.req.bits.addr.peek().litValue -> dut.io.dmem.req.bits.write.peek().litToBoolean
        }
        if (dut.io.commit.valid.peek().litToBoolean && dut.io.commit.writeEnable.peek().litToBoolean) {
          writes :+= dut.io.commit.rd.peek().litValue.toInt -> dut.io.commit.data.peek().litValue
        }
        if (dut.io.trap.valid.peek().litToBoolean) {
          traps :+= TrapEvent(
            dut.io.trap.cause.peek().litValue.toInt,
            dut.io.trap.pc.peek().litValue,
            dut.io.trap.inst.peek().litValue
          )
        }

        dut.clock.step()

        if (fetchResponseFires) fetchResponse = None
        fetchAddress.foreach(address => fetchResponse = Some(address))
        dataResponse = if (dataResponseFires) None else dataResponse.map(delay => math.max(0, delay - 1))
        if (dataRequestFires) dataResponse = Some(dataResponseDelay)
        if (applyReset) {
          resetClearedHalt = !dut.io.halted.peek().litToBoolean
          active = false
        } else if (!resetAfterHalt && haltedCycles >= 3) {
          active = false
        }
      }

      result = RunResult(traps, writes, requests, everHalted, resetClearedHalt)
    }
    result
  }

  describe("Rv32Core precise traps") {
    it("reports an illegal instruction after older work and suppresses younger work") {
      val result = run(Seq(
        BigInt("00100093", 16),
        BigInt("ffffffff", 16),
        BigInt("00200113", 16)
      ), resetAfterHalt = true)

      result.traps shouldBe Vector(TrapEvent(2, 4, BigInt("ffffffff", 16)))
      result.writes shouldBe Vector(1 -> BigInt(1))
      result.halted shouldBe true
      result.resetClearedHalt shouldBe true
    }

    it("reports ECALL and EBREAK with their architectural causes") {
      val ecall = run(Seq(BigInt("00000073", 16)))
      val ebreak = run(Seq(BigInt("00100073", 16)))

      ecall.traps shouldBe Vector(TrapEvent(11, 0, BigInt("00000073", 16)))
      ebreak.traps shouldBe Vector(TrapEvent(3, 0, BigInt("00100073", 16)))
      ecall.halted shouldBe true
      ebreak.halted shouldBe true
    }

    it("reports an instruction access fault at the response PC") {
      val result = run(
        Seq(BigInt("00100093", 16), BigInt("00000013", 16), BigInt("00200113", 16)),
        instructionErrorAddresses = Set(BigInt(4))
      )

      result.traps shouldBe Vector(TrapEvent(1, 4, BigInt("00000013", 16)))
      result.writes shouldBe Vector(1 -> BigInt(1))
    }

    it("distinguishes load and store access faults") {
      val load = run(Seq(
        BigInt("10000093", 16),
        BigInt("0000a103", 16),
        BigInt("00300193", 16)
      ), dataError = true)
      val store = run(Seq(
        BigInt("10000093", 16),
        BigInt("00700113", 16),
        BigInt("0020a023", 16),
        BigInt("00300193", 16)
      ), dataError = true)

      load.traps shouldBe Vector(TrapEvent(5, 4, BigInt("0000a103", 16)))
      load.writes shouldBe Vector(1 -> BigInt(256))
      store.traps shouldBe Vector(TrapEvent(7, 8, BigInt("0020a023", 16)))
      store.writes shouldBe Vector(1 -> BigInt(256), 2 -> BigInt(7))
      load.dataRequests shouldBe Vector(BigInt(256) -> false)
      store.dataRequests shouldBe Vector(BigInt(256) -> true)
    }

    it("rejects a taken branch target that is not four-byte aligned") {
      val result = run(Seq(BigInt("002000ef", 16), BigInt("00100113", 16)))

      result.traps shouldBe Vector(TrapEvent(0, 0, BigInt("002000ef", 16)))
      result.writes shouldBe empty
    }

    it("reports misaligned memory accesses without issuing a store request") {
      val load = run(Seq(BigInt("10100093", 16), BigInt("00009103", 16)))
      val store = run(Seq(BigInt("10200093", 16), BigInt("0000a023", 16)))

      load.traps shouldBe Vector(TrapEvent(4, 4, BigInt("00009103", 16)))
      store.traps shouldBe Vector(TrapEvent(6, 4, BigInt("0000a023", 16)))
      load.dataRequests shouldBe empty
      store.dataRequests shouldBe empty
    }

    it("waits for an older delayed load before trapping a younger instruction") {
      val result = run(Seq(
        BigInt("10000093", 16),
        BigInt("0000a103", 16),
        BigInt("ffffffff", 16),
        BigInt("00300193", 16)
      ), dataResponseDelay = 5, dataReadValue = 42)

      result.writes shouldBe Vector(1 -> BigInt(256), 2 -> BigInt(42))
      result.traps shouldBe Vector(TrapEvent(2, 8, BigInt("ffffffff", 16)))
    }
  }
}
