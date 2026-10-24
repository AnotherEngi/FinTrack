[CmdletBinding()]
param([switch]$Install)

$ErrorActionPreference = 'Stop'
$wingetCommand = Get-Command winget -ErrorAction SilentlyContinue
if (-not $wingetCommand) {
    $wingetCandidate = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'
    if (Test-Path -LiteralPath $wingetCandidate) { $wingetCommand = Get-Item -LiteralPath $wingetCandidate }
}
if (-not $wingetCommand) {
    throw 'WinGet is required. Install/update Microsoft App Installer, then rerun this script.'
}
$wingetExe = if ($wingetCommand.Source) { $wingetCommand.Source } else { $wingetCommand.FullName }

Write-Output 'Windows setup: VS 2022 C++ x64 build tools + Windows SDK, then stable Swift.'
Write-Output 'Swift WinGet dependencies include Python 3.10 and the Microsoft VC runtime.'
Write-Output 'This script does not change Windows Developer Mode or install a full Visual Studio IDE.'
if (-not $Install) {
    Write-Output 'Preparation only. To install, run: .\scripts\Setup-WindowsSwift.ps1 -Install'
    & $wingetExe show --id Swift.Toolchain --exact --source winget --accept-source-agreements
    if ($LASTEXITCODE -ne 0) { throw 'Unable to inspect the Swift package.' }
    return
}

$vswhereExe = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$vcTools = if (Test-Path -LiteralPath $vswhereExe) {
    @(& $vswhereExe -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath)
} else { @() }
if ($vcTools.Count -eq 0) {
    & $wingetExe install --id Microsoft.VisualStudio.2022.BuildTools --exact --source winget `
        --accept-source-agreements --accept-package-agreements `
        --override '--wait --passive --norestart --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 --add Microsoft.VisualStudio.Component.Windows11SDK.22621'
    if ($LASTEXITCODE -notin @(0, 3010)) { throw ('C++ build tools installation failed: ' + $LASTEXITCODE) }
} else {
    Write-Output ('Existing C++ tools found: ' + $vcTools[0])
    Write-Output 'Confirm a Windows SDK is installed with that Visual Studio installation.'
}

& $wingetExe install --id Swift.Toolchain --exact --source winget `
    --accept-source-agreements --accept-package-agreements
if ($LASTEXITCODE -notin @(0, 3010)) {
    throw ('Swift installation failed: ' + $LASTEXITCODE)
}
Write-Output 'Reopen your terminal (and VS Code if necessary), then run .\scripts\Test-Core.ps1.'
