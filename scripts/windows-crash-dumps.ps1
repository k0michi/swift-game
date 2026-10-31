param([Parameter(Mandatory)][ValidateSet("keep", "print")][string]$Action)

$ErrorActionPreference = "Stop"

# Crash dumps on Windows, where Swift prints no stacks when a program
# crashes. "keep" has Windows keep a dump of every process that crashes in
# $env:RUNNER_TEMP\crash-dumps, and "print" prints the stacks of each dump
# with cdb, from the Windows SDK, looking up the symbols of the debug build.

$Dumps = Join-Path $env:RUNNER_TEMP "crash-dumps"

if ($Action -eq "keep") {
    New-Item -ItemType Directory -Force $Dumps | Out-Null
    $Key = "HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting\LocalDumps"
    New-Item -Force $Key | Out-Null
    New-ItemProperty -Force -Path $Key -Name DumpFolder -PropertyType ExpandString -Value $Dumps | Out-Null
    # Minidumps, ten at most.
    New-ItemProperty -Force -Path $Key -Name DumpType -PropertyType DWord -Value 1 | Out-Null
    New-ItemProperty -Force -Path $Key -Name DumpCount -PropertyType DWord -Value 10 | Out-Null
    exit 0
}

$Files = Get-ChildItem $Dumps -Filter *.dmp -ErrorAction SilentlyContinue
if (-not $Files) {
    Write-Host "No process crashed."
    exit 0
}
$Cdb = Get-ChildItem "${env:ProgramFiles(x86)}\Windows Kits\10\Debuggers\x64\cdb.exe" -ErrorAction SilentlyContinue |
    Select-Object -First 1
if (-not $Cdb) {
    Write-Host "cdb is not installed, so only the dumps are kept."
    exit 0
}
$RepositoryRoot = Split-Path -Parent $PSScriptRoot
$Bin = swift build --package-path $RepositoryRoot --show-bin-path | Select-Object -Last 1
$Symbols = "$Bin;srv*$env:RUNNER_TEMP\symbols*https://msdl.microsoft.com/download/symbols"
foreach ($File in $Files) {
    Write-Host "::group::$($File.Name)"
    # The thread that crashed, then every thread.
    & $Cdb.FullName -z $File.FullName -y $Symbols -c ".ecxr; kn 60; ~*kn 30; q"
    Write-Host "::endgroup::"
}
exit 0
