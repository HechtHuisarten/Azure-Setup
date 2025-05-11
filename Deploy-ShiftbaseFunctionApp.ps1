# --- Setup Azure Resource Naming Variables ---
$RandomInt = Get-Random -Minimum 1000 -Maximum 9999
$ProjectPrefix = "shiftbase-sync" # A prefix for your project resources
$ResourceGroupName = "$($ProjectPrefix)-rg-ps"
$StorageAccountName = "$($ProjectPrefix)storps$RandomInt" # Needs to be globally unique
$FunctionAppName = "$($ProjectPrefix)-func-app-ps-$RandomInt" # Needs to be globally unique
$AppInsightsName = "appi-ps-$FunctionAppName" # Application Insights name
$Location = "northeurope"
$PlanName = "$($FunctionAppName)-consumptionplan" # Name for the consumption plan

# --- Application Configuration Variables (to be set as App Settings) ---
# CRITICAL: Replace placeholder values with your actual data or use a secure method to inject them.
# For an internship, you might hardcode them for your local script copy,
# but NEVER commit actual secrets to a shared repository.
$ShiftbaseURL = "https://api.shiftbase.com/api/reports/schedule_detail"
$ShiftbaseAPIKey = "YOUR_SHIFTBASE_API_KEY_HERE" # <<< !!! REPLACE WITH YOUR ACTUAL API KEY !!!
$DBConnectionString = "YOUR_DB_CONNECTION_STRING_HERE" # <<< !!! REPLACE WITH YOUR ACTUAL CONNECTION STRING !!!
$DBTargetTable = "ShiftbaseScheduleDetailedReport"

# --- Create a Resource Group ---
Write-Host "Creating resource group: $ResourceGroupName in $Location..."
New-AzResourceGroup -Name $ResourceGroupName -Location $Location -ErrorAction Stop | Out-Null

# --- Create an Azure Storage Account for the Function App ---
Write-Host "Creating storage account: $StorageAccountName..."
New-AzStorageAccount -ResourceGroupName $ResourceGroupName `
    -Name $StorageAccountName `
    -Location $Location `
    -SkuName Standard_LRS `
    -Kind StorageV2 `
    -HttpsOnly $true `
    -MinimumTlsVersion TLS1_2 `
    -ErrorAction Stop | Out-Null

# --- Create Application Insights instance ---
Write-Host "Creating Application Insights: $AppInsightsName..."
$appInsights = New-AzApplicationInsights -Name $AppInsightsName `
    -ResourceGroupName $ResourceGroupName `
    -Location $Location `
    -Kind web `
    -ApplicationType web `
    -ErrorAction Stop

$AppInsightsInstrumentationKey = $appInsights.InstrumentationKey
If (-not $AppInsightsInstrumentationKey) {
    Write-Warning "Failed to retrieve Application Insights Instrumentation Key. Monitoring might be affected."
    # Consider stopping the script if App Insights is absolutely critical: # exit 1
} Else {
    Write-Host "Successfully retrieved Instrumentation Key for $AppInsightsName."
}

# --- Define Application Settings for the Function App ---
# These will be available as environment variables to your function code.
$appSettings = @{
    "FUNCTIONS_WORKER_RUNTIME"          = "python" # Assuming Python based on your previous context
    "FUNCTIONS_EXTENSION_VERSION"       = "~4"
    "WEBSITE_RUN_FROM_PACKAGE"          = "1"      # Recommended for deployment
    "APPLICATIONINSIGHTS_CONNECTION_STRING" = "InstrumentationKey=$AppInsightsInstrumentationKey" # Modern way to connect App Insights

    # Your custom application settings
    "SHIFTBASE_API_URL"                 = $ShiftbaseURL
    "SHIFTBASE_API_KEY"                 = $ShiftbaseAPIKey
    "DB_CONNECTION_STRING"              = $DBConnectionString
    "DB_TARGET_TABLE"                   = $DBTargetTable
}

# --- Create a Function App ---
Write-Host "Creating Function App: $FunctionAppName for Python on Linux in $Location..."
New-AzFunctionApp -Name $FunctionAppName `
    -ResourceGroupName $ResourceGroupName `
    -Location $Location `
    -StorageAccountName $StorageAccountName `
    -Runtime Python ` # Ensure this matches your function's language
    -RuntimeVersion "3.11" ` # Specify your Python version
    -FunctionsVersion "4" `
    -PlanName $PlanName ` # This will create a new consumption plan with this name
    -Sku "Y1" ` # Y1 is the SKU for the Dynamic Consumption plan
    -OSType Linux `
    -EnableSystemAssignedIdentity $true ` # Good for Azure Key Vault integration & other Azure resource auth
    -AppSettings $appSettings `
    -InstrumentationKey $AppInsightsInstrumentationKey ` # Direct linking for some portal views/older compatibility
    -ErrorAction Stop | Out-Null

Write-Host "--------------------------------------------------------------------"
Write-Host "Script completed at $(Get-Date)."
Write-Host "Resource Group:         $ResourceGroupName"
Write-Host "Storage Account:        $StorageAccountName"
Write-Host "Application Insights:   $AppInsightsName"
Write-Host "Function App Name:      $FunctionAppName"
Write-Host "Function App Plan Name: $PlanName (Consumption Plan)"
Write-Host "Function App Location:  $Location"
Write-Host "Function App Runtime:   Python 3.11 (Linux)" # Verify this matches your needs
Write-Host ""
Write-Host "The following Application Settings have been configured for '$FunctionAppName':"
$appSettings.GetEnumerator() | ForEach-Object { 
    If ($_.Name -in @("SHIFTBASE_API_KEY", "DB_CONNECTION_STRING")) {
        Write-Host "  $($_.Name) = [Value Set - Hidden for Security]" 
    } Else {
        Write-Host "  $($_.Name) = $($_.Value)" 
    }
}
Write-Host ""
Write-Host "Access your Function App in the Azure portal or at: https://$FunctionAppName.azurewebsites.net"
Write-Host "IMPORTANT: If you used placeholder values for SHIFTBASE_API_KEY or DB_CONNECTION_STRING,"
Write-Host "           you MUST update them in the Azure portal (Function App -> Configuration) for the function to work correctly."
Write-Host "--------------------------------------------------------------------"
