<#
.SYNOPSIS
    Establishes authenticated connections to source and destination Microsoft 365 tenants
    using certificate-based authentication via the Microsoft Graph PowerShell SDK.

.DESCRIPTION
    Lab Script 1 of 8 — StoneZone Security M365 Migration Script Library
    Companion to: Mastering Microsoft 365 Migrations by Sterling Stone
    Repository: github.com/StoneZoneSecurity/M365-Migration-Scripts

    Creates the standard log and data directory structure, then connects to both
    source and destination tenants using app registrations with certificate thumbprints.
    All subsequent scripts in this library depend on this connection pattern.

.PARAMETER SourceTenantId
    The Tenant ID (GUID) of the source Microsoft 365 tenant.

.PARAMETER SourceClientId
    The Application (Client) ID of the app registration in the source tenant.

.PARAMETER SourceCertThumb
    The certificate thumbprint registered in the source tenant app registration.

.PARAMETER DestTenantId
    The Tenant ID (GUID) of the destination Microsoft 365 tenant.

.PARAMETER DestClientId
    The Application (Client) ID of the app registration in the destination tenant.

.PARAMETER DestCertThumb
    The certificate thumbprint registered in the destination tenant app registration.

.NOTES
    Required Graph Scopes — Source App Registration:
        User.Read.All, Directory.Read.All, Files.Read.All, AuditLog.Read.All

    Required Graph Scopes — Destination App Registration:
        User.ReadWrite.All, Directory.ReadWrite.All, Files.ReadWrite.All,
        Sites.ReadWrite.All, Team.Create, Channel.Create,
        TeamMember.ReadWrite.All, Organization.Read.All

    Prerequisites:
        Install-Module Microsoft.Graph -Scope CurrentUser
        Install-Module ExchangeOnlineManagement -Scope CurrentUser

    Author:  Sterling Stone — StoneZone Security LLC
    Version: 1.0.0
    Updated: 2026-04
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SourceTenantId,
    [Parameter(Mandatory)][string]$SourceClientId,
    [Parameter(Mandatory)][string]$SourceCertThumb,
    [Parameter(Mandatory)][string]$DestTenantId,
    [Parameter(Mandatory)][string]$DestClientId,
    [Parameter(Mandatory)][string]$DestCertThumb
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#region ── Directory setup ────────────────────────────────────────────────────
$global:LogRoot  = "$env:USERPROFILE\M365Migration\Logs"
$global:DataRoot = "$env:USERPROFILE\M365Migration\Data"
New-Item -ItemType Directory -Force -Path $global:LogRoot, $global:DataRoot | Out-Null

$LogFile = "$global:LogRoot\Connect-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

function Write-Log {
    param([string]$Message, [ValidateSet('INFO','WARN','ERROR')][string]$Level = 'INFO')
    $entry = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] $Message"
    Add-Content -Path $LogFile -Value $entry
    switch ($Level) {
        'INFO'  { Write-Host $entry -ForegroundColor Cyan }
        'WARN'  { Write-Host $entry -ForegroundColor Yellow }
        'ERROR' { Write-Host $entry -ForegroundColor Red }
    }
}
#endregion

#region ── Prerequisite check ─────────────────────────────────────────────────
Write-Log "Checking required modules..."
$required = @('Microsoft.Graph.Authentication','Microsoft.Graph.Users',
              'Microsoft.Graph.Files','Microsoft.Graph.Teams')
foreach ($mod in $required) {
    if (-not (Get-Module -ListAvailable -Name $mod)) {
        Write-Log "Module '$mod' not found. Run: Install-Module Microsoft.Graph -Scope CurrentUser" 'ERROR'
        throw "Missing module: $mod"
    }
}
Write-Log "All required modules present."
#endregion

#region ── Source tenant connection ───────────────────────────────────────────
Write-Log "Connecting to SOURCE tenant: $SourceTenantId"
try {
    Connect-MgGraph -TenantId $SourceTenantId `
                    -ClientId $SourceClientId `
                    -CertificateThumbprint $SourceCertThumb `
                    -NoWelcome
    $global:SourceContext = Get-MgContext
    Write-Log "SOURCE connected. Tenant: $($global:SourceContext.TenantId) | App: $($global:SourceContext.ClientId)"
} catch {
    Write-Log "Failed to connect to source tenant: $_" 'ERROR'
    throw
}
#endregion

#region ── Destination tenant connection ──────────────────────────────────────
Write-Log "Connecting to DESTINATION tenant: $DestTenantId"
try {
    Connect-MgGraph -TenantId $DestTenantId `
                    -ClientId $DestClientId `
                    -CertificateThumbprint $DestCertThumb `
                    -NoWelcome
    $global:DestContext = Get-MgContext
    Write-Log "DESTINATION connected. Tenant: $($global:DestContext.TenantId) | App: $($global:DestContext.ClientId)"
} catch {
    Write-Log "Failed to connect to destination tenant: $_" 'ERROR'
    throw
}
#endregion

Write-Log "Both tenant connections established. LogRoot: $global:LogRoot | DataRoot: $global:DataRoot"
Write-Host "`nReady. Run subsequent Lab Scripts in the same session." -ForegroundColor Green
