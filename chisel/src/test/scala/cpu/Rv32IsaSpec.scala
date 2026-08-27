package cpu

import chisel3.simulator.scalatest.ChiselSim
import org.scalatest.funspec.AnyFunSpec
import org.scalatest.matchers.should.Matchers

class Rv32IsaSpec extends AnyFunSpec with ChiselSim with Matchers {
  describe("RV32I definitions") {
    it("uses the architectural trap cause numbers") {
      TrapCause.InstructionAddressMisaligned.litValue shouldBe 0
      TrapCause.InstructionAccessFault.litValue shouldBe 1
      TrapCause.IllegalInstruction.litValue shouldBe 2
      TrapCause.Breakpoint.litValue shouldBe 3
      TrapCause.LoadAddressMisaligned.litValue shouldBe 4
      TrapCause.LoadAccessFault.litValue shouldBe 5
      TrapCause.StoreAddressMisaligned.litValue shouldBe 6
      TrapCause.StoreAccessFault.litValue shouldBe 7
      TrapCause.EnvironmentCall.litValue shouldBe 11
    }
  }
}
