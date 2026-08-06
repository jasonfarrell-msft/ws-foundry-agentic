<#
.SYNOPSIS
    Enables incoming A2A on a Foundry agent.

.DESCRIPTION
    Patches the target agent to activate the A2A protocol and publish an agent card.
    The base A2A endpoint is used by calling agents (e.g., orchestrators) to invoke
    this agent. The agent card URL is provided for verification only.

.PARAMETER FoundryName
    The Foundry account name (Azure Cognitive Services account).

.PARAMETER ResourceGroupName
    The resource group that contains the Foundry account.

.PARAMETER ProjectName
    The Foundry project name.

.PARAMETER AgentName
    The name of the agent to expose as an A2A endpoint.

.PARAMETER AgentDescription
    Description surfaced in the agent card so calling agents know what this agent does.

.PARAMETER AgentVersion
    Semantic version string placed in the agent card. Defaults to "1.0".
#>
param(
    [Parameter(Mandatory)][string]$FoundryName,
    [Parameter(Mandatory)][string]$ResourceGroupName,
    [Parameter(Mandatory)][string]$ProjectName,
    [Parameter(Mandatory)][string]$AgentName,
    [string]$AgentDescription = "A Foundry agent exposed via A2A",
    [string]$AgentVersion = "1.0"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$az = Get-Command az -ErrorAction Stop

# ---------------------------------------------------------------------------
# 1. Resolve the Foundry project endpoint
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

$projectEndpoint = "https://$FoundryName.services.ai.azure.com/api/projects/$ProjectName"
Write-Host "  Project endpoint : $projectEndpoint"

# ---------------------------------------------------------------------------
# 2. Acquire a Foundry-scoped Entra token
# ---------------------------------------------------------------------------
$token = & $az account get-access-token --resource https://ai.azure.com --query accessToken -o tsv
if ([string]::IsNullOrWhiteSpace($token)) {
    Write-Error "Failed to acquire access token. Run 'az login' and try again."
    exit 1
}

# ---------------------------------------------------------------------------
# 3. Enable A2A on the agent via PATCH
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "Enabling A2A on '$AgentName'..."

$patchBody = @{
    agent_card = @{
        description = $AgentDescription
        version     = $AgentVersion
        skills      = @(
            @{
                id          = "default"
                name        = $AgentName
                description = $AgentDescription
            }
        )
    }
    agent_endpoint = @{
        protocol_configuration = @{
            responses = @{}
            a2a       = @{}
        }
    }
} | ConvertTo-Json -Depth 6

try {
    $patchResult = Invoke-RestMethod `
        -Method Patch `
        -Uri "$projectEndpoint/agents/$AgentName`?api-version=v1" `
        -Headers @{ Authorization = "Bearer $token" } `
        -ContentType "application/json" `
        -Body $patchBody
    Write-Host "  A2A enabled. Agent card version: $($patchResult.agent_card.version)"
}
catch {
    Write-Error "Failed to enable A2A: $_"
    exit 1
}

$a2aBaseUrl = "$projectEndpoint/agents/$AgentName/endpoint/protocols/a2a"

# ---------------------------------------------------------------------------
# 4. Summary
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "A2A setup complete."
Write-Host "  Agent A2A base URL : $a2aBaseUrl"
$agentCardUrl = "$a2aBaseUrl/agentCard/v1.0"
Write-Host "  Agent card URL (v1.0): $agentCardUrl"
Write-Host ""
Write-Host "Next step (for prompt orchestrator in Step 3 of Part 3):"
Write-Host "  Copy the Agent A2A base URL above and paste it into the A2A Tool dialog."
Write-Host "  Do not paste the Agent card URL; Foundry discovers the card automatically."
