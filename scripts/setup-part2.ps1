param(
    [Parameter(Mandatory = $true)]
    [string]$Initials,
    
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName
)

$ErrorActionPreference = "Stop"

# Configuration
$initials = $Initials.ToLower()
$acrName = "cragentws${initials}lx01"
$containerEnvName = "ce-agentws-${initials}-lx01"
$containerAppName = "aca-agentws-api-${initials}-lx01"
$imageName = "agentws-api:v1"
$apiDir = Join-Path (Split-Path $PSScriptRoot) "src" "api"

Write-Host "=== Part 2 Setup: Audit API Deployment ===" -ForegroundColor Cyan

# Get resource group location
Write-Host "Fetching resource group location..." -ForegroundColor Yellow
$rg = az group show --name $ResourceGroupName --query "location" -o tsv
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Resource group not found." -ForegroundColor Red
    exit 1
}
Write-Host "Location: $rg" -ForegroundColor Green

# Create Container Registry
Write-Host "`nCreating Container Registry: $acrName..." -ForegroundColor Yellow
az acr create `
    --resource-group $ResourceGroupName `
    --name $acrName `
    --sku Basic `
    --admin-enabled true `
    --location $rg
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Failed to create Container Registry." -ForegroundColor Red
    exit 1
}
Write-Host "Container Registry created." -ForegroundColor Green

# Get ACR login server
$loginServer = az acr show --name $acrName --query "loginServer" -o tsv
Write-Host "Login Server: $loginServer" -ForegroundColor Green

# Build and push image using az acr build
Write-Host "`nBuilding and pushing Docker image..." -ForegroundColor Yellow
az acr build `
    --registry $acrName `
    --image $imageName `
    --file "$apiDir/Dockerfile" `
    $apiDir
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Failed to build and push Docker image." -ForegroundColor Red
    exit 1
}
Write-Host "Image pushed: ${loginServer}/${imageName}" -ForegroundColor Green

# Create Container App Environment
Write-Host "`nCreating Container App Environment: $containerEnvName..." -ForegroundColor Yellow
az containerapp env create `
    --name $containerEnvName `
    --resource-group $ResourceGroupName `
    --location $rg
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Failed to create Container App Environment." -ForegroundColor Red
    exit 1
}
Write-Host "Container App Environment created." -ForegroundColor Green

# Create Container App
Write-Host "`nCreating Container App: $containerAppName..." -ForegroundColor Yellow

# Get ACR admin credentials
$registryUsername = az acr credential show -n $acrName --query "username" -o tsv
$registryPassword = az acr credential show -n $acrName --query "passwords[0].value" -o tsv

az containerapp create `
    --name $containerAppName `
    --resource-group $ResourceGroupName `
    --environment $containerEnvName `
    --image "${loginServer}/${imageName}" `
    --target-port 8000 `
    --ingress external `
    --registry-server $loginServer `
    --registry-username $registryUsername `
    --registry-password $registryPassword `
    --cpu 0.5 `
    --memory 1.0Gi
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Failed to create Container App." -ForegroundColor Red
    exit 1
}
Write-Host "Container App created." -ForegroundColor Green

# Get Container App URL
Write-Host "`nFetching Container App URL..." -ForegroundColor Yellow
Start-Sleep -Seconds 5
$appUrl = az containerapp show -n $containerAppName -g $ResourceGroupName --query "properties.configuration.ingress.fqdn" -o tsv
if ($LASTEXITCODE -eq 0 -and $appUrl) {
    $apiUrl = "https://${appUrl}"
    
    Write-Host "`n=== Deployment Complete ===" -ForegroundColor Green
    Write-Host "`n" 
    Write-Host "════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "AUDIT API URL (copy and paste into MCP configuration):" -ForegroundColor Yellow
    Write-Host "════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""
    Write-Host $apiUrl -ForegroundColor Green -BackgroundColor Black
    Write-Host ""
    Write-Host "════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "`nUse this URL for:" -ForegroundColor Yellow
    Write-Host "  • AUDIT_API_URL environment variable in MCP server" -ForegroundColor White
    Write-Host "  • MCP server configuration in Foundry" -ForegroundColor White
    Write-Host "  • Testing: curl $apiUrl/health" -ForegroundColor White
} else {
    Write-Host "`n=== Deployment Complete (Warning) ===" -ForegroundColor Yellow
    Write-Host "Could not retrieve Container App URL automatically." -ForegroundColor Yellow
    Write-Host "Check deployment status in Azure Portal:" -ForegroundColor Yellow
    Write-Host "  Container App: $containerAppName" -ForegroundColor White
    Write-Host "  Resource Group: $ResourceGroupName" -ForegroundColor White
}
