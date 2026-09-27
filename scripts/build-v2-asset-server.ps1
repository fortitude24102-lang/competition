param([string]$CrossCompiler = 'x86_64-w64-mingw32-gcc')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
Push-Location $root
try {
    $out='generated/verification/v2-network-software'
    New-Item -ItemType Directory -Force $out | Out-Null
    & wsl $CrossCompiler -O2 -std=c11 -Wall -Wextra -Werror -static -Isw/efinix_gpu/include sw/efinix_gpu/tools/asset_server/asset_server.c sw/efinix_gpu/src/asset_protocol.c sw/efinix_gpu/src/net_asset_server.c -lws2_32 -o "$out/asset_server.exe"
    if ($LASTEXITCODE -ne 0) { throw 'Windows C server build failed; WSL needs gcc-mingw-w64-x86-64' }
    Write-Output "Windows resource server: $root/$out/asset_server.exe"
} finally { Pop-Location }
