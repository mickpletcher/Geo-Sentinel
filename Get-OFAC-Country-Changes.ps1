<#
.SYNOPSIS
    Monitors the OFAC Consolidated Sanctions List for country-level changes
    and flags new or removed countries suitable for geofencing policy updates.

.DESCRIPTION
    Downloads the OFAC Consolidated Sanctions List CSV, extracts unique sanctioned
    countries, maps them to ISO 3166-1 alpha-2 codes, compares against a stored
    baseline, and reports any additions or removals. Designed to be run on a
    schedule (daily/weekly) as part of an automated geofencing policy pipeline.

    Output includes:
      - Console summary of changes
      - Updated baseline JSON file
      - Optional text file of ISO codes ready for ipverse/country-ip-blocks
      - Optional webhook notification on detected changes

.PARAMETER BaselinePath
    Path to the JSON baseline file used for change comparison.
    Defaults to .\OFACCountryBaseline.json

.PARAMETER OutputPath
    Directory where updated baseline and ISO code list are written.
    Defaults to the script root.

.PARAMETER ExportIsoCodes
    Writes a CSV file (country_code,country_name) of ISO codes. Enabled by default.

.PARAMETER ExportIsoCodeList
    Writes a plain-text file of ISO codes only, one per line. For use with
    ipverse/country-ip-blocks or similar geofencing tools.

.PARAMETER SkipIfNoChanges
    Exit cleanly with a log entry but no console output when no additions or
    removals are detected. Reduces noise in scheduled task logs during stable periods.

.PARAMETER WebhookUrl
    When specified, POSTs a JSON change summary to this URL when additions
    or removals are detected. Compatible with Slack incoming webhooks,
    Microsoft Teams connectors, or any custom HTTP endpoint.

.PARAMETER WhatIf
    Shows what would change without writing any files.

.EXAMPLE
    .\Get-OFAC-Country-Changes.ps1
    Compares current OFAC list against the stored baseline and reports changes.

.EXAMPLE
    .\Get-OFAC-Country-Changes.ps1 -ExportIsoCodes -OutputPath C:\Geofence
    Runs comparison and exports an ISO code list to C:\Geofence.

.EXAMPLE
    .\Get-OFAC-Country-Changes.ps1 -WebhookUrl 'https://hooks.slack.com/services/...'
    Runs comparison and POSTs a notification if changes are detected.

.NOTES
    Created on  : 2026-05-15
    Created by  : Mick Pletcher
    Organization:
    Filename    : Get-OFACCountryChanges.ps1

    Data source : https://www.treasury.gov/ofac/downloads/add.csv
    OFAC page   : https://ofac.treasury.gov/sanctions-programs-and-country-information
#>

