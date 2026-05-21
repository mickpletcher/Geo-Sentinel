Set-StrictMode -Version Latest

function Ensure-GeofenceParentDirectory {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Path
    )

    $parent = Split-Path -Path $Path -Parent
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -Path $parent)) {
        New-Item -Path $parent -ItemType Directory -Force | Out-Null
    }
}

function Get-GeofenceRepositoryRoot {
    $moduleParent = Split-Path -Path $PSScriptRoot -Parent
    return Split-Path -Path $moduleParent -Parent
}

function Get-GeofenceDefaultSettingsPath {
    return Join-Path (Get-GeofenceRepositoryRoot) 'config\geofence.settings.json'
}

function Resolve-GeofencePath {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$BasePath,

        [Parameter(Mandatory)]
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $Path
    }

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    }

    return [System.IO.Path]::GetFullPath((Join-Path $BasePath $Path))
}

function ConvertTo-IPv4Integer {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$IPAddress
    )

    $address = [System.Net.IPAddress]::Parse($IPAddress)
    if ($address.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) {
        throw "Only IPv4 addresses are supported: $IPAddress"
    }

    $bytes = $address.GetAddressBytes()
    [array]::Reverse($bytes)
    return [BitConverter]::ToUInt32($bytes, 0)
}

function Test-IPAddressInCidr {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$IPAddress,

        [Parameter(Mandatory)]
        [string]$Cidr
    )

    $parts = $Cidr.Split('/')
    if ($parts.Count -ne 2) {
        throw "Invalid CIDR value: $Cidr"
    }

    $prefixLength = [int]$parts[1]
    if ($prefixLength -lt 0 -or $prefixLength -gt 32) {
        throw "Invalid CIDR prefix length: $Cidr"
    }

    $addressValue = ConvertTo-IPv4Integer -IPAddress $IPAddress
    $networkValue = ConvertTo-IPv4Integer -IPAddress $parts[0]
    $maskValue = if ($prefixLength -eq 0) { [uint32]0 } else { [uint32]::MaxValue -shl (32 - $prefixLength) }

    return (($addressValue -band $maskValue) -eq ($networkValue -band $maskValue))
}

function Get-GeofenceSettings {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$Path = (Get-GeofenceDefaultSettingsPath)
    )

    if (-not (Test-Path -Path $Path)) {
        throw "Settings file not found: $Path"
    }

    $resolvedPath = [System.IO.Path]::GetFullPath($Path)
    $basePath = Split-Path -Path $resolvedPath -Parent
    $settings = Get-Content -Path $resolvedPath -Raw | ConvertFrom-Json -Depth 20

    foreach ($provider in @($settings.Providers)) {
        if ($null -ne $provider.PSObject.Properties['LocalCachePath']) {
            $provider.LocalCachePath = Resolve-GeofencePath -BasePath $basePath -Path $provider.LocalCachePath
        }

        if ($null -ne $provider.PSObject.Properties['ExportPath'] -and -not [string]::IsNullOrWhiteSpace($provider.ExportPath)) {
            $provider.ExportPath = Resolve-GeofencePath -BasePath $basePath -Path $provider.ExportPath
        }
    }

    foreach ($formatPathProperty in 'Json', 'PowerShell', 'NginxMap', 'CloudflareRules', 'FirewallRules') {
        if ($settings.OutputPaths.PSObject.Properties.Name -contains $formatPathProperty) {
            $settings.OutputPaths.$formatPathProperty = Resolve-GeofencePath -BasePath $basePath -Path $settings.OutputPaths.$formatPathProperty
        }
    }

    $settings | Add-Member -NotePropertyName SettingsPath -NotePropertyValue $resolvedPath -Force
    return $settings
}

function New-GeofenceProvider {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [pscustomobject]$Definition,

        [Parameter(Mandatory)]
        [scriptblock]$FetchMethod,

        [Parameter(Mandatory)]
        [scriptblock]$ParseMethod,

        [Parameter(Mandatory)]
        [scriptblock]$ValidateMethod,

        [Parameter(Mandatory)]
        [scriptblock]$ExportMethod
    )

    $metadata = if ($Definition.PSObject.Properties.Name -contains 'Metadata') { $Definition.Metadata } else { $null }

    return [pscustomobject]@{
        Name              = $Definition.Name
        ProviderType      = $Definition.ProviderType
        Enabled           = [bool]$Definition.Enabled
        RefreshInterval   = [int]$Definition.RefreshIntervalHours
        SourceUrl         = $Definition.SourceUrl
        LocalCachePath    = $Definition.LocalCachePath
        LastUpdated       = $Definition.LastUpdated
        Fetch             = $FetchMethod
        Parse             = $ParseMethod
        Validate          = $ValidateMethod
        Export            = $ExportMethod
        Metadata          = $metadata
        Confidence        = if ($Definition.PSObject.Properties.Name -contains 'Confidence') { [int]$Definition.Confidence } else { 50 }
    }
}

function Get-ProviderFileData {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [pscustomobject]$Provider
    )

    if (-not (Test-Path -Path $Provider.LocalCachePath)) {
        throw "Provider cache path not found for $($Provider.Name): $($Provider.LocalCachePath)"
    }

    $item = Get-Item -Path $Provider.LocalCachePath
    if ($item.PSIsContainer) {
        return $item
    }

    return Get-Content -Path $Provider.LocalCachePath -Raw
}

