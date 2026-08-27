$environmentRoot = 'D:\Chisel-environment'

$requiredDirectories = @(
    (Join-Path $environmentRoot 'jdk-17\bin'),
    (Join-Path $environmentRoot 'sbt\bin'),
    (Join-Path $environmentRoot 'firtool-1.139.0\bin'),
    (Join-Path $environmentRoot 'msys64\ucrt64\bin'),
    (Join-Path $environmentRoot 'msys64\usr\bin'),
    (Join-Path $environmentRoot 'bin')
)

foreach ($directory in $requiredDirectories) {
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        throw "Missing Chisel environment directory: $directory"
    }
}

$env:CHISEL_ENV_HOME = $environmentRoot
$env:JAVA_HOME = Join-Path $environmentRoot 'jdk-17'
$env:CHISEL_FIRTOOL_PATH = Join-Path $environmentRoot 'firtool-1.139.0\bin'
$env:COURSIER_CACHE = Join-Path $environmentRoot 'cache\coursier'
$env:SBT_BOOT_DIRECTORY = Join-Path $environmentRoot 'cache\sbt\boot'
$env:SBT_GLOBAL_BASE = Join-Path $environmentRoot 'cache\sbt\global'
$env:SBT_IVY_HOME = Join-Path $environmentRoot 'cache\ivy'
$env:VERILATOR_ROOT = Join-Path $environmentRoot 'msys64\ucrt64\share\verilator'
$env:SBT_OPTS = "-Dsbt.boot.directory=$env:SBT_BOOT_DIRECTORY -Dsbt.global.base=$env:SBT_GLOBAL_BASE -Dsbt.ivy.home=$env:SBT_IVY_HOME"

$toolPaths = @(
    (Join-Path $environmentRoot 'bin'),
    (Join-Path $env:JAVA_HOME 'bin'),
    (Join-Path $environmentRoot 'sbt\bin'),
    $env:CHISEL_FIRTOOL_PATH,
    (Join-Path $environmentRoot 'msys64\ucrt64\bin'),
    (Join-Path $environmentRoot 'msys64\usr\bin')
)

$env:Path = (($toolPaths + ($env:Path -split ';')) | Where-Object { $_ } | Select-Object -Unique) -join ';'
