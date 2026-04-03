<#
.SYNOPSIS
    Generates a post-migration validation report comparing source and destination
    state for each pilot user. Outputs PASS / REVIEW / FAIL per user.

.DESCRIPTION
    Lab Script 8 of 8 — StoneZone Security M365 Migration Script Library
    Companion to: Mastering Microsoft 365 Migrations by Sterling Stone

    Validates the following for each user in the pilot CSV:
      - Account exists and is enabled in destination
      - Licence is assigned
      - OneDrive is provisioned and contains files
      - MFA is registered (Auth methods count > 0)
      - Sign-in is not blocked
      - (Optional) Mailbox exists in Exchange Online

    Outputs a colour-coded console summary and a full CSV report for
    distribution to project stakeholders and the help desk.

.PARAMETER CsvPath
    Path to the pilot users CSV. Requires UPN and DestUPN columns (or just UPN
    if source and destination UPNs are the same).

.PARAMETER CheckMailbox
    If true, also validates that a mailbox exists in Exchange Online.
    Requires Exchange Online connection (Connect-ExchangeOnline).
    Default: $false.

.PARAMETER MinFileCount
    Minimum number of files expected in OneDrive for a PASS result. Default: 1.

.NOTES
    Required Graph Scopes (destination app): User.Read.All, Files.Read.All, AuditLog.Read.All
    Run Lab Script 1 first to establish destination connection.

    Author:  Sterling Stone — StoneZone Security LLC
    Version: 1.0.0
    Updated: 2026-04
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateScript({ Test-Path $_ })][string]$CsvPath,
    [bool]$CheckMailbox  = $false,
    [int]$MinFileCount   = 1
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

#region ── Logging ────────────────────────────────────────────────────────────
$Timestamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
$LogFile    = "$global:LogRoot\ValidationReport-$Timestamp.log"
$ReportCsv  = "$global:DataRoot\ValidationReport-$Timestamp.csv"
$ReportHtml = "$global:DataRoot\ValidationReport-$Timestamp.html"

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
$report  = [System.Collections.Generic.List[PSObject]]::new()
$pass = 0; $review = 0; $fail = 0

Write-Log "Running post-migration validation for $($users.Count) users..."

foreach ($user in $users) {
    $destUPN = if ($user.DestUPN) { $user.DestUPN } else { $user.UPN }

    $checks = [ordered]@{
        AccountExists   = $false
        AccountEnabled  = $false
        LicenceAssigned = $false
        OneDriveExists  = $false
        FileCount       = 0
        FilesPresent    = $false
        MFARegistered   = $false
        SignInAllowed   = $false
        MailboxExists   = 'N/A'
    }
    $errors = @()

    try {
        #── Account ───────────────────────────────────────────────────────────
        $destUser = Get-MgUser -UserId $destUPN `
                        -Property Id,DisplayName,AccountEnabled,AssignedLicenses,SignInSessionsValidFromDateTime `
                        -ErrorAction Stop
        $checks.AccountExists  = $true
        $checks.AccountEnabled = $destUser.AccountEnabled
        $checks.LicenceAssigned = ($destUser.AssignedLicenses.Count -gt 0)

        #── OneDrive ──────────────────────────────────────────────────────────
        try {
            $drive = Get-MgUserDrive -UserId $destUPN -ErrorAction Stop
            $checks.OneDriveExists = $true
            $rootChildren = Get-MgUserDriveRootChild -UserId $destUPN -ErrorAction SilentlyContinue
            $checks.FileCount   = @($rootChildren).Count
            $checks.FilesPresent = ($checks.FileCount -ge $MinFileCount)
        } catch {
            $errors += "OneDrive: $_"
        }

        #── MFA registration ──────────────────────────────────────────────────
        try {
            $authMethods = Get-MgUserAuthenticationMethod -UserId $destUPN -ErrorAction Stop
            # Filter out the default password method — count only real second factors
            $mfaMethods = $authMethods | Where-Object {
                $_.'@odata.type' -notmatch 'passwordAuthentication'
            }
            $checks.MFARegistered = ($mfaMethods.Count -gt 0)
        } catch {
            $errors += "MFA check: $_"
        }

        #── Sign-in not blocked ───────────────────────────────────────────────
        $checks.SignInAllowed = $destUser.AccountEnabled

        #── Mailbox (optional) ────────────────────────────────────────────────
        if ($CheckMailbox) {
            try {
                $mbx = Get-Mailbox -Identity $destUPN -ErrorAction Stop
                $checks.MailboxExists = $true
            } catch {
                $checks.MailboxExists = $false
                $errors += "Mailbox: not found"
            }
        }

    } catch {
        $errors += "Account lookup failed: $_"
        Write-Log "  FAIL: $destUPN — $_" 'ERROR'
    }

    #── Determine overall result ─────────────────────────────────────────────
    $coreChecks = @($checks.AccountExists, $checks.AccountEnabled,
                    $checks.LicenceAssigned, $checks.OneDriveExists, $checks.FilesPresent)
    $result = if ($coreChecks -notcontains $false -and $checks.MFARegistered) {
        'PASS'
    } elseif ($checks.AccountExists -and $checks.LicenceAssigned) {
        'REVIEW'
    } else {
        'FAIL'
    }

    switch ($result) {
        'PASS'   { $pass++;   Write-Host "  ✓ PASS   $destUPN" -ForegroundColor Green }
        'REVIEW' { $review++; Write-Host "  ~ REVIEW $destUPN" -ForegroundColor Yellow }
        'FAIL'   { $fail++;   Write-Host "  ✗ FAIL   $destUPN" -ForegroundColor Red }
    }

    $report.Add([PSCustomObject]@{
        DestUPN         = $destUPN
        Result          = $result
        AccountExists   = $checks.AccountExists
        AccountEnabled  = $checks.AccountEnabled
        LicenceAssigned = $checks.LicenceAssigned
        OneDriveExists  = $checks.OneDriveExists
        FileCount       = $checks.FileCount
        MFARegistered   = $checks.MFARegistered
        SignInAllowed   = $checks.SignInAllowed
        MailboxExists   = $checks.MailboxExists
        Errors          = ($errors -join ' | ')
        Timestamp       = (Get-Date -Format 'o')
    })

    Start-Sleep -Milliseconds 300
}