function ConvertTo-NormalizedSanctionsRule {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$ProviderName,

        [Parameter(Mandatory)]
        [pscustomobject]$Rule,

        [Parameter()]
        [string]$DefaultReasonCode = 'CUSTOM_RULE_MATCH',

        [Parameter()]
        [string]$DefaultAction = 'Deny'
    )

    $countryCode = if ($Rule.PSObject.Properties.Name -contains 'country_code') { [string]$Rule.country_code } elseif ($Rule.PSObject.Properties.Name -contains 'CountryCode') { [string]$Rule.CountryCode } else { $null }
    $countryName = if ($Rule.PSObject.Properties.Name -contains 'country_name') { [string]$Rule.country_name } elseif ($Rule.PSObject.Properties.Name -contains 'CountryName') { [string]$Rule.CountryName } else { $null }
    $region = if ($Rule.PSObject.Properties.Name -contains 'region') { [string]$Rule.region } elseif ($Rule.PSObject.Properties.Name -contains 'Region') { [string]$Rule.Region } else { $null }
    $asn = if ($Rule.PSObject.Properties.Name -contains 'asn') { [string]$Rule.asn } elseif ($Rule.PSObject.Properties.Name -contains 'ASN') { [string]$Rule.ASN } else { $null }
    $action = if ($Rule.PSObject.Properties.Name -contains 'action') { [string]$Rule.action } elseif ($Rule.PSObject.Properties.Name -contains 'Action') { [string]$Rule.Action } else { $DefaultAction }
    $reasonCode = if ($Rule.PSObject.Properties.Name -contains 'reason_code') { [string]$Rule.reason_code } elseif ($Rule.PSObject.Properties.Name -contains 'ReasonCode') { [string]$Rule.ReasonCode } else { $DefaultReasonCode }
    $ruleId = if ($Rule.PSObject.Properties.Name -contains 'rule_id') { [string]$Rule.rule_id } elseif ($Rule.PSObject.Properties.Name -contains 'RuleId') { [string]$Rule.RuleId } else { "$ProviderName|$reasonCode|$countryCode|$region|$asn" }
    $metadata = if ($Rule.PSObject.Properties.Name -contains 'metadata') { $Rule.metadata } elseif ($Rule.PSObject.Properties.Name -contains 'Metadata') { $Rule.Metadata } else { [pscustomobject]@{} }

    return [pscustomobject]@{
        RuleId      = $ruleId
        RuleType    = 'Sanctions'
        Source      = $ProviderName
        CountryCode = if ([string]::IsNullOrWhiteSpace($countryCode)) { $null } else { $countryCode.ToUpperInvariant() }
        CountryName = $countryName
        Region      = $region
        ASN         = $asn
        Action      = $action
        ReasonCode  = $reasonCode
        Metadata    = $metadata
    }
}

function ConvertTo-NetworkEntry {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$ProviderName,

        [Parameter(Mandatory)]
        [pscustomobject]$Row,

        [Parameter()]
        [int]$DefaultConfidence = 50
    )

    $network = if ($Row.PSObject.Properties.Name -contains 'network') { [string]$Row.network } elseif ($Row.PSObject.Properties.Name -contains 'Network') { [string]$Row.Network } else { $null }
    $countryCode = if ($Row.PSObject.Properties.Name -contains 'country_code') { [string]$Row.country_code } elseif ($Row.PSObject.Properties.Name -contains 'CountryCode') { [string]$Row.CountryCode } else { $null }
    $region = if ($Row.PSObject.Properties.Name -contains 'region') { [string]$Row.region } elseif ($Row.PSObject.Properties.Name -contains 'Region') { [string]$Row.Region } else { $null }
    $confidence = if ($Row.PSObject.Properties.Name -contains 'confidence') { [int]$Row.confidence } elseif ($Row.PSObject.Properties.Name -contains 'Confidence') { [int]$Row.Confidence } else { $DefaultConfidence }
    $description = if ($Row.PSObject.Properties.Name -contains 'description') { [string]$Row.description } elseif ($Row.PSObject.Properties.Name -contains 'Description') { [string]$Row.Description } else { $null }

    return [pscustomobject]@{
        Provider    = $ProviderName
        Network     = $network
        CountryCode = if ([string]::IsNullOrWhiteSpace($countryCode)) { $null } else { $countryCode.ToUpperInvariant() }
        Region      = $region
        Confidence  = $confidence
        Description = $description
    }
}

function ConvertTo-IndicatorEntry {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$ProviderName,

        [Parameter(Mandatory)]
        [string]$ReasonCode,

        [Parameter(Mandatory)]
        [pscustomobject]$Row
    )

    return [pscustomobject]@{
        Provider    = $ProviderName
        ReasonCode  = $ReasonCode
        IPAddress   = if ($Row.PSObject.Properties.Name -contains 'ip_address') { [string]$Row.ip_address } elseif ($Row.PSObject.Properties.Name -contains 'IPAddress') { [string]$Row.IPAddress } else { $null }
        Network     = if ($Row.PSObject.Properties.Name -contains 'network') { [string]$Row.network } elseif ($Row.PSObject.Properties.Name -contains 'Network') { [string]$Row.Network } else { $null }
        ASN         = if ($Row.PSObject.Properties.Name -contains 'asn') { [string]$Row.asn } elseif ($Row.PSObject.Properties.Name -contains 'ASN') { [string]$Row.ASN } else { $null }
        Description = if ($Row.PSObject.Properties.Name -contains 'description') { [string]$Row.description } elseif ($Row.PSObject.Properties.Name -contains 'Description') { [string]$Row.Description } else { $null }
    }
}

