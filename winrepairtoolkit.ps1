[CmdletBinding()]
param(
    [ValidateSet(
        "Scan",
        "Check",
        "ScanImage",
        "Repair",
        "Cleanup",
        "FullRepair",
        "FullRepairDiagnostic"
    )]
    [string]$Action
)

$Version = "1.1.0"
$BuildDate = "2026-11-25"

# ------------------------------------------------------------
# SELF-ELEVATE
# ------------------------------------------------------------

$CurrentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
$Principal = New-Object Security.Principal.WindowsPrincipal($CurrentIdentity)

if (-not $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
{
    $Args = @(
        "-NoProfile"
        "-ExecutionPolicy"
        "Bypass"
        "-File"
        "`"$PSCommandPath`""
    )

    if ($Action) {
        $Args += @("-Action", $Action)
    }

    Start-Process `
        -FilePath "powershell.exe" `
        -Verb RunAs `
        -ArgumentList $Args

    exit
}

# ------------------------------------------------------------
# LOGGING
# ------------------------------------------------------------

$LogRoot = Join-Path $env:ProgramData "WindowsRepair"

if (-not (Test-Path $LogRoot))
{
    New-Item `
        -ItemType Directory `
        -Force `
        -Path $LogRoot | Out-Null
}

$TimeStamp = Get-Date -Format "yyyyMMdd-HHmmss"

$TranscriptLog = Join-Path `
    $LogRoot `
    "Repair-$TimeStamp.log"

try
{
    Start-Transcript `
        -Path $TranscriptLog `
        -Append | Out-Null
}
catch
{
}

try
{
    $Host.UI.RawUI.WindowTitle = "Windows Repair Utility $Version"
}
catch
{
}

# ------------------------------------------------------------
# FUNCTIONS
# ------------------------------------------------------------

function Show-Banner {

    Clear-Host

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "                 WINDOWS REPAIR TOOLKIT" -ForegroundColor Yellow
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host " Version : $Version"
    Write-Host " Build   : $BuildDate"
    Write-Host ""
}

function Show-SystemInfo {

    try {

        $OS = Get-CimInstance Win32_OperatingSystem

        Write-Host "Computer : $env:COMPUTERNAME" -ForegroundColor Gray
        Write-Host "OS       : $($OS.Caption)" -ForegroundColor Gray
        Write-Host "Version  : $($OS.Version)" -ForegroundColor Gray
        Write-Host ""
    }
    catch
    {
    }
}

function Show-Section {

    param([string]$Text)

    Write-Host ""
    Write-Host "------------------------------------------------------------" -ForegroundColor DarkCyan
    Write-Host " $Text" -ForegroundColor Cyan
    Write-Host "------------------------------------------------------------" -ForegroundColor DarkCyan
    Write-Host ""
}

function Save-RepairLogs {

    param(
        [string]$TimeStamp
    )

    try {

        $ExportDir = Join-Path `
            $env:ProgramData `
            "WindowsRepair\$TimeStamp"

        New-Item `
            -ItemType Directory `
            -Force `
            -Path $ExportDir | Out-Null

        $CBS = "$env:windir\Logs\CBS\CBS.log"
        $DISM = "$env:windir\Logs\DISM\dism.log"

        if (Test-Path $CBS) {
            Copy-Item `
                $CBS `
                (Join-Path $ExportDir "CBS.log") `
                -Force
        }

        if (Test-Path $DISM) {
            Copy-Item `
                $DISM `
                (Join-Path $ExportDir "DISM.log") `
                -Force
        }

        Write-Host ""
        Write-Host "Repair logs exported:" -ForegroundColor Green
        Write-Host "  $ExportDir" -ForegroundColor Gray
        Write-Host ""
    }
    catch {

        Write-Host ""
        Write-Host "Unable to export DISM/CBS logs." -ForegroundColor Yellow
        Write-Host ""
    }
}

function Invoke-RepairTask {

    param(
        [string]$Name,
        [string]$File,
        [string[]]$Arguments
    )

    Show-Section $Name

    Write-Host "Running:" -ForegroundColor Yellow
    Write-Host " $File $($Arguments -join ' ')" -ForegroundColor Gray
    Write-Host ""

    $StopWatch = [System.Diagnostics.Stopwatch]::StartNew()

    & $File @Arguments

    $ExitCode = $LASTEXITCODE

    $StopWatch.Stop()

    Write-Host ""

    if ($ExitCode -eq 0)
    {
        Write-Host "[SUCCESS]" -ForegroundColor Green -NoNewline
        Write-Host " Completed in $($StopWatch.Elapsed)"
    }
    else
    {
        Write-Host "[WARNING]" -ForegroundColor Yellow -NoNewline
        Write-Host " Exit Code $ExitCode"
    }

    Write-Host ""
}

function Show-Menu {

    Show-Banner
    Show-SystemInfo

    Write-Host "Log File:" -ForegroundColor Yellow
    Write-Host "  $TranscriptLog" -ForegroundColor Gray
    Write-Host ""

    Write-Host "1 - SFC Scan" -ForegroundColor Green
    Write-Host "2 - DISM CheckHealth" -ForegroundColor Green
    Write-Host "3 - DISM ScanHealth" -ForegroundColor Green
    Write-Host "4 - DISM RestoreHealth" -ForegroundColor Green
    Write-Host "5 - Component Cleanup" -ForegroundColor Green
    Write-Host ""
    Write-Host "6 - Fast Full Repair" -ForegroundColor Yellow
    Write-Host "    RestoreHealth + SFC"
    Write-Host ""
    Write-Host "7 - Diagnostic Full Repair" -ForegroundColor Yellow
    Write-Host "    CheckHealth + ScanHealth + RestoreHealth + SFC"
    Write-Host ""
    Write-Host "Q - Quit" -ForegroundColor Red
    Write-Host ""

    $Choice = Read-Host "Select Option"

    switch ($Choice.ToUpper())
    {
        "1" { return "Scan" }
        "2" { return "Check" }
        "3" { return "ScanImage" }
        "4" { return "Repair" }
        "5" { return "Cleanup" }
        "6" { return "FullRepair" }
        "7" { return "FullRepairDiagnostic" }
        "Q" { exit }

        default {
            Write-Host ""
            Write-Host "Invalid Selection." -ForegroundColor Red
            Start-Sleep -Seconds 2
            return (Show-Menu)
        }
    }
}

# ------------------------------------------------------------
# MENU
# ------------------------------------------------------------

if (-not $Action)
{
    $Action = Show-Menu
}

Show-Banner
Show-SystemInfo

Write-Host "Log File:" -ForegroundColor Yellow
Write-Host "  $TranscriptLog" -ForegroundColor Gray
Write-Host ""

# ------------------------------------------------------------
# MAIN
# ------------------------------------------------------------

switch ($Action)
{
    "Scan" {

        Invoke-RepairTask `
            -Name "System File Checker" `
            -File "sfc.exe" `
            -Arguments "/scannow"
    }

    "Check" {

        Invoke-RepairTask `
            -Name "DISM CheckHealth" `
            -File "dism.exe" `
            -Arguments @(
                "/Online"
                "/Cleanup-Image"
                "/CheckHealth"
            )
    }

    "ScanImage" {

        Invoke-RepairTask `
            -Name "DISM ScanHealth" `
            -File "dism.exe" `
            -Arguments @(
                "/Online"
                "/Cleanup-Image"
                "/ScanHealth"
            )
    }

    "Repair" {

        Invoke-RepairTask `
            -Name "DISM RestoreHealth" `
            -File "dism.exe" `
            -Arguments @(
                "/Online"
                "/Cleanup-Image"
                "/RestoreHealth"
            )

        Save-RepairLogs $TimeStamp
    }

    "Cleanup" {

        Invoke-RepairTask `
            -Name "Component Store Cleanup" `
            -File "dism.exe" `
            -Arguments @(
                "/Online"
                "/Cleanup-Image"
                "/StartComponentCleanup"
            )
    }

    "FullRepair" {

        Show-Section "FAST FULL REPAIR"

        Invoke-RepairTask `
            -Name "DISM RestoreHealth" `
            -File "dism.exe" `
            -Arguments @(
                "/Online"
                "/Cleanup-Image"
                "/RestoreHealth"
            )

        Invoke-RepairTask `
            -Name "System File Checker" `
            -File "sfc.exe" `
            -Arguments "/scannow"

        Save-RepairLogs $TimeStamp
    }

    "FullRepairDiagnostic" {

        Show-Section "DIAGNOSTIC FULL REPAIR"

        Invoke-RepairTask `
            -Name "DISM CheckHealth" `
            -File "dism.exe" `
            -Arguments @(
                "/Online"
                "/Cleanup-Image"
                "/CheckHealth"
            )

        Invoke-RepairTask `
            -Name "DISM ScanHealth" `
            -File "dism.exe" `
            -Arguments @(
                "/Online"
                "/Cleanup-Image"
                "/ScanHealth"
            )

        Invoke-RepairTask `
            -Name "DISM RestoreHealth" `
            -File "dism.exe" `
            -Arguments @(
                "/Online"
                "/Cleanup-Image"
                "/RestoreHealth"
            )

        Invoke-RepairTask `
            -Name "System File Checker" `
            -File "sfc.exe" `
            -Arguments "/scannow"

        Save-RepairLogs $TimeStamp
    }
}

# ------------------------------------------------------------
# COMPLETE
# ------------------------------------------------------------

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "                    OPERATION COMPLETE" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""

Write-Host "Transcript:" -ForegroundColor Yellow
Write-Host "  $TranscriptLog" -ForegroundColor Gray
Write-Host ""

Write-Host "Tip: Reboot Windows after any repair operation." -ForegroundColor Yellow
Write-Host ""

try
{
    Stop-Transcript | Out-Null
}
catch
{
}

Read-Host "Press ENTER to exit"