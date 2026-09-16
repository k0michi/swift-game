$ErrorActionPreference = "Stop"

$RepositoryRoot = Split-Path -Parent $PSScriptRoot
$DependencyDirectory = Join-Path $RepositoryRoot ".build/dependencies/sdl3"
$BuildDirectory = Join-Path $DependencyDirectory "cmake-build"
$InstallDirectory = Join-Path $DependencyDirectory "install"
$SwiftBinDirectory = Split-Path -Parent (Get-Command swiftc).Source
$ClangCL = Join-Path $SwiftBinDirectory "clang-cl.exe"

cmake `
    --fresh `
    -G Ninja `
    -S $RepositoryRoot `
    -B $BuildDirectory `
    "-DCMAKE_BUILD_TYPE=Release" `
    "-DCMAKE_INSTALL_PREFIX=$InstallDirectory" `
    "-DCMAKE_C_COMPILER=$ClangCL"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

cmake --build $BuildDirectory --config Release --parallel
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

cmake --install $BuildDirectory --config Release
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

cmake `
    --fresh `
    -S (Join-Path $RepositoryRoot "cmake/ExtractSDLTarget") `
    -B (Join-Path $DependencyDirectory "metadata") `
    "-DCMAKE_PREFIX_PATH=$InstallDirectory" `
    "-DOUTPUT_DIRECTORY=$DependencyDirectory" `
    "-DCMAKE_BUILD_TYPE=Release"
exit $LASTEXITCODE