function Merge-GeofenceRules {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Rules
    )

    $seen = [System.Collections.Generic.HashSet[string]]::new()
    $merged = foreach ($rule in $Rules) {
        $key = "{0}|{1}|{2}|{3}|{4}" -f $rule.ReasonCode, $rule.CountryCode, $rule.Region, $rule.ASN, $rule.Action
        if ($seen.Add($key)) {
            $rule
        }
    }

    return @($merged | Sort-Object ReasonCode, CountryCode, Region, ASN, Source)
}

function Invoke-GeofenceProvider {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [pscustomobject]$Provider
    )

    if (-not $Provider.Enabled) {
        return [pscustomobject]@{
            Provider = $Provider
            Succeeded = $true
            Skipped = $true
            Data = @()
            Error = $null
        }
    }

    try {
        $rawData = & $Provider.Fetch $Provider
        $parsedData = & $Provider.Parse $Provider $rawData
        $isValid = & $Provider.Validate $Provider $parsedData
        if (-not $isValid) {
            throw "Provider validation failed for $($Provider.Name)"
        }

        return [pscustomobject]@{
            Provider = $Provider
            Succeeded = $true
            Skipped = $false
            Data = @($parsedData)
            Error = $null
        }
    }
    catch {
        Write-Warning "Provider $($Provider.Name) failed: $_"
        return [pscustomobject]@{
            Provider = $Provider
            Succeeded = $false
            Skipped = $false
            Data = @()
            Error = $_.Exception.Message
        }
    }
}

