<#
.SYNOPSIS
    Pre-provisions OneDrive for Business for all pilot users in the destination tenant.

.DESCRIPTION
    Lab Script 3 of 8 — StoneZone Security M365 Migration Script Library
    Companion to: Mastering Microsoft 365 Migrations by Sterling Stone

    OneDrive is not automatically provisioned when a user account is created — it
    initialises on first login or when explicitly triggered via Graph. This script
    forces provisioning for all users in the pilot CSV so that file migration (Script 5)
    does not fail with "drive not found" errors.

    Provisioning can take 30-90 seconds per user. The script polls until the drive
    is confirmed available before moving to the next user.

.PARAMETER CsvPath
    Path to the pilot users CSV (same file used in Script 2). Requires UPN column.

.PARAMETER MaxWaitSeconds
    Maximum seconds to wait for OneDrive provisioning per user. Default: 120.

.NOTES
    Required Graph Scopes (destination app): Sites.ReadWrite.All
    Run Lab Script 1 first to establish the destination tenant connection.

    Author:  Sterling Stone — StoneZone Security LLC
    Version: 1.0.0
    Updated: 2026-04
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateScript({ Test-Path $_ })][string]$CsvPath,
    [int]$MaxWaitSeconds = 120
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

#region ── Logging ────────────────────────────────────────────────────────────
$LogFile    = "$global:LogRoot\PreProvision-OneDrive-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
$ResultsCsv = "$global:DataRoot\PreProvision-Results-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $entry = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] $Message"
    Add-Content -Path $LogFile -Value $entry
    $color = switch ($Level) { 'WARN' {'Yellow'} 'ERROR' {'Red'} default {'Cyan'} }
    Write-Host $entry -ForegroundColor $color
}
#endregion

if (-not $global:DestContext) { throw "Run Lab Script 1 first." }

$users   = Import-Csv -Path $CsvPath
$results = [System.Collections.Generic.List[PSObject]]::new()
Write-Log "Pre-provisioning OneDrive for $($users.Count) users..."

foreach ($user in $users) {
    $upn      = $user.UPN
    $status   = 'Unknown'
    $waitedMs = 0
    $interval = 5000   # Poll every 5 seconds

    Write-Log "Provisioning: $upn"

    do {
        try {
            $drive = Get-MgUserDrive -UserId $upn -ErrorAction Stop
            if ($drive.Id) {
                $status = 'Provisioned'
                Write-Log "  OK — DriveId: $($drive.Id) | Quota: $([math]::Round($drive.Quota.Total/1GB,1)) GB"
            }
        } catch {
            if ($waitedMs -ge ($MaxWaitSeconds * 1000)) {
                $status = 'Timeout'
                Write-Log "  TIMEOUT after ${MaxWaitSeconds}s — $upn" 'WARN'
            } else {
                Write-Log "  Waiting for provisioning... ($([math]::Round($waitedMs/1000))s elapsed)"
                Start-Sleep -Milliseconds $interval
                $waitedMs += $interval
            }
        }
    } while ($status -eq 'Unknown')

    $results.Add([PSCustomObject]@{
        UPN       = $upn
        Status    = $status
        Timestamp = (Get-Date -Format 'o')
    })

    Start-Sleep -Milliseconds 200   # Graph throttle buffer
}

$results | Export-Csv -Path $ResultsCsv -NoTypeInformation
$provisioned = ($results | Where-Object { $_.Status -eq 'Provisioned' }).Count
$timeouts    = ($results | Where-Object { $_.Status -eq 'Timeout' }).Count
Write-Log "Complete. Provisioned: $provisioned | Timeouts: $timeouts"
Write-Log "Results: $ResultsCsv"
