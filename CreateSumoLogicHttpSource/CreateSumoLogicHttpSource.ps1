Trace-VstsEnteringInvocation $MyInvocation
Import-Module -Name $PSScriptRoot\ps_modules\VstsTaskSdk\VstsTaskSdk.psm1

# Get inputs.
$SumoLogicAccessKeyId = Get-VstsInput -Name SumoLogicAccessKeyId -Require
$SumoLogicAccessKey = Get-VstsInput -Name SumoLogicAccessKey -Require
$SumoLogicEndpoint = Get-VstsInput -Name SumoLogicEndpoint -Require
$SumoLogicCollectorName = Get-VstsInput -Name SumoLogicCollectorName -Require
$SumoLogicSourceName = Get-VstsInput -Name SumoLogicSourceName -Require
$SumoLogicSourceDescription = Get-VstsInput -Name SumoLogicSourceDescription
$SumoLogicSourceCategory = Get-VstsInput -Name SumoLogicSourceCategory -Require
$SumoLogicEndpointVariableName = Get-VstsInput -Name SumoLogicEndpointVariableName

Write-Output "AccessKeyId: $SumoLogicAccessKeyId"
Write-Output "AccessKey: $($SumoLogicAccessKey.Substring(0,8))"
Write-Output "APIEndpoint: $SumoLogicEndpoint"
Write-Output "CollectorName: $SumoLogicCollectorName"
Write-Output "SourceName: $SumoLogicSourceName"
Write-Output "SourceDescription: $SumoLogicSourceDescription"
Write-Output "SourceCategory: $SumoLogicSourceCategory"
Write-Output "SumoLogicEndpointVariableName: $SumoLogicEndpointVariableName"

function New-SumoLogicHttpSource {
    param (
        [Parameter(Mandatory=$true)][hashtable]$AuthHeader,
        [Parameter(Mandatory=$true)][string]$ApiEndpoint,
        [Parameter(Mandatory=$true)][int]$CollectorId,
        [Parameter(Mandatory=$true)][string]$SourceName,
        [Parameter(Mandatory=$false)][string]$SourceDescription,
        [Parameter(Mandatory=$false)][string]$SourceCategory,
        [Parameter(Mandatory=$false)][boolean]$SourceAutomaticDateParsing = $true,
        [Parameter(Mandatory=$false)][boolean]$SourceMultilineProcessingEnable,
        [Parameter(Mandatory=$false)][boolean]$SourceUseAutolineMatching = $true,
        [Parameter(Mandatory=$false)][boolean]$SourceForceTimeZone = $false,
        [Parameter(Mandatory=$false)][boolean]$SourceMessagePerRequest = $true,
        [Parameter(Mandatory=$false)][string]$SourceManualPrefixRegexp,
        [Parameter(Mandatory=$false)][string[]]$SourceFilters,
        [Parameter(Mandatory=$false)][hashtable[]]$SourceDefaultDateFormats,
        [Parameter(Mandatory=$false)][string]$SourceEncoding
    )

    $SourceData = @{
        sourceType = "HTTP"
        name = $SourceName
        messagePerRequest = $SourceMessagePerRequest
        multilineProcessingEnable = if ($SourceMessagePerRequest) { $false } else { $SourceMultilineProcessingEnable }
        useAutolineMatching = if ($SourceMessagePerRequest) { $false } else { $SourceUseAutolineMatching }
        forceTimeZone = $SourceForceTimeZone
        automaticDateParsing = $SourceAutomaticDateParsing
    }

    if($SourceDescription)        { $SourceData.Add('description', $SourceDescription) }
    if($SourceCategory)           { $SourceData.Add('category', $SourceCategory) }
    if($SourceHostName)           { $SourceData.Add('hostName', $SourceHostName) }
    if($SourceTimeZone)           { $SourceData.Add('timeZone', $SourceTimeZone) }
    if($SourceFilters)            { $SourceData.Add('filters', $SourceFilters) }
    if($SourceDefaultDateFormats) { $SourceData.Add('defaultDateFormats', $SourceDefaultDateFormats) }
    if($SourceManualPrefixRegexp) { $SourceData.Add('sourceManualPrefixRegexp', $SourceManualPrefixRegexp) }


    $RequestData = @{
        source = $SourceData
    }

    Write-Verbose $SourceData

    $NewSource = Invoke-WebRequest -Method Post -Headers $AuthHeader -Uri ($ApiEndpoint+"/collectors/$CollectorId/sources") -Body ($RequestData | ConvertTo-Json) -UseBasicParsing

    return $NewSource.Content | ConvertFrom-Json
}

$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $SumoLogicAccessKeyId,$SumoLogicAccessKey)))
$AuthHeader = @{
    Authorization=("Basic {0}" -f $base64AuthInfo)
    'Content-Type' = 'application/json'
    }

$CollectorReq = Invoke-WebRequest -Method Get -Headers $AuthHeader -Uri ($SumoLogicEndpoint+'/collectors') -UseBasicParsing

$CollectorsCollection = ($CollectorReq.Content | ConvertFrom-Json)

$Collector = $CollectorsCollection.collectors.Where({$_.name.ToLower() -eq $SumoLogicCollectorName.ToLower()})

if(-not $Collector)
{
    Write-Error "Collector doesn't exist! Please create a hosted collector first using the Create Sumo Logic Hosted Collector VSTS task."
}
else
{
    Write-Output "Collector Exists: $SumoLogicCollectorName"
}

if ($Collector)
{
    $SourceReq = Invoke-WebRequest -Method Get -Headers $AuthHeader -Uri ($SumoLogicEndpoint+"/collectors/$($Collector.id)/sources") -UseBasicParsing

    $SourcesCollection = ($SourceReq.Content | ConvertFrom-Json)

    $Source = $SourcesCollection.sources.Where({$_.name.ToLower() -eq $SumoLogicSourceName.ToLower()})

    if(-not $Source)
    {
        Write-Output "Creating HTTP Source: $SumoLogicSourceName"
        $Source = (New-SumoLogicHttpSource `
            -AuthHeader $AuthHeader `
            -ApiEndpoint $SumoLogicEndpoint `
            -CollectorId $Collector.id `
            -SourceName $SumoLogicSourceName `
            -SourceDescription $SumoLogicSourceDescription `
            -SourceCategory $SumoLogicSourceCategory).source
    }
    else
    {
        Write-Output "Source Exists: $SumoLogicSourceName"
    }
}

if ($Source)
{
    Set-TaskVariable $SumoLogicEndpointVariableName $Source.url
}
else
{
    Write-Error "Unable to create or update a Sumo Logic HTTP Source"   
}