function Get-GeofenceProviders {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [pscustomobject]$Settings
    )

    $providers = foreach ($definition in @($Settings.Providers)) {
        switch ($definition.Name) {
            'OFAC' {
                New-GeofenceProvider -Definition $definition -FetchMethod ${function:Get-ProviderFileData} -ParseMethod {
                    param($provider, $rawData)
                    $items = $rawData | ConvertFrom-Json -Depth 10
                    foreach ($item in @($items)) {
                        ConvertTo-NormalizedSanctionsRule -ProviderName $provider.Name -Rule $item -DefaultReasonCode 'OFAC_COUNTRY_MATCH'
                    }
                } -ValidateMethod {
                    param($provider, $parsedData)
                    return @($parsedData).Count -gt 0
                } -ExportMethod {
                    param($provider, $data, $path)
                    $data | ConvertTo-Json -Depth 10 | Set-Content -Path $path -Encoding UTF8
                }
            }
            'EU' {
                New-GeofenceProvider -Definition $definition -FetchMethod ${function:Get-ProviderFileData} -ParseMethod {
                    param($provider, $rawData)
                    $items = $rawData | ConvertFrom-Json -Depth 10
                    foreach ($item in @($items)) {
                        ConvertTo-NormalizedSanctionsRule -ProviderName $provider.Name -Rule $item -DefaultReasonCode 'EU_SANCTIONS_MATCH'
                    }
                } -ValidateMethod {
                    param($provider, $parsedData)
                    return @($parsedData).Count -gt 0
                } -ExportMethod {
                    param($provider, $data, $path)
                    $data | ConvertTo-Json -Depth 10 | Set-Content -Path $path -Encoding UTF8
                }
            }
            'UK' {
                New-GeofenceProvider -Definition $definition -FetchMethod ${function:Get-ProviderFileData} -ParseMethod {
                    param($provider, $rawData)
                    $items = $rawData | ConvertFrom-Json -Depth 10
                    foreach ($item in @($items)) {
                        ConvertTo-NormalizedSanctionsRule -ProviderName $provider.Name -Rule $item -DefaultReasonCode 'UK_SANCTIONS_MATCH'
                    }
                } -ValidateMethod {
                    param($provider, $parsedData)
                    return @($parsedData).Count -gt 0
                } -ExportMethod {
                    param($provider, $data, $path)
                    $data | ConvertTo-Json -Depth 10 | Set-Content -Path $path -Encoding UTF8
                }
            }
            'Custom' {
                New-GeofenceProvider -Definition $definition -FetchMethod ${function:Get-ProviderFileData} -ParseMethod {
                    param($provider, $rawData)
                    $items = $rawData | ConvertFrom-Json -Depth 10
                    foreach ($item in @($items)) {
                        ConvertTo-NormalizedSanctionsRule -ProviderName $provider.Name -Rule $item -DefaultReasonCode 'CUSTOM_RULE_MATCH' -DefaultAction 'Review'
                    }
                } -ValidateMethod {
                    param($provider, $parsedData)
                    return $null -ne $parsedData
                } -ExportMethod {
                    param($provider, $data, $path)
                    $data | ConvertTo-Json -Depth 10 | Set-Content -Path $path -Encoding UTF8
                }
            }
            'HighRisk' {
                New-GeofenceProvider -Definition $definition -FetchMethod ${function:Get-ProviderFileData} -ParseMethod {
                    param($provider, $rawData)
                    $items = $rawData | ConvertFrom-Json -Depth 10
                    foreach ($item in @($items)) {
                        ConvertTo-NormalizedSanctionsRule -ProviderName $provider.Name -Rule $item -DefaultReasonCode 'HIGH_RISK_COUNTRY' -DefaultAction 'Review'
                    }
                } -ValidateMethod {
                    param($provider, $parsedData)
                    return $null -ne $parsedData
                } -ExportMethod {
                    param($provider, $data, $path)
                    $data | ConvertTo-Json -Depth 10 | Set-Content -Path $path -Encoding UTF8
                }
            }
            'MaxMind' {
                New-GeofenceProvider -Definition $definition -FetchMethod ${function:Get-ProviderFileData} -ParseMethod {
                    param($provider, $rawData)
                    foreach ($row in @($rawData | ConvertFrom-Csv)) {
                        ConvertTo-NetworkEntry -ProviderName $provider.Name -Row $row -DefaultConfidence $provider.Confidence
                    }
                } -ValidateMethod {
                    param($provider, $parsedData)
                    return @($parsedData | Where-Object { $_.Network }).Count -gt 0
                } -ExportMethod {
                    param($provider, $data, $path)
                    $data | Export-Csv -Path $path -NoTypeInformation -Encoding UTF8
                }
            }
            'IP2Location' {
                New-GeofenceProvider -Definition $definition -FetchMethod ${function:Get-ProviderFileData} -ParseMethod {
                    param($provider, $rawData)
                    foreach ($row in @($rawData | ConvertFrom-Csv)) {
                        ConvertTo-NetworkEntry -ProviderName $provider.Name -Row $row -DefaultConfidence $provider.Confidence
                    }
                } -ValidateMethod {
                    param($provider, $parsedData)
                    return $null -ne $parsedData
                } -ExportMethod {
                    param($provider, $data, $path)
                    $data | Export-Csv -Path $path -NoTypeInformation -Encoding UTF8
                }
            }
            'DBIP' {
                New-GeofenceProvider -Definition $definition -FetchMethod ${function:Get-ProviderFileData} -ParseMethod {
                    param($provider, $rawData)
                    foreach ($row in @($rawData | ConvertFrom-Csv)) {
                        ConvertTo-NetworkEntry -ProviderName $provider.Name -Row $row -DefaultConfidence $provider.Confidence
                    }
                } -ValidateMethod {
                    param($provider, $parsedData)
                    return $null -ne $parsedData
                } -ExportMethod {
                    param($provider, $data, $path)
                    $data | Export-Csv -Path $path -NoTypeInformation -Encoding UTF8
                }
            }
            'ipdeny' {
                New-GeofenceProvider -Definition $definition -FetchMethod ${function:Get-ProviderFileData} -ParseMethod {
                    param($provider, $rawData)
                    $zoneFiles = Get-ChildItem -Path $provider.LocalCachePath -Filter '*.zone' | Sort-Object Name
                    foreach ($zoneFile in $zoneFiles) {
                        $countryCode = [System.IO.Path]::GetFileNameWithoutExtension($zoneFile.Name).ToUpperInvariant()
                        foreach ($line in @(Get-Content -Path $zoneFile.FullName | Where-Object { $_ -and $_.Trim() })) {
                            [pscustomobject]@{
                                Provider = $provider.Name
                                Network = $line.Trim()
                                CountryCode = $countryCode
                                Region = $null
                                Confidence = $provider.Confidence
                                Description = 'ipdeny country CIDR'
                            }
                        }
                    }
                } -ValidateMethod {
                    param($provider, $parsedData)
                    return @($parsedData).Count -gt 0
                } -ExportMethod {
                    param($provider, $data, $path)
                    $data | Export-Csv -Path $path -NoTypeInformation -Encoding UTF8
                }
            }
            'Tor' {
                New-GeofenceProvider -Definition $definition -FetchMethod ${function:Get-ProviderFileData} -ParseMethod {
                    param($provider, $rawData)
                    foreach ($line in @($rawData -split "`r?`n" | Where-Object { $_ -and $_.Trim() })) {
                        [pscustomobject]@{
                            Provider = $provider.Name
                            ReasonCode = 'TOR_EXIT_NODE'
                            IPAddress = $line.Trim()
                            Network = $null
                            ASN = $null
                            Description = 'Tor exit node'
                        }
                    }
                } -ValidateMethod {
                    param($provider, $parsedData)
                    return @($parsedData).Count -gt 0
                } -ExportMethod {
                    param($provider, $data, $path)
                    $data | Set-Content -Path $path -Encoding UTF8
                }
            }
            'VPN' {
                New-GeofenceProvider -Definition $definition -FetchMethod ${function:Get-ProviderFileData} -ParseMethod {
                    param($provider, $rawData)
                    $items = $rawData | ConvertFrom-Json -Depth 10
                    foreach ($item in @($items)) {
                        ConvertTo-IndicatorEntry -ProviderName $provider.Name -ReasonCode 'VPN_DETECTED' -Row $item
                    }
                } -ValidateMethod {
                    param($provider, $parsedData)
                    return $null -ne $parsedData
                } -ExportMethod {
                    param($provider, $data, $path)
                    $data | ConvertTo-Json -Depth 10 | Set-Content -Path $path -Encoding UTF8
                }
            }
            'Proxy' {
                New-GeofenceProvider -Definition $definition -FetchMethod ${function:Get-ProviderFileData} -ParseMethod {
                    param($provider, $rawData)
                    $items = $rawData | ConvertFrom-Json -Depth 10
                    foreach ($item in @($items)) {
                        ConvertTo-IndicatorEntry -ProviderName $provider.Name -ReasonCode 'PROXY_DETECTED' -Row $item
                    }
                } -ValidateMethod {
                    param($provider, $parsedData)
                    return $null -ne $parsedData
                } -ExportMethod {
                    param($provider, $data, $path)
                    $data | ConvertTo-Json -Depth 10 | Set-Content -Path $path -Encoding UTF8
                }
            }
            'Datacenter' {
                New-GeofenceProvider -Definition $definition -FetchMethod ${function:Get-ProviderFileData} -ParseMethod {
                    param($provider, $rawData)
                    $items = $rawData | ConvertFrom-Json -Depth 10
                    foreach ($item in @($items)) {
                        ConvertTo-IndicatorEntry -ProviderName $provider.Name -ReasonCode 'DATACENTER_ASN' -Row $item
                    }
                } -ValidateMethod {
                    param($provider, $parsedData)
                    return $null -ne $parsedData
                } -ExportMethod {
                    param($provider, $data, $path)
                    $data | ConvertTo-Json -Depth 10 | Set-Content -Path $path -Encoding UTF8
                }
            }
            'ASNLookup' {
                New-GeofenceProvider -Definition $definition -FetchMethod ${function:Get-ProviderFileData} -ParseMethod {
                    param($provider, $rawData)
                    foreach ($row in @($rawData | ConvertFrom-Csv)) {
                        [pscustomobject]@{
                            Provider = $provider.Name
                            Network = $row.network
                            ASN = [string]$row.asn
                            Description = $row.description
                            Type = $row.type
                            Confidence = if ($row.PSObject.Properties.Name -contains 'confidence') { [int]$row.confidence } else { $provider.Confidence }
                        }
                    }
                } -ValidateMethod {
                    param($provider, $parsedData)
                    return @($parsedData).Count -gt 0
                } -ExportMethod {
                    param($provider, $data, $path)
                    $data | Export-Csv -Path $path -NoTypeInformation -Encoding UTF8
                }
            }
            default {
                throw "Unsupported provider definition: $($definition.Name)"
            }
        }
    }

    return @($providers)
}

