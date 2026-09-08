package gpu

import circt.stage.ChiselStage

object GenerateEfinix2dGpu extends App {
  ChiselStage.emitSystemVerilogFile(new Efinix2dGpuTop, args)
}
