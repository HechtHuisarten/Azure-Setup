# --- Setup Azure Resource Naming Variables ---
$RandomInt = Get-Random -Minimum 1000 -Maximum 9999
$ProjectPrefix = "shiftbase-sync"

# Adjusted Storage Account Name generation to meet Azure requirements (3-24 chars, lowercase, no hyphens)
$StorageAccountProjectPrefix = ($ProjectPrefix -replace "-", "") # Removes hyphen -> "shiftbasesync" (13 chars)
$StorageAccountUniqueSuffix = "stor" # Shortened suffix (4 chars)
# Total potential length: 13 (prefix) + 4 (suffix) + 4 (RandomInt) = 21 chars. This is within 3-24 char limit.
$StorageAccountName = "$($StorageAccountProjectPrefix)$($StorageAccountUniqueSuffix)$($RandomInt)".ToLower() # Ensure lowercase

$ResourceGroupName = "$($ProjectPrefix)-rg-cli-ps" # Resource group names can have hyphens
$FunctionAppName = "$($ProjectPrefix)-func-app-cli-ps-$($RandomInt)" # Function app names can have hyphens
$AppInsightsName = "appi-cli-ps-$($FunctionAppName)" # App Insights names can have hyphens
$Location = "northeurope"

# --- Application Configuration Variables ---
# CRITICAL: Replace placeholder values with your actual data.
$ShiftbaseURL = "https://api.shiftbase.com/api/reports/schedule_detail"
$ShiftbaseAPIKey = "YOUR_SHIFTBASE_API_KEY_HERE" # <<< !!! REPLACE WITH YOUR ACTUAL API KEY !!!
$DBConnectionString = "YOUR_DB_CONNECTION_STRING_HERE" # <<< !!! REPLACE WITH YOUR ACTUAL CONNECTION STRING !!!
$DBTargetTable = "ShiftbaseScheduleDetailedReport"

Write-Host "Starting Azure resource deployment using Azure CLI via PowerShell..."
Write-Host "Current Date: $(Get-Date)"
Write-Host "Generated Storage Account Name: $StorageAccountName" # Added for debugging
Write-Host ""

# --- Log into Azure ---
Write-Host "Attempting to log into Azure. You might be prompted."
az login
if ($LASTEXITCODE -ne 0) {
    Write-Error "Azure CLI login failed. Please ensure Azure CLI is installed and you can log in manually. Script aborted."
    exit 1
}
Write-Host "Azure CLI login successful or already logged in."
Write-Host ""

# --- Check current Azure CLI account ---
Write-Host "Checking current Azure CLI account..."
az account show
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to verify Azure CLI account. Script aborted."
    exit 1
}
Write-Host "Azure CLI account verified."
Write-Host ""

# --- Create a Resource Group ---
Write-Host "Creating resource group: $ResourceGroupName in $Location..."
az group create --name $ResourceGroupName --location $Location --output none
if ($LASTEXITCODE -ne 0) { Write-Error "Failed to create resource group. Script aborted."; exit 1 }
Write-Host "Resource group '$ResourceGroupName' created successfully."
Write-Host ""

# --- Create an Azure Storage Account for the Function App ---
Write-Host "Creating storage account: $StorageAccountName..."
az storage account create --name $StorageAccountName --resource-group $ResourceGroupName --location $Location --sku "Standard_LRS" --kind "StorageV2" --https-only true --min-tls-version "TLS1_2" --output none
if ($LASTEXITCODE -ne 0) { Write-Error "Failed to create storage account. Script aborted."; exit 1 }
Write-Host "Storage account '$StorageAccountName' created successfully."
Write-Host ""

# --- Create Application Insights instance ---
Write-Host "Creating Application Insights: $AppInsightsName..."
az monitor app-insights component create --app $AppInsightsName --location $Location --resource-group $ResourceGroupName --kind "web" --application-type "web" --output none
if ($LASTEXITCODE -ne 0) { Write-Error "Failed to create Application Insights. Script aborted."; exit 1 }
Write-Host "Application Insights '$AppInsightsName' created successfully."
Write-Host ""