function Get-GeofenceRuleSet {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$ConfigurationPath = (Get-GeofenceDefaultSettingsPath)
    )

    $settings = Get-GeofenceSettings -Path $ConfigurationPath
    $providers = Get-GeofenceProviders -Settings $settings
    $results = foreach ($provider in $providers) {
        Invoke-GeofenceProvider -Provider $provider
    }

    $rules = @($results | Where-Object { $_.Succeeded -and $_.Provider.ProviderType -eq 'Sanctions' } | ForEach-Object { $_.Data })
    $geolocation = @($results | Where-Object { $_.Succeeded -and $_.Provider.ProviderType -eq 'Geolocation' } | ForEach-Object { $_.Data })
    $threatIntel = @($results | Where-Object { $_.Succeeded -and $_.Provider.ProviderType -eq 'ThreatIntel' } | ForEach-Object { $_.Data })
    $asnLookup = @($results | Where-Object { $_.Succeeded -and $_.Provider.ProviderType -eq 'ASNLookup' } | ForEach-Object { $_.Data })

    return [pscustomobject]@{
        Settings = $settings
        Providers = $providers
        ProviderResults = $results
        SanctionsRules = Merge-GeofenceRules -Rules $rules
        GeolocationData = $geolocation
        ThreatIntelData = $threatIntel
        ASNLookupData = $asnLookup
    }
}

function Resolve-GeolocationRecord {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$IPAddress,

        [Parameter(Mandatory)]
        [object[]]$GeolocationData,

        [Parameter(Mandatory)]
        [object[]]$ProviderOrder
    )

    foreach ($providerName in $ProviderOrder) {
        $candidate = $GeolocationData |
            Where-Object { $_.Provider -eq $providerName } |
            Where-Object { Test-IPAddressInCidr -IPAddress $IPAddress -Cidr $_.Network } |
            Sort-Object Confidence -Descending |
            Select-Object -First 1

        if ($candidate) {
            return $candidate
        }
    }

    return $null
}

function Resolve-AsnRecord {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$IPAddress,

        [Parameter(Mandatory)]
        [object[]]$ASNLookupData
    )

    return $ASNLookupData |
        Where-Object { Test-IPAddressInCidr -IPAddress $IPAddress -Cidr $_.Network } |
        Sort-Object Confidence -Descending |
        Select-Object -First 1
}

function Get-IndicatorMatches {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$IPAddress,

        [Parameter()]
        [string]$ASN,

        [Parameter(Mandatory)]
        [object[]]$ThreatIntelData
    )

    return @(
        $ThreatIntelData | Where-Object {
            ($_.IPAddress -and $_.IPAddress -eq $IPAddress) -or
            ($_.Network -and (Test-IPAddressInCidr -IPAddress $IPAddress -Cidr $_.Network)) -or
            ($ASN -and $_.ASN -and $_.ASN -eq $ASN)
        }
    )
}

