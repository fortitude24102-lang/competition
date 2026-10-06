package gpu

import circt.stage.ChiselStage

object GenerateEfinix2dGpu extends App {
  // Build-time A/B switch; the old software register ABI is unchanged.
  private val legacyCopy = args.contains("--legacy-copy")
  private val instances = args.contains("--instances")
  ChiselStage.emitSystemVerilogFile(new Efinix2dGpuTop(!legacyCopy, instances),
    args.filterNot(a => a == "--legacy-copy" || a == "--instances"))
}
