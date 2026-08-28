import circt.stage.ChiselStage
import cpu.Rv32Core
import soc.SoCTop

object Generate extends App {
  args.headOption match {
    case Some("soc") =>
      ChiselStage.emitSystemVerilogFile(new SoCTop(), args.tail)
    case Some("rv32") =>
      ChiselStage.emitSystemVerilogFile(new Rv32Core(), args.tail)
    case _ =>
      ChiselStage.emitSystemVerilogFile(new Blink, args)
  }
}