function New-DecisionMatch {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$ReasonCode,

        [Parameter(Mandatory)]
        [string]$Source,

        [Parameter(Mandatory)]
        [string]$Action,

        [Parameter()]
        [object]$Rule,

        [Parameter()]
        [string]$Detail
    )

    return [pscustomobject]@{
        ReasonCode = $ReasonCode
        Source = $Source
        Action = $Action
        Rule = $Rule
        Detail = $Detail
    }
}

function Get-RuleMatches {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$CountryCode,

        [Parameter()]
        [string]$Region,

        [Parameter()]
        [string]$ASN,

        [Parameter(Mandatory)]
        [object[]]$SanctionsRules
    )

    $matches = foreach ($rule in $SanctionsRules) {
        $countryMatch = $rule.CountryCode -and $CountryCode -and ($rule.CountryCode -eq $CountryCode)
        $regionMatch = $rule.Region -and $Region -and ($rule.Region -eq $Region)
        $asnMatch = $rule.ASN -and $ASN -and ($rule.ASN -eq $ASN)

        if ($countryMatch -or $regionMatch -or $asnMatch) {
            $detail = if ($rule.CountryCode) { $rule.CountryCode } elseif ($rule.Region) { $rule.Region } else { $rule.ASN }
            New-DecisionMatch -ReasonCode $rule.ReasonCode -Source $rule.Source -Action $rule.Action -Rule $rule -Detail $detail
        }
    }

    return @($matches)
}

function Get-ConfigurationMatches {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [pscustomobject]$Settings,

        [Parameter()]
        [string]$CountryCode,

        [Parameter()]
        [string]$Region,

        [Parameter()]
        [string]$ASN
    )

    $matches = [System.Collections.Generic.List[object]]::new()

    if ($CountryCode -and @($Settings.CountryDenylist) -contains $CountryCode) {
        [void]$matches.Add((New-DecisionMatch -ReasonCode 'CUSTOM_RULE_MATCH' -Source 'Configuration' -Action 'Deny' -Detail $CountryCode))
    }

    if ($Region -and @($Settings.RegionDenylist) -contains $Region) {
        [void]$matches.Add((New-DecisionMatch -ReasonCode 'CUSTOM_RULE_MATCH' -Source 'Configuration' -Action 'Deny' -Detail $Region))
    }

    if ($ASN -and @($Settings.AsnDenylist) -contains $ASN) {
        [void]$matches.Add((New-DecisionMatch -ReasonCode 'CUSTOM_RULE_MATCH' -Source 'Configuration' -Action 'Deny' -Detail $ASN))
    }

    return @($matches)
}

function Get-ConfidenceScore {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$CountryCode,

        [Parameter()]
        [string]$ProvidedCountryCode,

        [Parameter()]
        [string]$Region,

        [Parameter()]
        [string]$ProvidedRegion,

        [Parameter()]
        [string]$ASN,

        [Parameter()]
        [string]$ProvidedASN,

        [Parameter()]
        [object]$GeolocationRecord,

        [Parameter()]
        [hashtable]$ProviderMetadata
    )

    $score = 35

    if ($GeolocationRecord) {
        $score += [Math]::Min([int]$GeolocationRecord.Confidence, 45)
    }

    if ($CountryCode -and $ProvidedCountryCode) {
        $score += 15
    }

    if ($Region -and $ProvidedRegion) {
        $score += 20
    }

    if ($ASN -and $ProvidedASN) {
        $score += 10
    }

    if ($ProviderMetadata -and $ProviderMetadata.Count -gt 0) {
        $score += 5
    }

    return [Math]::Min($score, 100)
}

