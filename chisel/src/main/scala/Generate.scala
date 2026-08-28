import circt.stage.ChiselStage
import cpu.Rv32Core

object Generate extends App {
  if (args.headOption.contains("rv32")) {
    ChiselStage.emitSystemVerilogFile(new Rv32Core(), args.tail)
  } else {
    ChiselStage.emitSystemVerilogFile(new Blink, args)
  }
}
