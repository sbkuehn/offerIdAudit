<#
.SYNOPSIS
Inventory Azure subscriptions and attempt to retrieve legacy OfferId using public APIs.

.DESCRIPTION
Enumerates all subscriptions visible to the current identity via Get-AzSubscription.
For each subscription, attempts to retrieve OfferId via:
  1) Microsoft.Billing (billingSubscriptions) using raw ARM REST
  2) Microsoft.Consumption (usageDetails) using raw ARM REST

Outputs a single row per subscription:
  SubscriptionName, SubscriptionId, OfferId, OfferSource

.NOTES
- OfferId is not exposed for every subscription through public APIs.
- The Consumption fallback relies on recent usage records (default 90 day lookback).

.AUTHOR
Shannon Eldridge-Kuehn
January 2026
#>

[CmdletBinding()]
param(
  [int]$LookbackDays = 90,
  [string]$BillingApiVersion = '2024-04-01',
  [string]$ConsumptionApiVersion = '2019-11-01'
)

$ErrorActionPreference = 'Stop'

# Sign in if needed
try {
  if (-not (Get-AzContext)) {
    Connect-AzAccount | Out-Null
  }
} catch {
  Connect-AzAccount | Out-Null
}

$arm = 'https://management.azure.com'
$token = (Get-AzAccessToken -ResourceUrl $arm).Token
$headers = @{ Authorization = "Bearer $token"; 'Content-Type' = 'application/json' }

function Invoke-ArmGet {
  param([Parameter(Mandatory)][string]$Uri)
  Invoke-RestMethod -Method GET -Uri $Uri -Headers $headers
}

function Get-FirstConsumptionOfferId {
  param([Parameter(Mandatory)][string]$SubscriptionId)

  $end = (Get-Date).ToString('yyyy-MM-dd')
  $start = (Get-Date).AddDays(-1 * [Math]::Abs($LookbackDays)).ToString('yyyy-MM-dd')

  # Build a filter the service commonly accepts
  $filterRaw = "properties/usageStart ge '$start' and properties/usageEnd le '$end'"
  $filter = [System.Web.HttpUtility]::UrlEncode($filterRaw)

  # $top=1 keeps it fast
  $uri = "$arm/subscriptions/$SubscriptionId/providers/Microsoft.Consumption/usageDetails?api-version=$ConsumptionApiVersion&`$filter=$filter&`$top=1"

  try {
    $resp = Invoke-ArmGet -Uri $uri
    if ($resp.value -and $resp.value.Count -gt 0) {
      $p = $resp.value[0].properties
      if ($p.offerId) { return $p.offerId }
      if ($p.OfferId) { return $p.OfferId }
    }
  } catch {
    return $null
  }

  return $null
}

$results = foreach ($sub in Get-AzSubscription) {

  $offerId = $null
  $source = 'NotExposedByPublicAPI'

  # 1) Microsoft.Billing
  try {
    $billingUri = "$arm/providers/Microsoft.Billing/billingSubscriptions/$($sub.Id)?api-version=$BillingApiVersion"
    $billing = Invoke-ArmGet -Uri $billingUri
    if ($billing.properties -and $billing.properties.offerId) {
      $offerId = $billing.properties.offerId
      $source = 'Microsoft.Billing'
    }
  } catch {
    # Expected for many subscription types
  }

  # 2) Microsoft.Consumption fallback
  if (-not $offerId) {
    $offerId = Get-FirstConsumptionOfferId -SubscriptionId $sub.Id
    if ($offerId) {
      $source = 'Microsoft.Consumption'
    }
  }

  [pscustomobject]@{
    SubscriptionName = $sub.Name
    SubscriptionId   = $sub.Id
    OfferId          = $offerId
    OfferSource      = $source
  }
}

$results | Sort-Object OfferSource, SubscriptionName