function Invoke-GeofenceDecision {
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
        [hashtable]$ProviderMetadata,

        [Parameter()]
        [string]$ConfigurationPath = (Get-GeofenceDefaultSettingsPath)
    )

    $ruleSet = Get-GeofenceRuleSet -ConfigurationPath $ConfigurationPath
    $settings = $ruleSet.Settings
    $providerOrder = @($settings.ProviderPrecedence.Geolocation)

    $geolocationRecord = $null
    if (-not $CountryCode) {
        $geolocationRecord = Resolve-GeolocationRecord -IPAddress $IPAddress -GeolocationData $ruleSet.GeolocationData -ProviderOrder $providerOrder
        if ($geolocationRecord) {
            $CountryCode = $geolocationRecord.CountryCode
            if (-not $Region) {
                $Region = $geolocationRecord.Region
            }
        }
    }

    if (-not $ASN) {
        $asnRecord = Resolve-AsnRecord -IPAddress $IPAddress -ASNLookupData $ruleSet.ASNLookupData
        if ($asnRecord) {
            $ASN = $asnRecord.ASN
        }
    }
    else {
        $asnRecord = $null
    }

    $matches = [System.Collections.Generic.List[object]]::new()

    foreach ($match in @(Get-RuleMatches -CountryCode $CountryCode -Region $Region -ASN $ASN -SanctionsRules $ruleSet.SanctionsRules)) {
        [void]$matches.Add($match)
    }

    foreach ($match in @(Get-ConfigurationMatches -Settings $settings -CountryCode $CountryCode -Region $Region -ASN $ASN)) {
        [void]$matches.Add($match)
    }

    foreach ($indicator in @(Get-IndicatorMatches -IPAddress $IPAddress -ASN $ASN -ThreatIntelData $ruleSet.ThreatIntelData)) {
        switch ($indicator.ReasonCode) {
            'TOR_EXIT_NODE' {
                if ($settings.TorBlocking) {
                    [void]$matches.Add((New-DecisionMatch -ReasonCode $indicator.ReasonCode -Source $indicator.Provider -Action 'Deny' -Rule $indicator -Detail $indicator.IPAddress))
                }
            }
            'VPN_DETECTED' {
                if ($settings.VpnBlocking) {
                    $detail = if ($indicator.IPAddress) { $indicator.IPAddress } else { $indicator.Network }
                    [void]$matches.Add((New-DecisionMatch -ReasonCode $indicator.ReasonCode -Source $indicator.Provider -Action 'Review' -Rule $indicator -Detail $detail))
                }
            }
            'PROXY_DETECTED' {
                if ($settings.ProxyBlocking) {
                    $detail = if ($indicator.IPAddress) { $indicator.IPAddress } else { $indicator.Network }
                    [void]$matches.Add((New-DecisionMatch -ReasonCode $indicator.ReasonCode -Source $indicator.Provider -Action 'Review' -Rule $indicator -Detail $detail))
                }
            }
            'DATACENTER_ASN' {
                if ($settings.DatacenterBlocking) {
                    $detail = if ($indicator.ASN) { $indicator.ASN } else { $indicator.Network }
                    [void]$matches.Add((New-DecisionMatch -ReasonCode $indicator.ReasonCode -Source $indicator.Provider -Action 'Review' -Rule $indicator -Detail $detail))
                }
            }
        }
    }

    $confidenceScore = Get-ConfidenceScore -CountryCode $CountryCode -ProvidedCountryCode $PSBoundParameters['CountryCode'] -Region $Region -ProvidedRegion $PSBoundParameters['Region'] -ASN $ASN -ProvidedASN $PSBoundParameters['ASN'] -GeolocationRecord $geolocationRecord -ProviderMetadata $ProviderMetadata

    $hasHardDeny = @($matches | Where-Object { $_.Action -eq 'Deny' }).Count -gt 0
    $hasReview = @($matches | Where-Object { $_.Action -eq 'Review' }).Count -gt 0

    if (($hasHardDeny -or $hasReview) -and ($settings.ReviewInsteadOfDenyMode -or ($settings.StrictComplianceMode -and $confidenceScore -lt 60))) {
        $decision = 'Review'
    }
    elseif ($hasHardDeny) {
        $decision = 'Deny'
    }
    elseif ($hasReview) {
        $decision = 'Review'
    }
    else {
        $decision = 'Allow'
    }

    if ($decision -eq 'Allow' -and $CountryCode -and @($settings.CountryAllowlist).Count -gt 0 -and @($settings.CountryAllowlist) -notcontains $CountryCode) {
        $decision = if ($settings.StrictComplianceMode) { 'Review' } else { 'Allow' }
    }

    $sourceProviders = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($match in @($matches)) {
        [void]$sourceProviders.Add($match.Source)
    }

    if ($geolocationRecord) {
        [void]$sourceProviders.Add($geolocationRecord.Provider)
    }

    if ($asnRecord) {
        [void]$sourceProviders.Add($asnRecord.Provider)
    }

    return [pscustomobject]@{
        IPAddress = $IPAddress
        CountryCode = $CountryCode
        Region = $Region
        ASN = $ASN
        Decision = $decision
        ReasonCodes = @($matches | Select-Object -ExpandProperty ReasonCode -Unique)
        MatchedRules = @($matches | Select-Object -ExpandProperty Rule)
        SourceProviders = @($sourceProviders)
        ConfidenceScore = $confidenceScore
        ProviderMetadata = $ProviderMetadata
    }
}

function Get-DenyCountryCodes {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [pscustomobject]$RuleSet
    )

    $codes = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($rule in @($RuleSet.SanctionsRules | Where-Object { $_.Action -eq 'Deny' -and $_.CountryCode })) {
        [void]$codes.Add($rule.CountryCode)
    }

    foreach ($code in @($RuleSet.Settings.CountryDenylist)) {
        [void]$codes.Add([string]$code)
    }

    return @($codes | Sort-Object)
}

function Export-GeofenceJson {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [pscustomobject]$RuleSet,

        [Parameter(Mandatory)]
        [string]$Path
    )

    Ensure-GeofenceParentDirectory -Path $Path

    $payload = [pscustomobject]@{
        GeneratedAt = (Get-Date).ToString('s')
        SanctionsRules = $RuleSet.SanctionsRules
        EnabledProviders = @($RuleSet.Providers | Where-Object Enabled | Select-Object -ExpandProperty Name)
        Settings = [pscustomobject]@{
            CountryAllowlist = @($RuleSet.Settings.CountryAllowlist)
            CountryDenylist = @($RuleSet.Settings.CountryDenylist)
            RegionDenylist = @($RuleSet.Settings.RegionDenylist)
            AsnDenylist = @($RuleSet.Settings.AsnDenylist)
            StrictComplianceMode = [bool]$RuleSet.Settings.StrictComplianceMode
            ReviewInsteadOfDenyMode = [bool]$RuleSet.Settings.ReviewInsteadOfDenyMode
        }
    }

    $payload | ConvertTo-Json -Depth 20 | Set-Content -Path $Path -Encoding UTF8
    return $Path
}

