#requires -Version 7.0

[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string]$IPAddress,

    [Parameter()]
    [string]$CountryCode,

    [Parameter()]
    [string]$ASN,

    [Parameter()]
    [string]$Region,

    [Parameter()]
    [string]$ConfigurationPath = (Join-Path $PSScriptRoot 'config\geofence.settings.json'),

    [Parameter()]
    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'Modules\Geo.Sentinel\Geo.Sentinel.psm1') -Force

$decision = Invoke-GeofenceDecision -IPAddress $IPAddress -CountryCode $CountryCode -ASN $ASN -Region $Region -ConfigurationPath $ConfigurationPath

if ($AsJson) {
    $decision | ConvertTo-Json -Depth 10
}
else {
    $decision
}