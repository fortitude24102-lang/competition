package cpu

import java.nio.file.{Files, Paths}
import org.scalatest.funspec.AnyFunSpec
import org.scalatest.matchers.should.Matchers
import testutil.StableChiselSim

class Rv32UiSpec extends AnyFunSpec with StableChiselSim with Matchers {
  private val tests = Seq(
    "add", "addi", "and", "andi", "auipc", "beq", "bge", "bgeu", "blt", "bltu", "bne",
    "jal", "jalr", "lb", "lbu", "lh", "lhu", "lui", "lw", "or", "ori", "sb", "sh",
    "sll", "slli", "slt", "slti", "sltiu", "sltu", "sra", "srai", "srl", "srli",
    "sub", "sw", "xor", "xori"
  )

  describe("Rv32Core upstream rv32ui compatibility") {
    it("passes the selected integer ISA binaries") {
      val buildDirectory = Paths.get(
        sys.env.getOrElse("RISCV_TESTS_BUILD", "/mnt/d/Chisel-environment/riscv-tests-build/rv32ui")
      )
      val binaries = tests.map(name => name -> Files.readAllBytes(buildDirectory.resolve(s"$name.bin")))

      simulate(new Rv32Core()) { dut =>
        dut.io.imem.resp.bits.error.poke(false)
        dut.io.dmem.resp.bits.error.poke(false)

        for ((testName, binary) <- binaries) {
          val memory = Array.fill(0x20000)(0)
          binary.indices.foreach(index => memory(index) = binary(index) & 0xff)

          def readWord(address: Int): BigInt = {
            val base = address & ~3
            (0 until 4).foldLeft(BigInt(0)) { (word, lane) =>
              word | (BigInt(memory(base + lane)) << (8 * lane))
            }
          }

          dut.reset.poke(true)
          dut.io.imem.req.ready.poke(false)
          dut.io.imem.resp.valid.poke(false)
          dut.io.dmem.req.ready.poke(false)
          dut.io.dmem.resp.valid.poke(false)
          dut.clock.step(2)
          dut.reset.poke(false)

          var fetchResponse = Option.empty[(Int, Int)]
          var dataResponse = Option.empty[(Int, BigInt)]
          var trapCause = Option.empty[Int]

          for (cycle <- 0 until 12000 if trapCause.isEmpty) {
            val fetchReady = cycle % 4 != 1
            val dataReady = cycle % 3 != 0
            dut.io.imem.req.ready.poke(fetchReady)
            dut.io.dmem.req.ready.poke(dataReady)

            fetchResponse match {
              case Some((0, address)) =>
                dut.io.imem.resp.valid.poke(true)
                dut.io.imem.resp.bits.rdata.poke(readWord(address))
              case _ => dut.io.imem.resp.valid.poke(false)
            }
            dataResponse match {
              case Some((0, word)) =>
                dut.io.dmem.resp.valid.poke(true)
                dut.io.dmem.resp.bits.rdata.poke(word)
              case _ => dut.io.dmem.resp.valid.poke(false)
            }

            val fetchResponseFires = fetchResponse.exists(_._1 == 0) && dut.io.imem.resp.ready.peek().litToBoolean
            val fetchRequestFires = fetchReady && dut.io.imem.req.valid.peek().litToBoolean
            val fetchAddress = if (fetchRequestFires) Some(dut.io.imem.req.bits.addr.peek().litValue.toInt) else None
            val dataResponseFires = dataResponse.exists(_._1 == 0) && dut.io.dmem.resp.ready.peek().litToBoolean
            val dataRequestFires = dataReady && dut.io.dmem.req.valid.peek().litToBoolean

            val acceptedDataRequest = if (dataRequestFires) {
              val address = dut.io.dmem.req.bits.addr.peek().litValue.toInt
              val base = address & ~3
              if (dut.io.dmem.req.bits.write.peek().litToBoolean) {
                val writeData = dut.io.dmem.req.bits.wdata.peek().litValue
                val writeStrobe = dut.io.dmem.req.bits.wstrb.peek().litValue.toInt
                for (lane <- 0 until 4 if (writeStrobe & (1 << lane)) != 0) {
                  memory(base + lane) = ((writeData >> (8 * lane)) & 0xff).toInt
                }
              }
              Some(2 -> readWord(base))
            } else None

            if (dut.io.trap.valid.peek().litToBoolean) {
              trapCause = Some(dut.io.trap.cause.peek().litValue.toInt)
            }

            dut.clock.step()

            if (fetchResponseFires) fetchResponse = None
            fetchAddress.foreach(address => fetchResponse = Some(0 -> address))
            dataResponse = if (dataResponseFires) None else dataResponse.map { case (delay, word) =>
              math.max(0, delay - 1) -> word
            }
            acceptedDataRequest.foreach(response => dataResponse = Some(response))
          }

          withClue(s"$testName trap: ") { trapCause shouldBe Some(3) }
          withClue(s"$testName signature: ") { readWord(0x10000) shouldBe BigInt(1) }
        }
      }
    }
  }
}
