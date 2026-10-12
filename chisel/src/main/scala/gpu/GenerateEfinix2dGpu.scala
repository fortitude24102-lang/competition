package gpu

import circt.stage.ChiselStage

object GenerateEfinix2dGpu extends App {
  // Build-time A/B switch; the old software register ABI is unchanged.
  private val legacyCopy = args.contains("--legacy-copy")
  private val instances = args.contains("--instances")
  private val lists = args.contains("--frame-lists")
  ChiselStage.emitSystemVerilogFile(new Efinix2dGpuTop(!legacyCopy, instances,lists),
    args.filterNot(a => a == "--legacy-copy" || a == "--instances" || a == "--frame-lists"))
}
