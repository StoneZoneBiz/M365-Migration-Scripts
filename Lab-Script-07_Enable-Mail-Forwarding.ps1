<#
.SYNOPSIS
    Configures SMTP forwarding from source mailboxes to destination addresses
    during the hybrid coexistence period.

.DESCRIPTION
    Lab Script 7 of 8 — StoneZone Security M365 Migration Script Library
    Companion to: Mastering Microsoft 365 Migrations by Sterling Stone

    During hybrid coexistence, mail sent to a user's old source address must be
    delivered to their new destination mailbox. This script reads a forwarding
    map CSV and sets ForwardingSMTPAddress on each source mailbox with
    DeliverToMailboxAndForward enabled — ensuring the user receives mail in both
    locations during the transition window.

    IMPORTANT: Remove forwarding after each wave's cutover is validated. Leaving
    forwarding in place permanently can cause mail loops and compliance issues.

.PARAMETER ForwardingCsvPath
    Path to CSV with columns: SourceUPN, DestUPN.
    SourceUPN = the existing source mailbox address.
    DestUPN   = the new destination address in Exchange Online.

.PARAMETER DeliverToMailboxAndForward
    If true (default), mail is delivered to the source mailbox AND forwarded.
    Set to false to forward-only (source user receives no local copy).

.PARAMETER WhatIf
    Standard PowerShell WhatIf — shows what would change without applying it.

.NOTES
    Requires: ExchangeOnlineManagement module v3+
    Connect-ExchangeOnline must be called before this script, or use -UseRPSSession.
    Does NOT require Graph — uses Exchange Online PowerShell cmdlets.

    Author:  Sterling Stone — StoneZone Security LLC
    Version: 1.0.0
    Updated: 2026-04
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][ValidateScript({ Test-Path $_ })][string]$ForwardingCsvPath,
    [bool]$DeliverToMailboxAndForward = $true
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Continue'

#region ── Logging ────────────────────────────────────────────────────────────
$Timestamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
$LogFile    = "$global:LogRoot\MailForwarding-$Timestamp.log"
$ResultsCsv = "$global:DataRoot\MailForwarding-Results-$Timestamp.csv"
$ErrorCsv   = "$global:DataRoot\MailForwarding-Errors-$Timestamp.csv"

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $entry = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] $Message"
    Add-Content -Path $LogFile -Value $entry
    $color = switch ($Level) { 'WARN' {'Yellow'} 'ERROR' {'Red'} default {'Cyan'} }
    Write-Host $entry -ForegroundColor $color
}
#endregion

#region ── Validate EXO connection ────────────────────────────────────────────
Write-Log "Validating Exchange Online connection..."
try {
    $null = Get-OrganizationConfig -ErrorAction Stop
    Write-Log "Exchange Online connection confirmed."
} catch {
    Write-Log "Not connected to Exchange Online. Run Connect-ExchangeOnline first." 'ERROR'
    throw
}
#endregion

$forwardingMap = Import-Csv -Path $ForwardingCsvPath
Write-Log "Loaded $($forwardingMap.Count) forwarding rules from $ForwardingCsvPath"

# Validate CSV columns
if (-not ($forwardingMap[0].PSObject.Properties.Name -contains 'SourceUPN') -or
    -not ($forwardingMap[0].PSObject.Properties.Name -contains 'DestUPN')) {
    throw "CSV must contain 'SourceUPN' and 'DestUPN' columns."
}

$results = [System.Collections.Generic.List[PSObject]]::new()
$errors  = [System.Collections.Generic.List[PSObject]]::new()
$set = 0; $failed = 0

foreach ($row in $forwardingMap) {
    $src  = $row.SourceUPN.Trim()
    $dest = $row.DestUPN.Trim()

    try {
        # Verify source mailbox exists
        $mailbox = Get-Mailbox -Identity $src -ErrorAction Stop

        if ($PSCmdlet.ShouldProcess($src, "Set forwarding to $dest")) {
            Set-Mailbox -Identity $src `
                -ForwardingSMTPAddress $dest `
                -DeliverToMailboxAndForward $DeliverToMailboxAndForward `
                -ErrorAction Stop

            Write-Log "  Set: $src → $dest (DeliverBoth: $DeliverToMailboxAndForward)"
            $results.Add([PSCustomObject]@{
                SourceUPN  = $src
                DestUPN    = $dest
                DeliverBoth = $DeliverToMailboxAndForward
                Status     = 'Set'
                Timestamp  = (Get-Date -Format 'o')
            })
            $set++
        }

    } catch {
        Write-Log "  FAILED: $src — $_" 'ERROR'
        $errors.Add([PSCustomObject]@{
            SourceUPN = $src
            DestUPN   = $dest
            Error     = $_.Exception.Message
            Timestamp = (Get-Date -Format 'o')
        })
        $failed++
    }

    Start-Sleep -Milliseconds 200
}

$results | Export-Csv -Path $ResultsCsv -NoTypeInformation
if ($errors.Count -gt 0) {
    $errors | Export-Csv -Path $ErrorCsv -NoTypeInformation
    Write-Log "Error log: $ErrorCsv" 'WARN'
}

Write-Log "Complete. Forwarding set: $set | Failed: $failed"
Write-Log "REMINDER: Remove forwarding (Set-Mailbox -ForwardingSMTPAddress `$null) after cutover validation."
