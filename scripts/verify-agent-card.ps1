<#
.SYNOPSIS
    Fetches and displays the A2A agent card for a Foundry agent.

.DESCRIPTION
    Resolves the Foundry project endpoint and retrieves the v1.0 A2A agent card
    for the specified agent. Use this to confirm that incoming A2A is enabled and
    that the description and skills are correct before wiring up the orchestrator.

.PARAMETER FoundryName
    The Foundry account name (Azure Cognitive Services account).

.PARAMETER ResourceGroupName
    The resource group that contains the Foundry account.

.PARAMETER ProjectName
    The Foundry project name.

.PARAMETER AgentName
    The name of the agent whose card you want to inspect.

.EXAMPLE
    .\scripts\verify-agent-card.ps1 `
        -FoundryName       "my-foundry-account" `
        -ResourceGroupName "my-resource-group" `
        -ProjectName       "my-project" `
        -AgentName         "audit-status-agent"
#>
param(
    [Parameter(Mandatory)][string]$FoundryName,
    [Parameter(Mandatory)][string]$ResourceGroupName,
    [Parameter(Mandatory)][string]$ProjectName,
    [Parameter(Mandatory)][string]$AgentName
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$az = Get-Command az -ErrorAction Stop

# ---------------------------------------------------------------------------
# Resolve project endpoint
# ---------------------------------------------------------------------------
Write-Host "Resolving Foundry project endpoint..."
$accountEndpoint = & $az cognitiveservices account show `
    --name $FoundryName `
    --resource-group $ResourceGroupName `
    --query "properties.endpoint" -o tsv

if ([string]::IsNullOrWhiteSpace($accountEndpoint)) {
    Write-Error "Could not resolve Foundry account endpoint. Verify -FoundryName and -ResourceGroupName."
    exit 1
}

$projectEndpoint = $accountEndpoint.TrimEnd('/') + "/api/projects/$ProjectName"

# ---------------------------------------------------------------------------
# Acquire token
# ---------------------------------------------------------------------------
$token = & $az account get-access-token --resource https://ai.azure.com --query accessToken -o tsv
if ([string]::IsNullOrWhiteSpace($token)) {
    Write-Error "Failed to acquire access token. Run 'az login' and try again."
    exit 1
}

# ---------------------------------------------------------------------------
# Fetch the v1.0 agent card
# ---------------------------------------------------------------------------
$cardUrl = "$projectEndpoint/agents/$AgentName/endpoint/protocols/a2a/agentCard/v1.0"
Write-Host "Fetching agent card for '$AgentName'..."
Write-Host "  URL: $cardUrl"
Write-Host ""

try {
    $card = Invoke-RestMethod `
        -Method Get `
        -Uri $cardUrl `
        -Headers @{ Authorization = "Bearer $token" }
}
catch {
    Write-Error "Failed to fetch agent card: $_`n`nMake sure A2A is enabled on '$AgentName' by running enable-a2a.ps1 first."
    exit 1
}

# ---------------------------------------------------------------------------
# Display key fields
# ---------------------------------------------------------------------------
Write-Host "Agent card retrieved successfully."
Write-Host ""
Write-Host "  Name        : $($card.name)"
Write-Host "  Description : $($card.description)"
Write-Host "  Version     : $($card.version)"
Write-Host "  Protocol    : $($card.protocolVersion)"
Write-Host ""

if ($card.skills) {
    Write-Host "  Skills:"
    foreach ($skill in $card.skills) {
        Write-Host "    - [$($skill.id)] $($skill.name): $($skill.description)"
    }
    Write-Host ""
}

Write-Host "Full agent card:"
$card | ConvertTo-Json -Depth 6
