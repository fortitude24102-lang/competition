param([string]$Out=('generated/verification/v3/hud-logo-encoder-'+(Get-Date -Format 'yyyyMMdd-HHmmss-fff')))
# Catch byte-width shifts discarding RGB565's red/green high bits. The preview
# PNG can look correct even when the actual binary pixels are wrong.
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $Out) {throw 'Refusing to overwrite encoder test evidence'}
New-Item -ItemType Directory -Path $Out | Out-Null
$Out=(Resolve-Path -LiteralPath $Out).Path
Add-Type -AssemblyName System.Drawing
$source=New-Object Drawing.Bitmap 200,70
$graphics=[Drawing.Graphics]::FromImage($source)
try {
 $colors=@([Drawing.Color]::White,[Drawing.Color]::Red,[Drawing.Color]::Lime,[Drawing.Color]::Blue)
 for($i=0;$i -lt 4;$i++) {
  $brush=New-Object Drawing.SolidBrush $colors[$i]
  try {$graphics.FillRectangle($brush,$i*50,0,50,70)} finally {$brush.Dispose()}
 }
 $source.Save((Join-Path $Out 'colors.png'),[Drawing.Imaging.ImageFormat]::Png)
} finally {$graphics.Dispose();$source.Dispose()}
& (Join-Path $PSScriptRoot 'build_hud_logo.ps1') -InputPng (Join-Path $Out 'colors.png') -Out (Join-Path $Out 'result')
$actual=[IO.File]::ReadAllBytes((Join-Path $Out 'result/competition_logo.rgb565'))
if($actual.Length -ne 28000) {throw 'Wrong complete image length'}
$expected=@(65535,63488,2016,31) # Literal RGB565 white, red, green, blue.
for($y=0;$y -lt 70;$y++) {for($i=0;$i -lt 4;$i++) {
 $word=[BitConverter]::ToUInt16($actual,2*($y*200+$i*50+10))
 if($word -ne $expected[$i]) {throw ('Wrong RGB565 color[{0}] row{1}: want 0x{2:x4}, got 0x{3:x4}' -f $i,$y,$expected[$i],$word)}
}}
Write-Output 'PASS actual RGB565 bytes: white FFFF, red F800, green 07E0, blue 001F; all70 rows'