#region ── Export ─────────────────────────────────────────────────────────────
$report | Export-Csv -Path $ReportCsv -NoTypeInformation

# Simple HTML report for stakeholder distribution
$htmlRows = $report | ForEach-Object {
    $color = switch ($_.Result) { 'PASS' {'#d4edda'} 'REVIEW' {'#fff3cd'} default {'#f8d7da'} }
    "<tr style='background:$color'><td>$($_.DestUPN)</td><td><b>$($_.Result)</b></td>" +
    "<td>$($_.AccountEnabled)</td><td>$($_.LicenceAssigned)</td>" +
    "<td>$($_.OneDriveExists)</td><td>$($_.FileCount)</td>" +
    "<td>$($_.MFARegistered)</td><td>$($_.Errors)</td></tr>"
}

$html = @"
<!DOCTYPE html><html><head><title>M365 Migration Validation Report</title>
<style>body{font-family:Segoe UI,sans-serif;margin:20px}
table{border-collapse:collapse;width:100%}th,td{border:1px solid #ddd;padding:8px;font-size:12px}
th{background:#1F4E79;color:#fff}.summary{padding:10px;margin-bottom:15px;background:#f5f5f5;border-radius:4px}</style>
</head><body>
<h2>M365 Migration Validation Report</h2>
<p>Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | Tenant: $($global:DestContext.TenantId)</p>
<div class='summary'>
  <b>PASS: $pass</b> &nbsp;|&nbsp; <b>REVIEW: $review</b> &nbsp;|&nbsp; <b>FAIL: $fail</b>
  &nbsp;|&nbsp; Total: $($report.Count)
</div>
<table><tr><th>User UPN</th><th>Result</th><th>Acct Enabled</th><th>Licensed</th>
<th>OneDrive</th><th>Files</th><th>MFA Registered</th><th>Errors</th></tr>
$($htmlRows -join "`n")</table>
<p><small>StoneZone Security LLC — M365 Migration Script Library v1.0</small></p>
</body></html>
"@
$html | Out-File -FilePath $ReportHtml -Encoding UTF8
#endregion

Write-Log "Validation complete. PASS: $pass | REVIEW: $review | FAIL: $fail"
Write-Log "CSV report: $ReportCsv"
Write-Log "HTML report: $ReportHtml"

# Return summary object for pipeline use
[PSCustomObject]@{ Pass = $pass; Review = $review; Fail = $fail; ReportPath = $ReportCsv }