[CmdletBinding(SupportsShouldProcess)]
param (
    [Parameter()]
    [string]$BaselinePath = (Join-Path $PSScriptRoot 'OFACCountryBaseline.json'),

    [Parameter()]
    [string]$OutputPath = $PSScriptRoot,

    [Parameter()]
    [switch]$ExportIsoCodes = $true,

    [Parameter()]
    [switch]$ExportIsoCodeList,

    [Parameter()]
    [switch]$SkipIfNoChanges,

    [Parameter()]
    [string]$WebhookUrl
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

#==============================================================================================
# Constants
#==============================================================================================

$OFACUrl          = 'https://www.treasury.gov/ofac/downloads/add.csv'
$LogFile          = Join-Path $OutputPath 'Get-OFACCountryChanges.log'
$IsoCodeFile      = Join-Path $OutputPath 'OFACGeofenceIsoCodes.csv'
$IsoCodeListFile  = Join-Path $OutputPath 'OFACGeofenceIsoCodes.txt'
$UnmappedFile     = Join-Path $OutputPath 'OFACUnmappedCountries.txt'

# ISO 3166-1 alpha-2 map for OFAC country name strings
# Add entries as OFAC introduces new naming conventions
$IsoMap = @{
    'Afghanistan'                          = 'AF'
    'Albania'                              = 'AL'
    'Belarus'                              = 'BY'
    'Bosnia and Herzegovina'               = 'BA'
    'Burma'                                = 'MM'
    'Central African Republic'             = 'CF'
    'China'                                = 'CN'
    'Congo, Democratic Republic of the'   = 'CD'
    'Congo, Republic of the'              = 'CG'
    'Cuba'                                 = 'CU'
    'Eritrea'                              = 'ER'
    'Ethiopia'                             = 'ET'
    'Haiti'                                = 'HT'
    'Hong Kong'                            = 'HK'
    'Iran'                                 = 'IR'
    'Iraq'                                 = 'IQ'
    'Korea, North'                         = 'KP'
    'Kosovo'                               = 'XK'
    'Lebanon'                              = 'LB'
    'Libya'                                = 'LY'
    'Mali'                                 = 'ML'
    'Moldova'                              = 'MD'
    'Montenegro'                           = 'ME'
    'Myanmar'                              = 'MM'
    'Nicaragua'                            = 'NI'
    'Pakistan'                             = 'PK'
    'Russia'                               = 'RU'
    'Serbia'                               = 'RS'
    'Somalia'                              = 'SO'
    'South Sudan'                          = 'SS'
    'Sudan'                                = 'SD'
    'Syria'                                = 'SY'
    'Ukraine'                              = 'UA'
    'Venezuela'                            = 'VE'
    'Yemen'                                = 'YE'
    'Zimbabwe'                             = 'ZW'
}

#==============================================================================================
# Functions
#==============================================================================================

function Write-CMTraceLog {
    <#
    .SYNOPSIS
        Writes a CMTrace-compatible log entry.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter()]
        [ValidateSet('Info', 'Warning', 'Error')]
        [string]$Type = 'Info'
    )

    $TypeMap  = @{ Info = 1; Warning = 2; Error = 3 }
    $DateTime = Get-Date
    $Date     = $DateTime.ToString('MM-dd-yyyy')
    $Time     = $DateTime.ToString('HH:mm:ss.fff') + '+000'

    $LogEntry = "<![LOG[$Message]LOG]!><time=""$Time"" date=""$Date"" component=""Get-OFACCountryChanges"" context="""" type=""$($TypeMap[$Type])"" thread=""$PID"" file="""">"

    Add-Content -Path $LogFile -Value $LogEntry -Encoding UTF8
    Write-Verbose $Message
}

function Get-OFACData {
    <#
    .SYNOPSIS
        Downloads the OFAC SDN address list (add.csv) and returns objects with a Country property.
        Retries up to 3 times with exponential backoff on network failure.

    .NOTES
        Treasury redirected the old consolidated.csv to sanctionslistservice.ofac.treas.gov,
        which requires a browser User-Agent. add.csv redirects cleanly and contains a country
        column (field 5) with the registrant country for each SDN address entry.

        Format: ent_num,addr_num,address,"city_state_zip","Country",-0-
    #>
    [CmdletBinding()]
    param ()

    $MaxRetries = 3
    $RetryDelay = 5
    $RawCsv     = $null
    $UserAgent  = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'

    for ($Attempt = 1; $Attempt -le $MaxRetries; $Attempt++) {
        try {
            Write-CMTraceLog -Message "Downloading OFAC SDN address list (attempt $Attempt of $MaxRetries)."
            $Response = Invoke-WebRequest -Uri $OFACUrl -UseBasicParsing -TimeoutSec 60 `
                        -UserAgent $UserAgent -MaximumRedirection 5
            $RawCsv   = $Response.Content
            break
        }
        catch {
            if ($Attempt -eq $MaxRetries) {
                Write-CMTraceLog -Message "Download failed after $MaxRetries attempts: $_" -Type Error
                throw
            }
            Write-CMTraceLog -Message "Download attempt $Attempt failed. Retrying in ${RetryDelay}s. Error: $_" -Type Warning
            Start-Sleep -Seconds $RetryDelay
            $RetryDelay *= 2
        }
    }

    try {
        # add.csv has no header row. Format per line:
        #   ent_num,addr_num,address,"city_state_zip","Country",-0-
        # Extract the last quoted field before the trailing -0-
        $Lines   = $RawCsv -split "`n"
        $Entries = foreach ($Line in $Lines) {
            if ($Line -match '^\d+,\d+,.*,"([^"]+)",-0-') {
                [PSCustomObject]@{ Country = $Matches[1] }
            }
        }

        if (-not $Entries) {
            throw 'No address entries parsed from OFAC data. Format may have changed.'
        }

        Write-CMTraceLog -Message "Parsed $(@($Entries).Count) OFAC address entries."
        return $Entries
    }
    catch {
        Write-CMTraceLog -Message "Failed to parse OFAC CSV: $_" -Type Error
        throw
    }
}

function Get-SanctionedCountries {
    <#
    .SYNOPSIS
        Extracts unique, non-empty country names from OFAC data rows.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object[]]$OFACData
    )

    $Countries = $OFACData |
        Where-Object { $_.Country -and $_.Country.Trim() -ne '' } |
        Select-Object -ExpandProperty Country |
        ForEach-Object { $_.Trim() } |
        Sort-Object -Unique

    Write-CMTraceLog -Message "Found $($Countries.Count) unique country entries in OFAC data."
    return $Countries
}

