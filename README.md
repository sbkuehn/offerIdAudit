# Azure Offer ID Audit (Billing + Consumption)

This repo contains a practical PowerShell script that inventories **all Azure subscriptions you can see** and attempts to retrieve the **legacy Offer ID** (for example `MS-AZR-0003P`) using **public APIs**.

It reflects real Azure commerce behavior:

- **Microsoft.Billing** sometimes exposes `offerId` for certain subscription types.
- **Microsoft.Consumption** sometimes exposes `offerId` on **usage details** records (commonly for legacy MOSP subscriptions and some benefit subscriptions).
- Some subscriptions show an offer in the Azure portal but **do not expose a retrievable OfferId via public APIs**. The script reports these as `NotExposedByPublicAPI`.

## Contents

- `scripts/Get-AzureOfferIdInventory.ps1`  
  Enumerates subscriptions and attempts OfferId retrieval via Billing first, then Consumption usage details.

## Prerequisites

- PowerShell 7+ recommended (Windows, macOS, or Linux)
- Az PowerShell modules:
  - `Az.Accounts`
  - `Az.Resources`
- Permission to enumerate subscriptions (Reader is sufficient)
- Permission to query billing/consumption APIs varies by tenant and subscription

Install modules (PowerShell):

```powershell
Install-Module Az.Accounts, Az.Resources -Scope CurrentUser
```

## How it works

For each subscription returned by `Get-AzSubscription`, the script:

1. Gets an ARM token using `Get-AzAccessToken`
2. Calls **Microsoft.Billing** (best-effort):

   `GET https://management.azure.com/providers/Microsoft.Billing/billingSubscriptions/{subscriptionId}?api-version=2024-04-01`

3. If `offerId` is not returned, it falls back to **Microsoft.Consumption usageDetails** (best-effort):

   `GET https://management.azure.com/subscriptions/{subscriptionId}/providers/Microsoft.Consumption/usageDetails?...`

4. Outputs:

- `SubscriptionName`
- `SubscriptionId`
- `OfferId`
- `OfferSource` (`Microsoft.Billing`, `Microsoft.Consumption`, or `NotExposedByPublicAPI`)

## Run

```powershell
Connect-AzAccount

# From the repo root:
./scripts/Get-AzureOfferIdInventory.ps1
```

### Export to CSV

```powershell
./scripts/Get-AzureOfferIdInventory.ps1 | Export-Csv ./offerid-inventory.csv -NoTypeInformation
```

## Notes and limitations

- The Consumption fallback requires recent usage within the lookback window (default 90 days). If a subscription has no usage, it may not return an OfferId via Consumption.
- Visual Studio / DevTest / entitlement subscriptions may show offer information in the Azure portal but still return `NotExposedByPublicAPI` here. That reflects public API limitations.

## References

- Offer details (legacy offer names and IDs):
  - https://azure.microsoft.com/en-us/support/legal/offer-details
- Microsoft Billing REST API overview:
  - https://learn.microsoft.com/en-us/rest/api/billing/
- Azure Consumption REST API overview:
  - https://learn.microsoft.com/en-us/rest/api/consumption/

## License

MIT. See `LICENSE`.
