package cpu

import java.nio.file.{Files, Paths}
import org.scalatest.funspec.AnyFunSpec
import org.scalatest.matchers.should.Matchers
import testutil.StableChiselSim

class Rv32ProgramSpec extends AnyFunSpec with StableChiselSim with Matchers {
  describe("Rv32Core compiled program") {
    it("runs the RV32I smoke binary to its pass signature and EBREAK") {
      val binary = Files.readAllBytes(Paths.get("src/test/resources/rv32i/smoke.bin"))
      val memory = Array.fill(8192)(0)
      binary.indices.foreach(index => memory(index) = binary(index) & 0xff)

      def readWord(address: Int): BigInt = {
        val base = address & ~3
        (0 until 4).foldLeft(BigInt(0)) { (word, lane) =>
          word | (BigInt(memory(base + lane)) << (8 * lane))
        }
      }

      simulate(new Rv32Core()) { dut =>
        dut.io.timerInterrupt.poke(false)
        dut.io.imem.resp.valid.poke(false)
        dut.io.imem.resp.bits.rdata.poke(0)
        dut.io.imem.resp.bits.error.poke(false)
        dut.io.dmem.resp.valid.poke(false)
        dut.io.dmem.resp.bits.rdata.poke(0)
        dut.io.dmem.resp.bits.error.poke(false)

        var fetchResponse = Option.empty[(Int, Int)]
        var dataResponse = Option.empty[(Int, BigInt)]
        var trap = Option.empty[(Int, BigInt)]
        var halted = false

        for (cycle <- 0 until 5000 if trap.isEmpty) {
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
            Some((2, readWord(base)))
          } else None

          if (dut.io.trap.valid.peek().litToBoolean) {
            trap = Some(dut.io.trap.cause.peek().litValue.toInt -> dut.io.trap.pc.peek().litValue)
          }

          dut.clock.step()

          if (fetchResponseFires) fetchResponse = None
          fetchAddress.foreach(address => fetchResponse = Some(1 -> address))
          fetchResponse = fetchResponse.map { case (delay, address) => (math.max(0, delay - 1), address) }
          dataResponse = if (dataResponseFires) None else dataResponse.map { case (delay, word) =>
            (math.max(0, delay - 1), word)
          }
          acceptedDataRequest.foreach(response => dataResponse = Some(response))
          halted = dut.io.halted.peek().litToBoolean
        }

        trap.map(_._1) shouldBe Some(3)
        halted shouldBe true
        readWord(0x1000) shouldBe BigInt("600dcafe", 16)
        readWord(0x1004) shouldBe BigInt("12345678", 16)
      }
    }
  }
}
