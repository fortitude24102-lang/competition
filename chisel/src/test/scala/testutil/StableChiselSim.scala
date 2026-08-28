package testutil

import chisel3.simulator.scalatest.ChiselSim
import svsim.{BackendSettingsModifications, CommonCompilationSettings, CommonSettingsModifications}
import svsim.verilator.Backend

trait StableChiselSim extends ChiselSim {
  this: org.scalatest.TestSuite =>

  implicit override def commonSettingsModifications: CommonSettingsModifications = {
    val inherited = super.commonSettingsModifications
    settings => inherited(settings).copy(
      availableParallelism = CommonCompilationSettings.AvailableParallelism.UpTo(1)
    )
  }

  implicit override def backendSettingsModifications: BackendSettingsModifications = {
    val inherited = super.backendSettingsModifications
    settings => inherited(settings) match {
      case verilator: Backend.CompilationSettings =>
        verilator.withParallelism(Some(Backend.CompilationSettings.Parallelism.Uniform.default.withNum(1)))
      case other => other
    }
  }
}
