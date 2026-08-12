#!/usr/bin/env pwsh

<#
.SYNOPSIS
Retrieves the HTTPS URL for the MCP server deployed in Part 2.

.PARAMETER Initials
User initials used for resource naming in Part 2.

.PARAMETER ResourceGroupName
Azure resource group containing the MCP server Container App.

.EXAMPLE
.\scripts\get-mcp-url.ps1 -Initials "jf" -ResourceGroupName "rg-agent-ws-mx01"
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$Initials,

    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName
)

$containerAppName = "aca-agentws-mcp-$Initials-lx01"

$mcpServerFqdn = az containerapp show `
    --name $containerAppName `
    --resource-group $ResourceGroupName `
    --query "properties.configuration.ingress.fqdn" `
    --output tsv

if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($mcpServerFqdn)) {
    Write-Error "Failed to retrieve the MCP server URL for '$containerAppName'. Confirm the Container App exists and that you have access to resource group '$ResourceGroupName'."
    exit 1
}

$mcpServerUrl = "https://$($mcpServerFqdn.Trim())"
Write-Host ""
Write-Host "MCP server URL (copy this into remediation-agent.json):" -ForegroundColor Cyan
Write-Host $mcpServerUrl -ForegroundColor White
Write-Host ""
