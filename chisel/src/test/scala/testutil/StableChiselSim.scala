package testutil

import chisel3.simulator.scalatest.ChiselSim
import svsim.{CommonCompilationSettings, CommonSettingsModifications}

trait StableChiselSim extends ChiselSim {
  this: org.scalatest.TestSuite =>

  implicit override def commonSettingsModifications: CommonSettingsModifications = {
    val inherited = super.commonSettingsModifications
    settings => inherited(settings).copy(
      availableParallelism = CommonCompilationSettings.AvailableParallelism.UpTo(1)
    )
  }
}
