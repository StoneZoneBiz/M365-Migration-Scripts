<#
.SYNOPSIS
    Bulk-creates users in the destination tenant from a CSV file and assigns Microsoft 365 licences.

.DESCRIPTION
    Lab Script 2 of 8 — StoneZone Security M365 Migration Script Library
    Companion to: Mastering Microsoft 365 Migrations by Sterling Stone

    Reads a pilot_users.csv file, creates each user in the destination tenant with a
    temporary password, assigns the specified licence SKU, and logs all results.
    Failed users are written to a separate error CSV for remediation.

.PARAMETER CsvPath
    Path to the pilot users CSV. Required columns: DisplayName, UPN, MailNickname,
    Department, JobTitle. Optional: UsageLocation (defaults to 'US').

.PARAMETER LicenceSku
    The SKU GUID for the licence to assign. Find with: Get-MgSubscribedSku | Select SkuId, SkuPartNumber

.PARAMETER UsageLocation
    Two-letter country code for licence assignment. Defaults to 'US'.

.NOTES
    Run Lab Script 1 first to establish the destination tenant connection.
    Required Graph Scopes (destination app): User.ReadWrite.All, Organization.Read.All

    Author:  Sterling Stone — StoneZone Security LLC
    Version: 1.0.0
    Updated: 2026-04
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][ValidateScript({ Test-Path $_ })][string]$CsvPath,
    [Parameter(Mandatory)][string]$LicenceSku,
    [string]$UsageLocation = 'US'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'   # Don't stop on individual user failures

#region ── Logging ────────────────────────────────────────────────────────────
$LogFile     = "$global:LogRoot\CreateUsers-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
$ErrorCsv    = "$global:DataRoot\CreateUsers-Errors-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
$ResultsCsv  = "$global:DataRoot\CreateUsers-Results-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $entry = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] $Message"
    Add-Content -Path $LogFile -Value $entry
    $color = switch ($Level) { 'WARN' {'Yellow'} 'ERROR' {'Red'} default {'Cyan'} }
    Write-Host $entry -ForegroundColor $color
}
#endregion

#region ── Validate destination context ───────────────────────────────────────
if (-not $global:DestContext) {
    throw "Destination tenant context not found. Run Lab Script 1 first."
}
Write-Log "Using destination tenant: $($global:DestContext.TenantId)"
#endregion

#region ── Validate licence SKU ───────────────────────────────────────────────
Write-Log "Validating licence SKU: $LicenceSku"
$sku = Get-MgSubscribedSku | Where-Object { $_.SkuId -eq $LicenceSku }
if (-not $sku) {
    Write-Log "SKU '$LicenceSku' not found in destination tenant. Available SKUs:" 'WARN'
    Get-MgSubscribedSku | Select-Object SkuId, SkuPartNumber, ConsumedUnits |
        Format-Table | Out-String | Write-Host
    throw "Invalid LicenceSku. See available SKUs above."
}
$available = $sku.PrepaidUnits.Enabled - $sku.ConsumedUnits
Write-Log "SKU '$($sku.SkuPartNumber)': $available licences available."
#endregion

#region ── Load and validate CSV ──────────────────────────────────────────────
$users = Import-Csv -Path $CsvPath
Write-Log "Loaded $($users.Count) users from $CsvPath"

$requiredCols = @('DisplayName','UPN','MailNickname')
$csvCols = $users[0].PSObject.Properties.Name
foreach ($col in $requiredCols) {
    if ($col -notin $csvCols) { throw "CSV missing required column: $col" }
}

if ($users.Count -gt $available) {
    Write-Log "WARNING: $($users.Count) users requested but only $available licences available." 'WARN'
}
#endregion

#region ── Create users ───────────────────────────────────────────────────────
$results = [System.Collections.Generic.List[PSObject]]::new()
$errors  = [System.Collections.Generic.List[PSObject]]::new()
$created = 0; $failed = 0

foreach ($user in $users) {
    $tempPassword = "TempP@ss$(Get-Random -Minimum 1000 -Maximum 9999)!"

    try {
        Write-Log "Creating user: $($user.UPN)"

        # Build user params
        $params = @{
            DisplayName         = $user.DisplayName
            UserPrincipalName   = $user.UPN
            MailNickname        = $user.MailNickname
            AccountEnabled      = $true
            UsageLocation       = if ($user.UsageLocation) { $user.UsageLocation } else { $UsageLocation }
            PasswordProfile     = @{
                ForceChangePasswordNextSignIn = $true
                Password                      = $tempPassword
            }
        }
        if ($user.Department) { $params['Department'] = $user.Department }
        if ($user.JobTitle)   { $params['JobTitle']   = $user.JobTitle }

        if ($PSCmdlet.ShouldProcess($user.UPN, 'Create user')) {
            $newUser = New-MgUser @params

            # Assign licence
            Set-MgUserLicense -UserId $newUser.Id `
                -AddLicenses @{ SkuId = $LicenceSku } `
                -RemoveLicenses @()

            Write-Log "  Created and licenced: $($user.UPN) (ID: $($newUser.Id))"
            $results.Add([PSCustomObject]@{
                UPN       = $user.UPN
                UserId    = $newUser.Id
                Status    = 'Created'
                TempPass  = $tempPassword
                Timestamp = (Get-Date -Format 'o')
            })
            $created++
        }

        # Throttle — Graph has per-minute limits
        Start-Sleep -Milliseconds 300

    } catch {
        Write-Log "  FAILED: $($user.UPN) — $_" 'ERROR'
        $errors.Add([PSCustomObject]@{
            UPN       = $user.UPN
            Error     = $_.Exception.Message
            Timestamp = (Get-Date -Format 'o')
        })
        $failed++
    }
}
#endregion

#region ── Export results ─────────────────────────────────────────────────────
$results | Export-Csv -Path $ResultsCsv -NoTypeInformation
if ($errors.Count -gt 0) {
    $errors | Export-Csv -Path $ErrorCsv -NoTypeInformation
    Write-Log "Error log written to: $ErrorCsv" 'WARN'
}

Write-Log "Complete. Created: $created | Failed: $failed"
Write-Log "Results written to: $ResultsCsv"
#endregion
