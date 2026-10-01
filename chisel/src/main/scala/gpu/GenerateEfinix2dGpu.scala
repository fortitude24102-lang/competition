package gpu

import circt.stage.ChiselStage

object GenerateEfinix2dGpu extends App {
  // Build-time A/B switch; the old software register ABI is unchanged.
  private val legacyCopy = args.contains("--legacy-copy")
  ChiselStage.emitSystemVerilogFile(new Efinix2dGpuTop(!legacyCopy), args.filterNot(_ == "--legacy-copy"))
}
