$ErrorActionPreference = "Stop"

$RepositoryRoot = Split-Path -Parent $PSScriptRoot

& (Join-Path $PSScriptRoot "build-sdl.ps1")
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# Dawn loads the shader compiler from beside the executable, as a package has
# it, and a test that runs shaders needs it there too.
$BinPath = swift build --package-path $RepositoryRoot --show-bin-path | Select-Object -Last 1
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
New-Item -ItemType Directory -Force $BinPath | Out-Null
Copy-Item (Join-Path ${env:ProgramFiles(x86)} "Windows Kits\10\Redist\D3D\x64\d3dcompiler_47.dll") $BinPath

$env:SDL_VIDEODRIVER = "dummy"
$env:SDL_AUDIODRIVER = "dummy"

swift test --package-path $RepositoryRoot @args
exit $LASTEXITCODE