function Get-IsoCodes {
    <#
    .SYNOPSIS
        Maps OFAC country name strings to ISO 3166-1 alpha-2 codes.
        Unmapped entries are flagged for manual review.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string[]]$Countries
    )

    $Mapped   = [System.Collections.Generic.List[PSCustomObject]]::new()
    $Unmapped = [System.Collections.Generic.List[string]]::new()

    # Normalize OFAC inverted names ("Congo, Republic of the" -> "Republic of the Congo")
    $Normalize = { param($n) if ($n -match '^([^,]+), (.+)$') { "$($Matches[2]) $($Matches[1])" } else { $n } }

    # Pass 1: exact matches — these always win
    foreach ($Country in $Countries) {
        $Code = $IsoMap[$Country]
        if ($Code -and -not ($Mapped | Where-Object { $_.Code -eq $Code })) {
            [void]$Mapped.Add([PSCustomObject]@{ Code = $Code; Country = (& $Normalize $Country) })
        }
    }

    # Pass 2: partial matches — only for codes not already claimed by an exact match
    foreach ($Country in $Countries) {
        if ($IsoMap[$Country]) { continue }  # exact match already handled above

        $PartialKey = $IsoMap.Keys | Where-Object { $Country -like "*$_*" -or $_ -like "*$Country*" } | Select-Object -First 1
        $Code = if ($PartialKey) { $IsoMap[$PartialKey] } else { $null }

        if ($Code) {
            if (-not ($Mapped | Where-Object { $_.Code -eq $Code })) {
                [void]$Mapped.Add([PSCustomObject]@{ Code = $Code; Country = (& $Normalize $Country) })
            }
        }
        else {
            if ($Unmapped -notcontains $Country) {
                [void]$Unmapped.Add($Country)
            }
        }
    }

    if ($Unmapped.Count -gt 0) {
        Write-CMTraceLog -Message "Unmapped countries (add to IsoMap if needed): $($Unmapped -join ', ')" -Type Warning
    }

    $Sorted = $Mapped | Sort-Object -Property Code
    return [PSCustomObject]@{
        IsoEntries = $Sorted
        IsoCodes   = ($Sorted | Select-Object -ExpandProperty Code)
        Unmapped   = $Unmapped
    }
}

function Get-Baseline {
    <#
    .SYNOPSIS
        Loads the stored country baseline from disk, or returns empty if none exists.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (Test-Path $Path) {
        Write-CMTraceLog -Message "Loading baseline from $Path"
        try {
            $Data = Get-Content $Path -Raw | ConvertFrom-Json

            if ($null -eq $Data) {
                Write-CMTraceLog -Message "Baseline file parsed as null. Treating as empty." -Type Warning
                return [string[]]@()
            }

            if ($null -eq $Data.PSObject.Properties['Countries']) {
                Write-CMTraceLog -Message "Baseline file is missing the 'Countries' property. Treating as empty." -Type Warning
                return [string[]]@()
            }

            if ($Data.Countries -isnot [System.Array] -and $Data.Countries -isnot [string]) {
                Write-CMTraceLog -Message "Baseline 'Countries' property has unexpected type ($($Data.Countries.GetType().Name)). Treating as empty." -Type Warning
                return [string[]]@()
            }

            return [string[]]$Data.Countries
        }
        catch {
            Write-CMTraceLog -Message "Baseline file is corrupt or unreadable. Treating as empty. Error: $_" -Type Warning
            return [string[]]@()
        }
    }
    else {
        Write-CMTraceLog -Message "No baseline found at $Path. First run — saving current state as baseline." -Type Warning
        return [string[]]@()
    }
}

