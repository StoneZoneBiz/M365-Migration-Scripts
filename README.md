<div align="center">  
The Microsoft 365 Migration Bible 2026
Official Lab Scripts & Automation Playbooks
The Definitive Guide to Planning, Executing, and Mastering Enterprise Cloud Migrations

By Sterling Stone



[Image failed to load: PowerShell] [Image failed to load: License: MIT] [Image failed to load: Microsoft 365] [Image failed to load: Graph SDK]

</div>  


About This Repository
Welcome to the official code repository for "The Microsoft 365 Migration Bible 2026" by Sterling Stone.

This repository contains the PowerShell scripts, automation playbooks, and Lab V8.0 assets referenced throughout the book. These tools are designed to move your organization from legacy architecture to a secure, AI-ready Microsoft 365 tenant.



Repository Contents
Lab Scripts
#	Script	Description
01	Lab-Script-01_Connect-Both-Tenants.ps1	Establishes authenticated sessions to both source and target Microsoft 365 tenants
02	Lab-Script-02_Create-Users-Assign-Licences.ps1	Provisions user accounts in the target tenant and assigns appropriate license SKUs
03	Lab-Script-03_Pre-Provision-OneDrive.ps1	Pre-provisions OneDrive for Business sites for migrating users to eliminate first-login delays
04	Lab-Script-04_Build-File-Manifest.ps1	Scans source file shares and builds a structured manifest for migration planning
05	Lab-Script-05_Transfer-Files-to-OneDrive.ps1	Executes file migration from source locations to user OneDrive libraries
06	Lab-Script-06_Seed-Pilot-Team-Channels.ps1	Creates Teams structures and channels for pilot group collaboration
07	Lab-Script-07_Enable-Mail-Forwarding.ps1	Configures mail forwarding rules during coexistence periods
08	Lab-Script-08_Post-Migration-Validation-Report.ps1	Generates comprehensive post-migration validation reports with pass/fail metrics
Supporting Files
File	Purpose
sample_forwarding_map.csv	Example mail forwarding configuration for Lab Script 07
sample_pilot_users.csv	Example pilot user list for Lab Script 06
Additional Scripts Referenced in Book
Chapter	Script	Description
Ch. 3	PreFlight-Audit.ps1	Scans local AD and Exchange for UPN mismatches and legacy protocols
Ch. 7	Graph-UserProvisioning.ps1	Modern SDK-based user creation and license assignment
Ch. 8	Intune-Linux-Compliance.sh	Bash script for Ubuntu disk encryption and compliance reporting
Ch. 8	Jamf-Entra-Bridge.ps1	Helper script for verifying the Jamf-to-Intune compliance handshake
App. B	Lab-Complete-Setup.ps1	Provisions the full lab environment described in Companion Guide B


Prerequisites
Before running these scripts, ensure your administrative workstation is prepared:

Requirement	Details
PowerShell	Version 7.x (Core) recommended for cross-platform compatibility
Microsoft Graph SDK	Install-Module Microsoft.Graph -Scope CurrentUser
Exchange Online Module	Install-Module ExchangeOnlineManagement -Scope CurrentUser
Execution Policy	Set to RemoteSigned or Bypass for the duration of your lab work
Permissions	Global Administrator or appropriate delegated admin roles
Quick Start
# Install required modules
Install-Module Microsoft.Graph -Scope CurrentUser
Install-Module ExchangeOnlineManagement -Scope CurrentUser
 
# Set execution policy for lab work
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
 
# Run the first lab script
.\Lab-Script-01_Connect-Both-Tenants.ps1



Important: Security & Usage
[!WARNING] Production Safety: Never run these scripts in a production environment without first testing them in a dedicated sandbox or developer tenant.

[!CAUTION] No Hardcoded Secrets: These scripts are designed to use interactive login or Environment Variables. Ensure you do not commit your Tenant IDs or App Secrets to your own forks of this repository.



The Companion Toolkit
If you are looking for the full Project Management Suite — including Companion Guides, Migration Runbooks, T-Minus Checklists, Communications Templates, and the 150-Question Exam Key — visit the official portal:

<div align="center">  
StoneZoneSecurity.com/M365-Migrations
Available Resources:

Free (No Email Required)	Premium Toolkit (Email Required)
Migration Glossary	Full PowerShell Script Catalog
Recommended Tools List	Migration Assessment Worksheet
Companion Guides (A–E)	Discovery & Planning Checklist
Sample Scripts (this repo)	Cutover Planning Template
Book Corrections & Updates	Migration Readiness Checklist
Resource Hub Announcements	Project Governance Templates
</div>  


Migration Workflow
┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│  DISCOVERY  │───▶│  PLANNING   │───▶│  EXECUTION  │───▶│ VALIDATION  │
│             │    │             │    │             │    │             │
│ • Audit     │    │ • Provision │    │ • Migrate   │    │ • Reports   │
│ • Manifest  │    │ • Configure │    │ • Forward   │    │ • Cleanup   │
│ • Assess    │    │ • Pilot     │    │ • Cutover   │    │ • Optimize  │
└─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘
   Scripts:           Scripts:           Scripts:           Scripts:
   04                 01, 02, 03         05, 06, 07        08



Contributing
This repository is maintained as a companion to the published book. If you find issues with any script or have suggestions for improvements:

1	Open an Issue describing the problem or enhancement
2	Reference the specific script and chapter number
3	Include your PowerShell version and module versions



License
This project is licensed under the MIT License — see the LICENSE file for details.



About the Author
Sterling Stone is a Microsoft 365 migration specialist and the founder of StoneZone Security. Author of The Microsoft 365 Migration Bible 2026, Sterling helps organizations transition from legacy infrastructure to modern, secure Microsoft 365 environments.



<div align="center">  
Get the Book · Resource Hub · Report an Issue

</div> 
