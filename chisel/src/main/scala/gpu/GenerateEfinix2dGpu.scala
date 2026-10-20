package gpu

import circt.stage.ChiselStage

object GenerateEfinix2dGpu extends App {
  // Build-time A/B switch; the old software register ABI is unchanged.
  private val legacyCopy = args.contains("--legacy-copy")
  private val instances = args.contains("--instances")
  private val lists = args.contains("--frame-lists")
  private val keyPrefetch = args.contains("--key-prefetch")
  private val stripes = args.contains("--stripe-scratchpad")
  private val burstBuffer = args.contains("--copy-burst-buffer")
  private val scanoutPipeline = args.contains("--scanout-word-pipeline")
  private val keyTrim = args.contains("--key-row-trim")
  private val transform = args.contains("--transform-blit")
  private val alphaPipeline = args.contains("--alpha-pipeline")
  private val axiDiagnostics = args.contains("--axi-diagnostics")
  private val keyWritePipeline = args.contains("--key-write-pipeline")
  require(!keyTrim || keyPrefetch, "Key row trim requires Key prefetch")
  ChiselStage.emitSystemVerilogFile(new Efinix2dGpuTop(!legacyCopy, instances,lists,keyPrefetch,stripes,burstBuffer,scanoutPipeline,keyTrim,transform,alphaPipeline,axiDiagnostics,keyWritePipeline),
    args.filterNot(a => Set("--legacy-copy", "--instances", "--frame-lists", "--key-prefetch", "--stripe-scratchpad", "--copy-burst-buffer", "--scanout-word-pipeline", "--key-row-trim", "--transform-blit", "--alpha-pipeline", "--axi-diagnostics", "--key-write-pipeline")(a)))
}
