# Exercise the actual child-process functions. No serial/JTAG or live gateway.
$ErrorActionPreference='Stop'
$path=Join-Path $PSScriptRoot 'test-game-menu-board.ps1'
$collectorRoot=$PSScriptRoot
$ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$null,[ref]$null)
foreach($name in @('Start-GameKeepalive','Stop-GameKeepalive')) {
 $node=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true)
 if(!$node){throw "Missing actual function: $name"}
 # AST extraction loses the file-local automatic root; bind that dependency.
 . ([scriptblock]::Create($node.Extent.Text.Replace('$PSScriptRoot','$collectorRoot')))
}
$primary=(Get-Command python -CommandType Application|Select-Object -First 1).Source
$outPath=Join-Path ([IO.Path]::GetTempPath()) ('keepalive-process-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $outPath|Out-Null
$script:commands=@([pscustomobject]@{Source=$primary},[pscustomobject]@{Source='Z:\missing-alias\python.exe'})
function Get-Command {param($Name,$CommandType) $script:commands}
$Python='python';$keepalive=$null;$acquired=$true;$held=0
$boot=@{token='offline-fixture'};$client='offline';$action=0
$GatewayUrl='http://127.0.0.1:9' # Deliberately not the user's gateway.
try {
 Start-GameKeepalive
 if(!$keepalive -or $keepalive.Id -le 0){throw 'No real child launched'}
 Stop-GameKeepalive
 if($keepalive -or !(Test-Path -LiteralPath "$outPath/keepalive.log")){throw 'Child not retired'}
 'PASS actual collector chooses first Python match and retires real child'
} finally {if($keepalive){try{Stop-GameKeepalive}catch{}}}
$script:commands=@([pscustomobject]@{Source=(Join-Path $outPath 'missing-python.exe')})
$failure=$null
try {Start-GameKeepalive}catch{$failure=$_}
if(!$failure){throw 'Missing runtime must fail launch'}
if($keepalive){try{Stop-GameKeepalive}catch{};throw 'Failed launch left an unstarted child for cleanup'}
Stop-GameKeepalive
'PASS failed launch preserves original failure and leaves no unstarted child'
