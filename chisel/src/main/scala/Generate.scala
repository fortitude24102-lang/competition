import circt.stage.ChiselStage

object Generate extends App {
  ChiselStage.emitSystemVerilogFile(new Blink, args)
}
