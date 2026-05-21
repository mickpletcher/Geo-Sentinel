#requires -Version 7.0

[CmdletBinding()]
param (
    [Parameter()]
    [string]$ConfigurationPath = (Join-Path $PSScriptRoot 'config\geofence.settings.json'),

    [Parameter()]
    [ValidateSet('JSON', 'PowerShell', 'NginxMap', 'CloudflareRules', 'FirewallRules')]
    [string[]]$Format,

    [Parameter()]
    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'Modules\Geo.Sentinel\Geo.Sentinel.psm1') -Force

$result = Export-GeofenceArtifacts -ConfigurationPath $ConfigurationPath -Formats $Format

if ($PassThru) {
    $result
}
else {
    $result | Format-Table -AutoSize
}