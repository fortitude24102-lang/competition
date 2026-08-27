ThisBuild / scalaVersion := "2.13.18"

val chiselVersion = "7.7.0"

lazy val root = (project in file("."))
  .settings(
    name := "smallproject-chisel",
    libraryDependencies ++= Seq(
      "org.chipsalliance" %% "chisel" % chiselVersion,
      "org.scalatest" %% "scalatest" % "3.2.19" % Test
    ),
    scalacOptions += "-language:reflectiveCalls",
    addCompilerPlugin("org.chipsalliance" % "chisel-plugin" % chiselVersion cross CrossVersion.full)
  )
