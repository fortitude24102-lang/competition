param()

$ErrorActionPreference = 'Stop'

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$sourceRoot = Join-Path $projectRoot 'third_party\coremark'
$expectedRevision = '1f483d5b8316753a742cbf5590caf5bd0a4e4777'
$expectedHashes = [ordered]@{
    'LICENSE.md'       = '0d92a0727423e27165852685d45d9f111a071dcba594454d7edbac48c28e4490'
    'core_list_join.c' = 'cb85efa5ca7e8537ce90fdce8c13fc01de0457a162fc44ceba5e300e97306418'
    'core_main.c'      = 'c240afdd1bda84af55643ca812fcbb0dd52063a7bae2ebf12f5fc12e487328ff'
    'core_matrix.c'    = '247761a5bfd88868e4fba4b56646512f03a74ba6d35011b9bf902854f078e98b'
    'core_state.c'     = 'b3e36c4dee73824c36261dd2f405bbd4e49f9eb94dd5bc2dfbd0e17ab3b3c028'
    'core_util.c'      = '166e9bf09afd290adffe2c6681d913c18373f77e457fae258499fbaad10b04fc'
    'coremark.h'       = '0c6655620a7fb984a0f9a69b90e6fb0626694535971abfb3ca0eb88422cbeab0'
    'coremark.md5'     = '29850e3852a846dcdf8cc6d270dd623aa47d22d3adc5cb591b6d111e8c1d43ed'
}

$revisionFile = Join-Path $sourceRoot 'UPSTREAM_REVISION'
if (-not (Test-Path -LiteralPath $revisionFile -PathType Leaf)) {
    throw "Missing pinned CoreMark revision file: $revisionFile"
}
$revision = (Get-Content -LiteralPath $revisionFile -Raw).Trim()
if ($revision -ne $expectedRevision) {
    throw "CoreMark revision mismatch: expected $expectedRevision, got $revision"
}

foreach ($entry in $expectedHashes.GetEnumerator()) {
    $path = Join-Path $sourceRoot $entry.Key
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Missing official CoreMark source: $path"
    }
    $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $entry.Value) {
        throw "CoreMark source hash mismatch for $($entry.Key): expected $($entry.Value), got $actual"
    }
}

Write-Host "[PASS] CoreMark sources match $expectedRevision"
