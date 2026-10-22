package gpu

import chisel3._
import circt.stage.ChiselStage
import org.scalatest.funspec.AnyFunSpec
import org.scalatest.matchers.should.Matchers

class WideCopyConfigSpec extends AnyFunSpec with Matchers {
  it("rejects native DMA with the narrow-only stripe scratchpad instead of corrupting its reserved window") {
    val error=intercept[IllegalArgumentException] {
      ChiselStage.emitCHIRRTL(new Efinix2dGpuTop(enableStripeScratchpad=true,enableWideCopyDma=true))
    }
    error.getMessage should include ("scratchpad")
  }
}
