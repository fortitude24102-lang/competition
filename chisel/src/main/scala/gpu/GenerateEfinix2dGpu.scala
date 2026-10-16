package gpu

import circt.stage.ChiselStage

object GenerateEfinix2dGpu extends App {
  // Build-time A/B switch; the old software register ABI is unchanged.
  private val legacyCopy = args.contains("--legacy-copy")
  private val instances = args.contains("--instances")
  private val lists = args.contains("--frame-lists")
  private val keyPrefetch = args.contains("--key-prefetch")
  private val stripes = args.contains("--stripe-scratchpad")
  ChiselStage.emitSystemVerilogFile(new Efinix2dGpuTop(!legacyCopy, instances,lists,keyPrefetch,stripes),
    args.filterNot(a => Set("--legacy-copy", "--instances", "--frame-lists", "--key-prefetch", "--stripe-scratchpad")(a)))
}
