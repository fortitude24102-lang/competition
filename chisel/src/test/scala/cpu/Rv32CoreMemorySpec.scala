package cpu

import chisel3.simulator.scalatest.ChiselSim
import org.scalatest.funspec.AnyFunSpec
import org.scalatest.matchers.should.Matchers

class Rv32CoreMemorySpec extends AnyFunSpec with ChiselSim with Matchers {
  describe("Rv32Core memory pipeline") {
    it("executes byte, halfword, and word accesses with delayed bus handshakes") {
      val instructions = new TestMemory(Seq(
        BigInt("10000093", 16), // addi x1, x0, 256
        BigInt("f8000113", 16), // addi x2, x0, -128
        BigInt("00208023", 16), // sb   x2, 0(x1)
        BigInt("0000c183", 16), // lbu  x3, 0(x1)
        BigInt("00008203", 16), // lb   x4, 0(x1)
        BigInt("12300293", 16), // addi x5, x0, 0x123
        BigInt("00509123", 16), // sh   x5, 2(x1)
        BigInt("0020d303", 16), // lhu  x6, 2(x1)
        BigInt("00209383", 16), // lh   x7, 2(x1)
        BigInt("02a00413", 16), // addi x8, x0, 42
        BigInt("0080a223", 16), // sw   x8, 4(x1)
        BigInt("0040a483", 16), // lw   x9, 4(x1)
        BigInt("00148513", 16), // addi x10, x9, 1
        BigInt("00000013", 16),
        BigInt("00000013", 16)
      ))
      val data = Array.fill(512)(0)

      simulate(new Rv32Core()) { dut =>
        dut.io.imem.req.ready.poke(true)
        dut.io.imem.resp.valid.poke(false)
        dut.io.imem.resp.bits.rdata.poke(0)
        dut.io.imem.resp.bits.error.poke(false)
        dut.io.dmem.req.ready.poke(false)
        dut.io.dmem.resp.valid.poke(false)
        dut.io.dmem.resp.bits.rdata.poke(0)
        dut.io.dmem.resp.bits.error.poke(false)

        var fetchResponse = Option.empty[BigInt]
        var dataResponse = Option.empty[(Int, BigInt)]
        var writes = Vector.empty[(Int, BigInt)]
        var dataRequests = 0

        for (cycle <- 0 until 400 if writes.length < 10) {
          fetchResponse match {
            case Some(address) =>
              dut.io.imem.resp.valid.poke(true)
              dut.io.imem.resp.bits.rdata.poke(instructions.readWord(address))
            case None => dut.io.imem.resp.valid.poke(false)
          }

          val dataReady = cycle % 3 == 0
          dut.io.dmem.req.ready.poke(dataReady)
          dataResponse match {
            case Some((0, word)) =>
              dut.io.dmem.resp.valid.poke(true)
              dut.io.dmem.resp.bits.rdata.poke(word)
            case _ => dut.io.dmem.resp.valid.poke(false)
          }

          val fetchResponseFires = fetchResponse.nonEmpty && dut.io.imem.resp.ready.peek().litToBoolean
          val fetchRequestFires = dut.io.imem.req.valid.peek().litToBoolean
          val fetchAddress = if (fetchRequestFires) Some(dut.io.imem.req.bits.addr.peek().litValue) else None
          val dataResponseFires = dataResponse.exists(_._1 == 0) && dut.io.dmem.resp.ready.peek().litToBoolean
          val dataRequestFires = dataReady && dut.io.dmem.req.valid.peek().litToBoolean

          val acceptedDataRequest = if (dataRequestFires) {
            dataRequests += 1
            val address = dut.io.dmem.req.bits.addr.peek().litValue.toInt
            val write = dut.io.dmem.req.bits.write.peek().litToBoolean
            val writeData = dut.io.dmem.req.bits.wdata.peek().litValue
            val writeStrobe = dut.io.dmem.req.bits.wstrb.peek().litValue.toInt
            val base = address & ~3
            if (write) {
              for (lane <- 0 until 4 if (writeStrobe & (1 << lane)) != 0) {
                data(base + lane) = ((writeData >> (8 * lane)) & 0xff).toInt
              }
            }
            val readWord = (0 until 4).foldLeft(BigInt(0)) { (word, lane) =>
              word | (BigInt(data(base + lane)) << (8 * lane))
            }
            Some((2, readWord))
          } else None

          if (dut.io.commit.valid.peek().litToBoolean && dut.io.commit.writeEnable.peek().litToBoolean) {
            writes :+= dut.io.commit.rd.peek().litValue.toInt -> dut.io.commit.data.peek().litValue
          }

          dut.clock.step()

          if (fetchResponseFires) fetchResponse = None
          fetchAddress.foreach(address => fetchResponse = Some(address))
          dataResponse = if (dataResponseFires) None else dataResponse.map { case (delay, word) =>
            (math.max(0, delay - 1), word)
          }
          acceptedDataRequest.foreach(response => dataResponse = Some(response))
        }

        writes shouldBe Vector(
          1 -> BigInt(256),
          2 -> BigInt("ffffff80", 16),
          3 -> BigInt(128),
          4 -> BigInt("ffffff80", 16),
          5 -> BigInt("123", 16),
          6 -> BigInt("123", 16),
          7 -> BigInt("123", 16),
          8 -> BigInt(42),
          9 -> BigInt(42),
          10 -> BigInt(43)
        )
        dataRequests shouldBe 8
        data(0x100) shouldBe 0x80
        data(0x102) shouldBe 0x23
        data(0x103) shouldBe 0x01
        data.slice(0x104, 0x108).toVector shouldBe Vector(42, 0, 0, 0)
      }
    }
  }
}
