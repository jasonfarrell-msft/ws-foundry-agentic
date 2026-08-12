#!/usr/bin/env pwsh

<#
.SYNOPSIS
Deploys the MCP server to Azure Container Apps

.DESCRIPTION
This script builds the MCP server image in the container registry and deploys it to 
Azure Container Apps. It requires the Audit API URL to be passed as an environment variable.

.PARAMETER Initials
User initials for resource naming (e.g., 'jf')

.PARAMETER ResourceGroupName
Azure resource group name where resources were deployed in Part 2

.PARAMETER ApiUrl
The Audit API URL (from setup-part2.ps1 output). If not provided, uses AUDIT_API_URL env var.

.EXAMPLE
pwsh scripts/deploy-mcp.ps1 -Initials "jf" -ResourceGroupName "rg-agent-ws-mx01" -ApiUrl "https://aca-agentws-api-jf-eastus.azurecontainerapps.io"
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$Initials,

    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $false)]
    [string]$ApiUrl = $env:AUDIT_API_URL
)

# Validate inputs
if ([string]::IsNullOrEmpty($ApiUrl)) {
    Write-Error "API URL not provided. Either pass -ApiUrl or set AUDIT_API_URL environment variable."
    exit 1
}

# Get resource group location
Write-Host "Retrieving resource group location..."
$rgInfo = az group show --name $ResourceGroupName --query "location" -o tsv
if (-not $?) {
    Write-Error "Failed to retrieve resource group. Ensure it exists and you have permissions."
    exit 1
}

$location = $rgInfo.Trim()
Write-Host "Using location: $location"

# Resource names
$registryName = "cragentws$($Initials)lx01"
$containerEnvName = "ce-agentws-$($Initials)-lx01"
$containerAppName = "aca-agentws-mcp-$($Initials)-lx01"

Write-Host "`nDeploying MCP Server..."
Write-Host "Registry: $registryName"
Write-Host "Container Environment: $containerEnvName"
Write-Host "Container App: $containerAppName"

# Build and push MCP server image
Write-Host "`n[1/3] Building MCP server image in container registry..."
az acr build `
    --registry $registryName `
    --image audit-mcp-server:v1 `
    --file src/mcp/Dockerfile `
    src/mcp

if (-not $?) {
    Write-Error "Failed to build and push MCP server image."
    exit 1
}

Write-Host "✓ MCP server image built and pushed"

# Get container environment ID
Write-Host "`n[2/3] Retrieving container environment..."
$containerEnvId = az containerapp env show `
    --name $containerEnvName `
    --resource-group $ResourceGroupName `
    --query "id" -o tsv

if (-not $?) {
    Write-Error "Failed to retrieve container environment. It may not exist from Part 2."
    exit 1
}

Write-Host "✓ Container environment retrieved"

# Get registry login credentials
Write-Host "`n[3/3] Creating container app for MCP server..."
$registryUrl = "$registryName.azurecr.io"
$registryUsername = az acr credential show --resource-group $ResourceGroupName --name $registryName --query "username" -o tsv
$registryPassword = az acr credential show --resource-group $ResourceGroupName --name $registryName --query "passwords[0].value" -o tsv

# Create or update container app
$revisionSuffix = "mcp-" + (Get-Date -Format "yyyyMMddHHmmss")
az containerapp create `
    --name $containerAppName `
    --resource-group $ResourceGroupName `
    --environment $containerEnvId `
    --image "$registryUrl/audit-mcp-server:v1" `
    --registry-server $registryUrl `
    --registry-username $registryUsername `
    --registry-password $registryPassword `
    --env-vars "AUDIT_API_URL=$ApiUrl" "PORT=8001" `
    --target-port 8001 `
    --ingress 'external' `
    --min-replicas 1 `
    --max-replicas 10 `
    --cpu 0.5 `
    --memory 1Gi `
    --query "properties.configuration.ingress.fqdn" -o tsv 2>/dev/null

if ($?) {
    Write-Host "✓ Container app created"
} else {
    # If create failed, try update
    Write-Host "Container app may already exist, attempting update..."
    az containerapp update `
        --name $containerAppName `
        --resource-group $ResourceGroupName `
        --image "$registryUrl/audit-mcp-server:v1" `
        --set-env-vars "AUDIT_API_URL=$ApiUrl" "PORT=8001" `
        --revision-suffix $revisionSuffix `
        --min-replicas 1 `
        --max-replicas 10 `
        > $null
    
    if (-not $?) {
        Write-Error "Failed to create or update container app."
        exit 1
    }
}

# Get the FQDN
$mcpServerUrl = az containerapp show `
    --name $containerAppName `
    --resource-group $ResourceGroupName `
    --query "properties.configuration.ingress.fqdn" -o tsv

if ([string]::IsNullOrEmpty($mcpServerUrl)) {
    Write-Error "Failed to retrieve MCP server URL."
    exit 1
}

$mcpEndpoint = "https://$mcpServerUrl"

Write-Host ""
Write-Host "════════════════════════════════════════════════════════════"
Write-Host "MCP SERVER URL (copy and paste into Foundry Tools config):"
Write-Host "════════════════════════════════════════════════════════════"
Write-Host ""
Write-Host $mcpEndpoint
Write-Host ""
Write-Host "════════════════════════════════════════════════════════════"
Write-Host ""
Write-Host "✓ MCP server is now running and ready to be connected in Foundry"
Write-Host ""
