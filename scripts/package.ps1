param([Parameter(Mandatory)][string]$Destination)

$ErrorActionPreference = "Stop"

# Copies the release builds of the games, which build.ps1 -c release makes,
# into the directory given, with what they need beside them. SDL and Dawn are
# linked statically, so the games need the Swift runtime and the Visual C++
# runtime, and Dawn the shader compiler for Direct3D.

$RepositoryRoot = Split-Path -Parent $PSScriptRoot
$BinPath = swift build --package-path $RepositoryRoot -c release --show-bin-path
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
$BinPath = $BinPath | Select-Object -Last 1

New-Item -ItemType Directory -Force $Destination | Out-Null
foreach ($Game in "swift-game", "shooter", "pong", "text") {
    Copy-Item (Join-Path $BinPath "$Game.exe") $Destination
}
Copy-Item (Join-Path $BinPath "NotoSansJP-Regular.otf"), (Join-Path $BinPath "NotoSansJP-LICENSE.txt") $Destination
$SwiftRuntime = Split-Path -Parent (Get-Command swiftCore.dll).Source
Copy-Item (Join-Path $SwiftRuntime "*.dll") $Destination
foreach ($Library in "msvcp140.dll", "vcruntime140.dll", "vcruntime140_1.dll") {
    Copy-Item (Join-Path $env:SystemRoot "System32\$Library") $Destination
}
# Dawn loads it from beside the executable, and ships the Windows SDK's.
Copy-Item (Join-Path ${env:ProgramFiles(x86)} "Windows Kits\10\Redist\D3D\x64\d3dcompiler_47.dll") $Destination