function Save-Baseline {
    <#
    .SYNOPSIS
        Persists the current country list to disk as the new baseline.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string[]]$Countries
    )

    $Payload = [PSCustomObject]@{
        GeneratedAt = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        Source      = $OFACUrl
        Countries   = $Countries
    }

    $Payload | ConvertTo-Json -Depth 5 | Set-Content -Path $Path -Encoding UTF8
    Write-CMTraceLog -Message "Baseline saved to $Path ($($Countries.Count) countries)."
}

function Show-ChangeReport {
    <#
    .SYNOPSIS
        Writes a formatted change report to the console and log.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$Added,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$Removed,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$Current,

        [Parameter()]
        [AllowEmptyCollection()]
        [string[]]$Unmapped = @()
    )

    $Separator = '=' * 70

    Write-Host ''
    Write-Host $Separator -ForegroundColor Cyan
    Write-Host '  OFAC Country Change Report' -ForegroundColor Cyan
    Write-Host "  Generated : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan
    Write-Host "  Total     : $($Current.Count) sanctioned countries currently" -ForegroundColor Cyan
    Write-Host $Separator -ForegroundColor Cyan

    if ($Added.Count -gt 0) {
        Write-Host ''
        Write-Host "  ADDED ($($Added.Count)) - Review for geofencing addition:" -ForegroundColor Red
        $Added | ForEach-Object { Write-Host "    [+] $_" -ForegroundColor Red }
        Write-CMTraceLog -Message "ADDED countries: $($Added -join ', ')" -Type Warning
    }
    else {
        Write-Host ''
        Write-Host '  ADDED    : None' -ForegroundColor Green
        Write-CMTraceLog -Message 'No countries added since last baseline.'
    }

    if ($Removed.Count -gt 0) {
        Write-Host ''
        Write-Host "  REMOVED ($($Removed.Count)) - Review for geofencing removal:" -ForegroundColor Yellow
        $Removed | ForEach-Object { Write-Host "    [-] $_" -ForegroundColor Yellow }
        Write-CMTraceLog -Message "REMOVED countries: $($Removed -join ', ')" -Type Warning
    }
    else {
        Write-Host ''
        Write-Host '  REMOVED  : None' -ForegroundColor Green
        Write-CMTraceLog -Message 'No countries removed since last baseline.'
    }

    if ($Unmapped.Count -gt 0) {
        Write-Host ''
        Write-Host "  UNMAPPED ($($Unmapped.Count)) - Add to `$IsoMap in the script:" -ForegroundColor Yellow
        $Unmapped | ForEach-Object { Write-Host "    [?] $_" -ForegroundColor Yellow }
    }

    Write-Host ''
    Write-Host $Separator -ForegroundColor Cyan
    Write-Host ''
}

function Send-ChangeNotification {
    <#
    .SYNOPSIS
        POSTs a JSON change summary to a webhook URL.
        Logs a warning on failure but does not abort the run.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Url,

        [Parameter(Mandatory)]
        [string[]]$Added,

        [Parameter(Mandatory)]
        [string[]]$Removed
    )

    $Summary = "$($Added.Count) country/countries added, $($Removed.Count) removed."

    # Generic JSON payload — works with Slack, custom endpoints, and most webhook receivers.
    # For Microsoft Teams, wrap this in an Adaptive Card or MessageCard format.
    $Body = [PSCustomObject]@{
        text      = "OFAC Sanctions List Change Detected: $Summary"
        added     = $Added
        removed   = $Removed
        timestamp = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        source    = $OFACUrl
    } | ConvertTo-Json -Compress

    try {
        Invoke-RestMethod -Uri $Url -Method Post -Body $Body -ContentType 'application/json' | Out-Null
        Write-CMTraceLog -Message "Webhook notification sent to $Url."
    }
    catch {
        Write-CMTraceLog -Message "Webhook notification failed (non-fatal): $_" -Type Warning
        Write-Warning "Webhook notification failed: $_"
    }
}

