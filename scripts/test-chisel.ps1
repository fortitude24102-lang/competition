$ErrorActionPreference = 'Stop'

& wsl.exe -d Ubuntu -- bash /mnt/d/ZYNQ/smallproject/scripts/test-chisel.sh
exit $LASTEXITCODE