function Export-GeofencePowerShellObjects {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [pscustomobject]$RuleSet,

        [Parameter(Mandatory)]
        [string]$Path
    )

    Ensure-GeofenceParentDirectory -Path $Path
    $RuleSet | Export-Clixml -Path $Path
    return $Path
}

function Export-GeofenceNginxMap {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [pscustomobject]$RuleSet,

        [Parameter(Mandatory)]
        [string]$Path
    )

    Ensure-GeofenceParentDirectory -Path $Path
    $lines = [System.Collections.Generic.List[string]]::new()
    [void]$lines.Add('map $geoip2_data_country_code $geofence_decision {')
    [void]$lines.Add('    default allow;')

    foreach ($rule in @($RuleSet.SanctionsRules | Where-Object { $_.CountryCode })) {
        $decision = if ($rule.Action -eq 'Review') { 'review' } else { 'deny' }
        [void]$lines.Add("    $($rule.CountryCode) $decision;")
    }

    foreach ($code in @($RuleSet.Settings.CountryDenylist | Sort-Object -Unique)) {
        [void]$lines.Add("    $code deny;")
    }

    [void]$lines.Add('}')
    $lines | Set-Content -Path $Path -Encoding UTF8
    return $Path
}

function Export-GeofenceCloudflareRules {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [pscustomobject]$RuleSet,

        [Parameter(Mandatory)]
        [string]$Path
    )

    Ensure-GeofenceParentDirectory -Path $Path
    $countryCodes = Get-DenyCountryCodes -RuleSet $RuleSet
    $expression = if ($countryCodes.Count -gt 0) {
        '(ip.geoip.country in {' + (($countryCodes | ForEach-Object { '"' + $_ + '"' }) -join ' ') + '})'
    }
    else {
        '(ip.geoip.country in {})'
    }

    [pscustomobject]@{
        action = 'block'
        expression = $expression
        description = 'OFAC GeoFence generated country block rule'
    } | ConvertTo-Json -Depth 10 | Set-Content -Path $Path -Encoding UTF8

    return $Path
}

function Export-GeofenceFirewallRules {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [pscustomobject]$RuleSet,

        [Parameter(Mandatory)]
        [string]$Path
    )

    Ensure-GeofenceParentDirectory -Path $Path
    $countryCodes = Get-DenyCountryCodes -RuleSet $RuleSet
    $cidrs = $RuleSet.GeolocationData |
        Where-Object { $_.Provider -eq 'ipdeny' -and $_.CountryCode -in $countryCodes } |
        Select-Object -ExpandProperty Network -Unique |
        Sort-Object

    $cidrs | Set-Content -Path $Path -Encoding UTF8
    return $Path
}

function Export-GeofenceArtifacts {
    [CmdletBinding()]
    param (
        [Parameter()]
        [string]$ConfigurationPath = (Get-GeofenceDefaultSettingsPath),

        [Parameter()]
        [string[]]$Formats
    )

    $ruleSet = Get-GeofenceRuleSet -ConfigurationPath $ConfigurationPath
    $selectedFormats = if ($Formats) { $Formats } else { @($ruleSet.Settings.OutputFormats) }
    $outputs = [System.Collections.Generic.List[object]]::new()

    foreach ($format in $selectedFormats) {
        switch ($format) {
            'JSON' {
                [void]$outputs.Add([pscustomobject]@{ Format = $format; Path = (Export-GeofenceJson -RuleSet $ruleSet -Path $ruleSet.Settings.OutputPaths.Json) })
            }
            'PowerShell' {
                [void]$outputs.Add([pscustomobject]@{ Format = $format; Path = (Export-GeofencePowerShellObjects -RuleSet $ruleSet -Path $ruleSet.Settings.OutputPaths.PowerShell) })
            }
            'NginxMap' {
                [void]$outputs.Add([pscustomobject]@{ Format = $format; Path = (Export-GeofenceNginxMap -RuleSet $ruleSet -Path $ruleSet.Settings.OutputPaths.NginxMap) })
            }
            'CloudflareRules' {
                [void]$outputs.Add([pscustomobject]@{ Format = $format; Path = (Export-GeofenceCloudflareRules -RuleSet $ruleSet -Path $ruleSet.Settings.OutputPaths.CloudflareRules) })
            }
            'FirewallRules' {
                [void]$outputs.Add([pscustomobject]@{ Format = $format; Path = (Export-GeofenceFirewallRules -RuleSet $ruleSet -Path $ruleSet.Settings.OutputPaths.FirewallRules) })
            }
            default {
                throw "Unsupported output format: $format"
            }
        }
    }

    return @($outputs)
}

Export-ModuleMember -Function @(
    'Export-GeofenceArtifacts',
    'Export-GeofenceCloudflareRules',
    'Export-GeofenceFirewallRules',
    'Export-GeofenceJson',
    'Export-GeofenceNginxMap',
    'Export-GeofencePowerShellObjects',
    'Get-GeofenceDefaultSettingsPath',
    'Get-GeofenceProviders',
    'Get-GeofenceRuleSet',
    'Get-GeofenceSettings',
    'Invoke-GeofenceDecision',
    'Invoke-GeofenceProvider',
    'Merge-GeofenceRules',
    'New-GeofenceProvider',
    'Resolve-GeofencePath',
    'Test-IPAddressInCidr'
)