# Get Application Insights Instrumentation Key
Write-Host "Fetching Instrumentation Key for $AppInsightsName..."
$AppInsightsInstrumentationKey = (az monitor app-insights component show --app $AppInsightsName --resource-group $ResourceGroupName --query "instrumentationKey" --output tsv)
# Remove potential newline/carriage return from tsv output
$AppInsightsInstrumentationKey = $AppInsightsInstrumentationKey -replace "`r","" -replace "`n",""

if (-not $AppInsightsInstrumentationKey) {
    Write-Warning "Failed to retrieve Application Insights Instrumentation Key. Monitoring might be affected. Continuing..."
} Else {
    Write-Host "Successfully retrieved Instrumentation Key for $AppInsightsName."
}
Write-Host ""

# --- Create a Function App ---
Write-Host "Creating Function App: $FunctionAppName for Python on Linux in $Location..."
az functionapp create --name $FunctionAppName --resource-group $ResourceGroupName --storage-account $StorageAccountName --consumption-plan-location $Location --os-type "Linux" --runtime "python" --runtime-version "3.11" --functions-version "4" --assign-identity "[system]" --app-insights $AppInsightsName --output none
if ($LASTEXITCODE -ne 0) { Write-Error "Failed to create Function App. Script aborted."; exit 1 }
Write-Host "Function App '$FunctionAppName' created successfully."
Write-Host ""

# --- Configure Application Settings for the Function App ---
Write-Host "Configuring Application Settings for $FunctionAppName..."
$appSettings = @(
    "FUNCTIONS_WORKER_RUNTIME=python",
    "FUNCTIONS_EXTENSION_VERSION=~4",
    "WEBSITE_RUN_FROM_PACKAGE=1",
    "SHIFTBASE_API_URL=$($ShiftbaseURL)",
    "SHIFTBASE_API_KEY=$($ShiftbaseAPIKey)",
    "DB_CONNECTION_STRING=$($DBConnectionString)",
    "DB_TARGET_TABLE=$($DBTargetTable)"
)

if ($AppInsightsInstrumentationKey) {
    $appSettings += "APPLICATIONINSIGHTS_CONNECTION_STRING=InstrumentationKey=$($AppInsightsInstrumentationKey)"
}

az functionapp config appsettings set --name $FunctionAppName --resource-group $ResourceGroupName --settings $appSettings --output none
if ($LASTEXITCODE -ne 0) { Write-Warning "Failed to set some application settings. Please verify in Azure Portal." }
else { Write-Host "Application settings configured for $FunctionAppName."}
Write-Host ""

Write-Host "--------------------------------------------------------------------"
Write-Host "Script completed at $(Get-Date)."
Write-Host "Resource Group:         $ResourceGroupName"
Write-Host "Storage Account:        $StorageAccountName"
Write-Host "Application Insights:   $AppInsightsName"
Write-Host "Function App Name:      $FunctionAppName"
Write-Host "Function App Location:  $Location"
Write-Host "Function App Runtime:   Python 3.11 (Linux, Consumption Plan)"
Write-Host ""
Write-Host "The following Application Settings have been configured (values for secrets are not displayed here for security):"
Write-Host "  FUNCTIONS_WORKER_RUNTIME=python"
Write-Host "  FUNCTIONS_EXTENSION_VERSION=~4"
Write-Host "  WEBSITE_RUN_FROM_PACKAGE=1"
if ($AppInsightsInstrumentationKey) {
    Write-Host "  APPLICATIONINSIGHTS_CONNECTION_STRING=InstrumentationKey=**********"
} else {
    Write-Host "  APPLICATIONINSIGHTS_CONNECTION_STRING was not explicitly set by this script (key not found or relying on auto-config by --app-insights flag)."
}
Write-Host "  SHIFTBASE_API_URL=$($ShiftbaseURL)"
Write-Host "  SHIFTBASE_API_KEY=**********" 
Write-Host "  DB_CONNECTION_STRING=**********"
Write-Host "  DB_TARGET_TABLE=$($DBTargetTable)"
Write-Host ""
Write-Host "Access your Function App in the Azure portal or at: https://$($FunctionAppName).azurewebsites.net"
Write-Host "IMPORTANT: Ensure you have replaced placeholder values for SHIFTBASE_API_KEY and DB_CONNECTION_STRING in the script."
Write-Host "--------------------------------------------------------------------"
