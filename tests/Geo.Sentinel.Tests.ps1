BeforeAll {
    $repoRoot = Split-Path -Path $PSScriptRoot -Parent
    Import-Module (Join-Path $repoRoot 'Modules\Geo.Sentinel\Geo.Sentinel.psm1') -Force
    $configPath = Join-Path $repoRoot 'config\geofence.settings.json'
    $outputRoot = Join-Path $repoRoot 'Outputs'
}

Describe 'Provider loading' {
    It 'loads the configured providers' {
        $settings = Get-GeofenceSettings -Path $configPath
        $providers = Get-GeofenceProviders -Settings $settings

        $providers.Count | Should -Be 14
        ($providers | Where-Object Name -EQ 'OFAC').ProviderType | Should -Be 'Sanctions'
        ($providers | Where-Object Name -EQ 'ASNLookup').ProviderType | Should -Be 'ASNLookup'
    }

    It 'parses provider data into a normalized rule set' {
        $ruleSet = Get-GeofenceRuleSet -ConfigurationPath $configPath

        $ruleSet.SanctionsRules.Count | Should -BeGreaterThan 5
        $ruleSet.GeolocationData.Count | Should -BeGreaterThan 5
        $ruleSet.ThreatIntelData.Count | Should -BeGreaterThan 3
        $ruleSet.ASNLookupData.Count | Should -Be 4
    }
}

Describe 'Rule merge logic' {
    It 'keeps unique sanctions rules after merge' {
        $ruleSet = Get-GeofenceRuleSet -ConfigurationPath $configPath
        $keys = $ruleSet.SanctionsRules | ForEach-Object { '{0}|{1}|{2}|{3}|{4}' -f $_.ReasonCode, $_.CountryCode, $_.Region, $_.ASN, $_.Action }

        $keys.Count | Should -Be ($keys | Select-Object -Unique).Count
    }
}

Describe 'Decision engine' {
    It 'denies an OFAC country match' {
        $decision = Invoke-GeofenceDecision -IPAddress '198.51.100.10' -ConfigurationPath $configPath

        $decision.Decision | Should -Be 'Deny'
        $decision.CountryCode | Should -Be 'CU'
        $decision.ReasonCodes | Should -Contain 'OFAC_COUNTRY_MATCH'
    }

    It 'denies an OFAC region match when the caller provides a region override' {
        $decision = Invoke-GeofenceDecision -IPAddress '203.0.113.10' -CountryCode 'UA' -Region 'Crimea' -ConfigurationPath $configPath

        $decision.Decision | Should -Be 'Deny'
        $decision.ReasonCodes | Should -Contain 'OFAC_REGION_MATCH'
    }

    It 'detects tor indicators' {
        $decision = Invoke-GeofenceDecision -IPAddress '203.0.113.13' -ConfigurationPath $configPath

        $decision.Decision | Should -Be 'Deny'
        $decision.ReasonCodes | Should -Contain 'TOR_EXIT_NODE'
    }

    It 'detects datacenter ASNs through the ASN lookup provider' {
        $decision = Invoke-GeofenceDecision -IPAddress '203.0.113.25' -ConfigurationPath $configPath

        $decision.ASN | Should -Be '64520'
        $decision.Decision | Should -Be 'Review'
        $decision.ReasonCodes | Should -Contain 'DATACENTER_ASN'
    }

    It 'allows an address without sanctions or threat hits' {
        $decision = Invoke-GeofenceDecision -IPAddress '198.18.0.11' -ConfigurationPath $configPath

        $decision.Decision | Should -Be 'Allow'
        $decision.ReasonCodes.Count | Should -Be 0
    }
}

Describe 'Export generation' {
    It 'writes all configured export artifacts' {
        if (Test-Path $outputRoot) {
            Remove-Item -Path $outputRoot -Recurse -Force
        }

        $exports = Export-GeofenceArtifacts -ConfigurationPath $configPath

        $exports.Count | Should -Be 5
        foreach ($export in $exports) {
            Test-Path -Path $export.Path | Should -BeTrue
        }

        (Get-Content -Path (Join-Path $outputRoot 'firewall-cidr-blocklist.txt') -Raw) | Should -Match '198.51.100.0/24'
    }
}