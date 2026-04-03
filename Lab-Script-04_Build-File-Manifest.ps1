<#
.SYNOPSIS
    Enumerates all files in source OneDrive accounts and writes a transfer manifest CSV.

.DESCRIPTION
    Lab Script 4 of 8 — StoneZone Security M365 Migration Script Library
    Companion to: Mastering Microsoft 365 Migrations by Sterling Stone

    Recursively walks each source user's OneDrive, collecting file metadata including
    the temporary download URL, file size, and full path. The resulting manifest CSV
    is consumed by Lab Script 5 (file transfer). Large tenants should run this script
    off-hours as it generates significant Graph API traffic.

    Download URLs expire after approximately 1 hour — run Script 5 immediately after
    this script completes, or re-run Script 4 to refresh URLs before transferring.

.PARAMETER CsvPath
    Path to the pilot users CSV. Requires UPN column.

.PARAMETER ManifestPath
    Output path for the file manifest CSV. Defaults to DataRoot\file_manifest_<timestamp>.csv

.PARAMETER ThrottleMs
    Milliseconds to wait between Graph calls. Increase to 500+ for large tenants. Default: 100.

.NOTES
    Required Graph Scopes (source app): Files.Read.All
    Run Lab Script 1 first to establish the source tenant connection.

    Author:  Sterling Stone — StoneZone Security LLC
    Version: 1.0.0
    Updated: 2026-04
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateScript({ Test-Path $_ })][string]$CsvPath,
    [string]$ManifestPath = "",
    [int]$ThrottleMs = 100
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

#region ── Logging ────────────────────────────────────────────────────────────
$Timestamp   = Get-Date -Format 'yyyyMMdd-HHmmss'
$LogFile     = "$global:LogRoot\BuildManifest-$Timestamp.log"
if (-not $ManifestPath) { $ManifestPath = "$global:DataRoot\file_manifest_$Timestamp.csv" }
$global:ManifestPath = $ManifestPath   # Expose for Script 5

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $entry = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] $Message"
    Add-Content -Path $LogFile -Value $entry
    $color = switch ($Level) { 'WARN' {'Yellow'} 'ERROR' {'Red'} default {'Cyan'} }
    Write-Host $entry -ForegroundColor $color
}
#endregion

if (-not $global:SourceContext) { throw "Source context not found. Run Lab Script 1 first." }

#region ── Recursive file enumeration ─────────────────────────────────────────
function Get-FilesRecursive {
    param(
        [string]$UserId,
        [string]$ItemId   = 'root',
        [string]$BasePath = ''
    )

    try {
        $children = Get-MgUserDriveItemChild -UserId $UserId -DriveItemId $ItemId -All `
                        -ErrorAction Stop
    } catch {
        Write-Log "  Failed to enumerate $ItemId for $UserId : $_" 'WARN'
        return
    }

    foreach ($item in $children) {
        $itemPath = if ($BasePath) { "$BasePath/$($item.Name)" } else { $item.Name }

        if ($item.Folder) {
            # Recurse into folder
            Get-FilesRecursive -UserId $UserId -ItemId $item.Id -BasePath $itemPath
        } else {
            # Emit file record
            [PSCustomObject]@{
                UserUPN      = $UserId
                FileName     = $item.Name
                FilePath     = $itemPath
                SizeBytes    = $item.Size
                LastModified = $item.LastModifiedDateTime
                DriveItemId  = $item.Id
                DownloadUrl  = $item.AdditionalProperties['@microsoft.graph.downloadUrl']
            }
        }
        Start-Sleep -Milliseconds $ThrottleMs
    }
}
#endregion

$users    = Import-Csv -Path $CsvPath
$manifest = [System.Collections.Generic.List[PSObject]]::new()
$totalFiles = 0; $totalBytes = 0

Write-Log "Building file manifest for $($users.Count) users..."

foreach ($user in $users) {
    Write-Log "Enumerating: $($user.UPN)"
    try {
        $files = Get-FilesRecursive -UserId $user.UPN
        $count = @($files).Count
        $bytes = ($files | Measure-Object -Property SizeBytes -Sum).Sum
        $totalFiles += $count
        $totalBytes += $bytes
        foreach ($f in $files) { $manifest.Add($f) }
        Write-Log "  $count files | $([math]::Round($bytes/1MB,1)) MB"
    } catch {
        Write-Log "  Failed for $($user.UPN): $_" 'ERROR'
    }
}

$manifest | Export-Csv -Path $ManifestPath -NoTypeInformation
Write-Log "Manifest complete. Total: $totalFiles files | $([math]::Round($totalBytes/1GB,2)) GB"
Write-Log "Manifest written to: $ManifestPath"
Write-Log "NOTE: Download URLs expire ~60 minutes. Run Script 5 immediately."