#==============================================================================================
# Main
#==============================================================================================

try {
    Write-CMTraceLog -Message '=== Get-OFACCountryChanges started ==='

    # Ensure output directory exists
    if (-not (Test-Path $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
        Write-CMTraceLog -Message "Created output directory: $OutputPath"
    }

    # Download and parse OFAC data
    $OFACData  = Get-OFACData
    $Countries = Get-SanctionedCountries -OFACData $OFACData

    # Map to ISO codes
    $IsoResult = Get-IsoCodes -Countries $Countries

    # Load baseline
    $Baseline = Get-Baseline -Path $BaselinePath

    # Diff
    $Added   = [string[]]@($Countries | Where-Object { $_ -notin $Baseline })
    $Removed = [string[]]@($Baseline  | Where-Object { $_ -notin $Countries })

    # Exit early if no changes and caller requested silent operation
    if ($SkipIfNoChanges -and $Added.Count -eq 0 -and $Removed.Count -eq 0) {
        Write-CMTraceLog -Message "No changes detected. Exiting without report (-SkipIfNoChanges)."
        Write-CMTraceLog -Message '=== Get-OFACCountryChanges completed ==='
        return
    }

    # Report
    Show-ChangeReport -Added $Added -Removed $Removed -Current $Countries -Unmapped $IsoResult.Unmapped

    # Notify webhook if changes detected
    if ($WebhookUrl -and ($Added.Count -gt 0 -or $Removed.Count -gt 0)) {
        Send-ChangeNotification -Url $WebhookUrl -Added $Added -Removed $Removed
    }

    # Save updated baseline
    if ($PSCmdlet.ShouldProcess($BaselinePath, 'Save updated baseline')) {
        Save-Baseline -Path $BaselinePath -Countries $Countries
    }

    # Export ISO code CSV (country_code,country_name)
    if ($ExportIsoCodes) {
        if ($PSCmdlet.ShouldProcess($IsoCodeFile, 'Export ISO code CSV')) {
            'country_code,country_name' | Set-Content -Path $IsoCodeFile -Encoding UTF8
            $IsoResult.IsoEntries | ForEach-Object {
                "$($_.Code),$($_.Country)"
            } | Add-Content -Path $IsoCodeFile -Encoding UTF8
            Write-Host "  ISO code CSV written to: $IsoCodeFile" -ForegroundColor Cyan
            Write-CMTraceLog -Message "ISO code CSV exported to $IsoCodeFile ($($IsoResult.IsoEntries.Count) entries)."
        }
    }

    # Export plain-text ISO code list (one code per line)
    if ($ExportIsoCodeList) {
        if ($PSCmdlet.ShouldProcess($IsoCodeListFile, 'Export ISO code list')) {
            $IsoResult.IsoCodes | Set-Content -Path $IsoCodeListFile -Encoding UTF8
            Write-Host "  ISO code list written to: $IsoCodeListFile" -ForegroundColor Cyan
            Write-CMTraceLog -Message "ISO code list exported to $IsoCodeListFile ($($IsoResult.IsoCodes.Count) codes)."
        }
    }

    # Write unmapped countries file — present when action needed, absent when clean
    if ($PSCmdlet.ShouldProcess($UnmappedFile, 'Write unmapped countries file')) {
        if ($IsoResult.Unmapped.Count -gt 0) {
            $IsoResult.Unmapped | Sort-Object | Set-Content -Path $UnmappedFile -Encoding UTF8
            Write-Host "  Unmapped countries written to: $UnmappedFile" -ForegroundColor Yellow
            Write-CMTraceLog -Message "Unmapped countries file written to $UnmappedFile ($($IsoResult.Unmapped.Count) entries)." -Type Warning
        }
        elseif (Test-Path $UnmappedFile) {
            Remove-Item -Path $UnmappedFile -Force
            Write-CMTraceLog -Message "No unmapped countries. Removed stale $UnmappedFile."
        }
    }

    Write-CMTraceLog -Message '=== Get-OFACCountryChanges completed ==='
}
catch {
    Write-CMTraceLog -Message "Unhandled error: $_" -Type Error
    Write-Error $_
}
