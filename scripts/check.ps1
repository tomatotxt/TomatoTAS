param([string]$ToolsDirectory = '')
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$luau = if ($ToolsDirectory) { Join-Path $ToolsDirectory 'luau.exe' } else { 'luau' }
$compiler = if ($ToolsDirectory) { Join-Path $ToolsDirectory 'luau-compile.exe' } else { 'luau-compile' }
$files = @(Get-ChildItem -LiteralPath (Join-Path $repo 'src'),(Join-Path $repo 'tests') -Recurse -Filter '*.luau')
$files += Get-Item -LiteralPath (Join-Path $repo 'loader.luau')
foreach ($file in $files) {
    & $compiler --null $file.FullName | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Compilation failed: $($file.FullName)" }
}
Write-Output "Compiled $($files.Count) Luau files."
foreach ($suite in @('core', 'controller', 'map')) {
    & $luau (Join-Path $repo "tests/$suite.luau")
    if ($LASTEXITCODE -ne 0) { throw "Test suite failed: $suite" }
}
Write-Output 'All local checks passed. In-game integration still requires Roblox.'
