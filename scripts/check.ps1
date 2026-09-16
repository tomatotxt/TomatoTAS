param([string]$ToolsDirectory = '')
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$luau = if ($ToolsDirectory) { Join-Path $ToolsDirectory 'luau.exe' } else { 'luau' }
$compiler = if ($ToolsDirectory) { Join-Path $ToolsDirectory 'luau-compile.exe' } else { 'luau-compile' }
$analyzer = if ($ToolsDirectory) { Join-Path $ToolsDirectory 'luau-analyze.exe' } else { 'luau-analyze' }
$files = @(Get-ChildItem -LiteralPath (Join-Path $repo 'src'),(Join-Path $repo 'tests') -Recurse -Filter '*.luau')
$files += Get-Item -LiteralPath (Join-Path $repo 'loader.luau')
foreach ($file in $files) {
    & $compiler --null $file.FullName | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Compilation failed: $($file.FullName)" }
}
Write-Output "Compiled $($files.Count) Luau files."
$analysisFiles = @('src/core/Quaternion.luau','src/core/Tree.luau','src/core/Codec.luau','src/core/Sampling.luau','tests/core.luau') |
    ForEach-Object { Join-Path $repo $_ }
& $analyzer @analysisFiles
if ($LASTEXITCODE -ne 0) { throw 'Pure-core static analysis failed' }
Write-Output 'Pure-core static analysis passed.'
foreach ($suite in (Get-ChildItem -LiteralPath (Join-Path $repo 'tests') -Filter '*.luau' | Sort-Object Name)) {
    if ($suite.BaseName -eq 'loader') {
        $loaderSource = Get-Content -LiteralPath (Join-Path $repo 'loader.luau') -Raw
        & $luau $suite.FullName -a $loaderSource
    } else {
        & $luau $suite.FullName
    }
    if ($LASTEXITCODE -ne 0) { throw "Test suite failed: $($suite.Name)" }
}
Write-Output 'All local checks passed. In-game integration still requires Roblox.'
