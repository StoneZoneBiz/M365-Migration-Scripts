<#
.SYNOPSIS
    Creates a pilot Microsoft Team with standard channels in the destination tenant.

.DESCRIPTION
    Lab Script 6 of 8 — StoneZone Security M365 Migration Script Library
    Companion to: Mastering Microsoft 365 Migrations by Sterling Stone

    Creates a private Team, adds specified owners and members, and provisions a
    standard set of channels. Used to validate Teams provisioning and membership
    management via Graph before production migration of existing Teams.

    Team provisioning is asynchronous — the script polls until the team is confirmed
    available before attempting channel creation.

.PARAMETER OwnerUPN
    UPN of the user who will be the Team owner (must exist in destination tenant).

.PARAMETER MemberUPNs
    Array of UPNs to add as Team members.

.PARAMETER TeamDisplayName
    Display name for the pilot Team. Default: 'Migration Pilot Team'.

.PARAMETER Channels
    Array of channel names to create. Default: IT Announcements, Migration Updates, Help & Support.

.NOTES
    Required Graph Scopes (destination app): Team.Create, Channel.Create, TeamMember.ReadWrite.All
    Run Lab Script 1 first.

    Author:  Sterling Stone — StoneZone Security LLC
    Version: 1.0.0
    Updated: 2026-04
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$OwnerUPN,
    [string[]]$MemberUPNs      = @(),
    [string]$TeamDisplayName   = 'Migration Pilot Team',
    [string[]]$Channels        = @('IT Announcements','Migration Updates','Help & Support')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region ── Logging ────────────────────────────────────────────────────────────
$LogFile = "$global:LogRoot\SeedTeam-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $entry = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] $Message"
    Add-Content -Path $LogFile -Value $entry
    $color = switch ($Level) { 'WARN' {'Yellow'} 'ERROR' {'Red'} default {'Cyan'} }
    Write-Host $entry -ForegroundColor $color
}
#endregion

if (-not $global:DestContext) { throw "Run Lab Script 1 first." }

#region ── Resolve owner object ID ────────────────────────────────────────────
Write-Log "Resolving owner: $OwnerUPN"
$owner = Get-MgUser -UserId $OwnerUPN -ErrorAction Stop
Write-Log "Owner resolved: $($owner.DisplayName) ($($owner.Id))"
#endregion

#region ── Create Team ────────────────────────────────────────────────────────
Write-Log "Creating Team: '$TeamDisplayName'"

$teamParams = @{
    DisplayName = $TeamDisplayName
    Description = 'Migration pilot team — provisioned by StoneZone Security migration toolkit'
    Visibility  = 'Private'
    Members     = @(
        @{
            '@odata.type'    = '#microsoft.graph.aadUserConversationMember'
            Roles            = @('owner')
            'user@odata.bind' = "https://graph.microsoft.com/v1.0/users/$($owner.Id)"
        }
    )
}

if ($PSCmdlet.ShouldProcess($TeamDisplayName, 'Create Team')) {
    $team = New-MgTeam -BodyParameter $teamParams
    Write-Log "Team created. ID: $($team.Id)"

    #── Poll until team is provisioned ──────────────────────────────────────
    Write-Log "Waiting for team provisioning (up to 60s)..."
    $waited  = 0
    $ready   = $false
    while ($waited -lt 60 -and -not $ready) {
        Start-Sleep -Seconds 5; $waited += 5
        try {
            $check = Get-MgTeam -TeamId $team.Id -ErrorAction Stop
            if ($check.Id) { $ready = $true; Write-Log "Team ready after ${waited}s." }
        } catch { Write-Log "  Still provisioning... (${waited}s)" }
    }
    if (-not $ready) { Write-Log "Team provisioning timeout — channels may fail." 'WARN' }
}
#endregion

#region ── Add members ────────────────────────────────────────────────────────
foreach ($upn in $MemberUPNs) {
    try {
        $member = Get-MgUser -UserId $upn -ErrorAction Stop
        $memberParams = @{
            '@odata.type'    = '#microsoft.graph.aadUserConversationMember'
            Roles            = @()
            'user@odata.bind' = "https://graph.microsoft.com/v1.0/users/$($member.Id)"
        }
        New-MgTeamMember -TeamId $team.Id -BodyParameter $memberParams | Out-Null
        Write-Log "  Added member: $upn"
    } catch {
        Write-Log "  Failed to add member $upn : $_" 'WARN'
    }
    Start-Sleep -Milliseconds 300
}
#endregion

#region ── Create channels ────────────────────────────────────────────────────
foreach ($channelName in $Channels) {
    try {
        if ($PSCmdlet.ShouldProcess($channelName, 'Create channel')) {
            New-MgTeamChannel -TeamId $team.Id `
                -DisplayName $channelName `
                -MembershipType 'standard' | Out-Null
            Write-Log "  Channel created: $channelName"
        }
    } catch {
        Write-Log "  Failed to create channel '$channelName': $_" 'WARN'
    }
    Start-Sleep -Milliseconds 500
}
#endregion

Write-Log "Team provisioning complete. TeamId: $($team.Id)"
Write-Log "Log: $LogFile"
