function Get-Pax8CurrentSubscription {
    param(
        [Parameter(Mandatory = $false)]
        [string]$TenantFilter,
        [string]$CustomerId,
        [string]$SKU,
        [string]$ProductName
    )

    if ($TenantFilter) {
        $TenantFilter = (Get-Tenants -TenantFilter $TenantFilter).customerId
        $CustomerId = Get-ExtensionMapping -Extension 'Pax8' | Where-Object { $_.RowKey -eq $TenantFilter } | Select-Object -ExpandProperty IntegrationId
    }

    if ([string]::IsNullOrWhiteSpace($CustomerId)) {
        throw 'No Pax8 mapping found'
    }

    Write-Information "Getting Pax8 subscriptions for $CustomerId"
    $Query = @{ companyId = $CustomerId }
    if ($SKU) {
        $Query.productId = $SKU
    }
    $Subscriptions = Get-Pax8PagedData -Path 'subscriptions' -Query $Query
    $ProductLookup = @{}
    $ProductIds = @(
        $Subscriptions | ForEach-Object {
            $_.product.id ?? $_.productId
        } | Where-Object {
            -not [string]::IsNullOrWhiteSpace([string]$_)
        } | Select-Object -Unique
    )
    foreach ($ProductId in $ProductIds) {
        try {
            $Product = Invoke-Pax8Request -Method GET -Path "products/$ProductId"
            $ProductLookup[$ProductId] = $Product.name ?? $Product.displayName
        } catch {
            Write-Information "Could not resolve Pax8 product name for $ProductId. $($_.Exception.Message)"
        }
    }

    $MappedSubscriptions = @($Subscriptions | ForEach-Object {
            $ProductNameValue = $_.product.name ?? $_.productName ?? $_.name
            $ProductId = $_.product.id ?? $_.productId
            if ([string]::IsNullOrWhiteSpace($ProductNameValue) -and -not [string]::IsNullOrWhiteSpace($ProductId) -and $ProductLookup.ContainsKey($ProductId)) {
                $ProductNameValue = $ProductLookup[$ProductId]
            }
            if ([string]::IsNullOrWhiteSpace($ProductNameValue)) {
                $ProductNameValue = $ProductId
            }
            [PSCustomObject]@{
                id                    = $_.id
                subscriptionId        = $_.id
                sku                   = $ProductId
                productId             = $ProductId
                productName           = $ProductNameValue
                name                  = @(@{ value = $ProductNameValue })
                quantity              = $_.quantity
                status                = $_.status
                purchaseDate          = $_.createdDate ?? $_.startDate
                billingCycle          = $_.billingTerm
                billingTerm           = $_.billingTerm
                commitmentTerm        = $_.commitmentTerm ?? @{
                    renewalConfiguration = @{
                        renewalDate = $_.commitmentTermEndDate
                    }
                }
                commitmentTermEndDate = $_.commitmentTermEndDate
                startDate             = $_.startDate
                endDate               = $_.endDate
                TermInfo              = $_.billingTerm
            }
        })

    if ($ProductName) {
        return $MappedSubscriptions | Where-Object { $_.productName -eq $ProductName }
    }
    return $MappedSubscriptions
}
