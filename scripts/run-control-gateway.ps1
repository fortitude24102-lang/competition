param(
    [string]$BoardIp = "",
    [int]$BoardPort = 8090,
    [string]$UdpBind = "0.0.0.0",
    [int]$UdpPort = 8090,
    [int]$HttpPort = 8765,
    [string]$Python = "python",
    [switch]$Simulated,
    [switch]$FakeBoardOnly
)
$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$ToolRoot = Join-Path $RepoRoot "sw/efinix_gpu/tools/control_gateway"
foreach ($PortValue in @($BoardPort, $UdpPort, $HttpPort)) {
    if ($PortValue -lt 1 -or $PortValue -gt 65535) { throw "Port must be 1..65535" }
}
$PythonCommand = Get-Command $Python -ErrorAction Stop
$PythonExecutable = $PythonCommand.Source
# Efinity's bundled Python needs its own library home; restore the caller environment on exit.
$PriorPythonHome = $env:PYTHONHOME
try {
    if ($PythonExecutable -replace '\\','/' -match '/efinity/python311/bin/python.exe$') {
        $env:PYTHONHOME = Split-Path -Parent (Split-Path -Parent $PythonExecutable)
    }
    if ($FakeBoardOnly) {
        Write-Host "SIMULATED ACK/ECHO ONLY. No game logic or performance measurement."
        if ($BoardPort -eq 8090) { $BoardPort = 8091 }
        & $PythonExecutable (Join-Path $ToolRoot "fake_board.py") --bind 127.0.0.1 --port $BoardPort --gateway 127.0.0.1 --gateway-port $UdpPort
    } else {
        if ($Simulated) {
            $BoardIp = "127.0.0.1"
            $UdpBind = "127.0.0.1"
            if ($BoardPort -eq 8090) { $BoardPort = 8091 }
            Write-Host "SIMULATED dashboard. Start a separate -FakeBoardOnly terminal using the same ports."
        }
        if ([string]::IsNullOrWhiteSpace($BoardIp)) { throw "Specify -BoardIp for the real board, or -Simulated for the fake ACK/echo peer." }
        $GatewayArgs = @((Join-Path $ToolRoot "gateway.py"), "--board", $BoardIp,
            "--board-port", "$BoardPort", "--udp-bind", $UdpBind, "--udp-port", "$UdpPort", "--http-port", "$HttpPort")
        if ($Simulated) { $GatewayArgs += "--simulated" }
        & $PythonExecutable @GatewayArgs
    }
    $ToolExitCode = $LASTEXITCODE
} finally {
    $env:PYTHONHOME = $PriorPythonHome
}
exit $ToolExitCode
