[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repoDirectory = Split-Path -Parent $PSScriptRoot
$vswhereExe = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if (Test-Path -LiteralPath $vswhereExe) {
    $vsInstallation = @(& $vswhereExe -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath)
    if ($vsInstallation.Count -gt 0) {
        $devShellScript = Join-Path $vsInstallation[0] 'Common7\Tools\Launch-VsDevShell.ps1'
        & $devShellScript -Arch amd64 -HostArch amd64 -SkipAutomaticLocation
    }
}
$swiftCommand = Get-Command swift -ErrorAction SilentlyContinue
if (-not $swiftCommand) {
    throw 'Swift is not on PATH. Reopen your terminal after setup, or run Setup-WindowsSwift.ps1 -Install first.'
}
& $swiftCommand.Source --version
& $swiftCommand.Source test --package-path (Join-Path $repoDirectory 'Packages\FinTrackCore')
if ($LASTEXITCODE -ne 0) { throw ('Core tests failed: ' + $LASTEXITCODE) }
