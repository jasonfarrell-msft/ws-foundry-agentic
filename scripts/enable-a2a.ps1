<#
.SYNOPSIS
    Enables incoming A2A on a Foundry agent and creates a RemoteA2A project connection.

.DESCRIPTION
    Patches the target agent to activate the A2A protocol and publish an agent card,
    then creates a RemoteA2A connection in the Foundry project so that other agents
    (such as the orchestrator) can reference it by connection name.

.PARAMETER FoundryName
    The Foundry account name (Azure Cognitive Services account).

.PARAMETER ResourceGroupName
    The resource group that contains the Foundry account.

.PARAMETER ProjectName
    The Foundry project name.

.PARAMETER AgentName
    The name of the agent to expose as an A2A endpoint.

.PARAMETER ConnectionName
    The connection to create in the project. Defaults to "<AgentName>-a2a".

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
    [string]$ConnectionName,
    [string]$AgentDescription = "A Foundry agent exposed via A2A",
    [string]$AgentVersion = "1.0"
)

if (-not $ConnectionName) {
    $ConnectionName = "$AgentName-a2a"
}

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

$projectEndpoint = $accountEndpoint.TrimEnd('/') + "/api/projects/$ProjectName"
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
# 4. Create RemoteA2A connection via ARM
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "Creating RemoteA2A connection '$ConnectionName'..."

$subscription = & $az account show --query id -o tsv
$mgmtToken    = & $az account get-access-token `
    --scope https://management.azure.com/.default `
    --query accessToken -o tsv

$connUri = "https://management.azure.com/subscriptions/$subscription" +
           "/resourceGroups/$ResourceGroupName" +
           "/providers/Microsoft.CognitiveServices/accounts/$FoundryName" +
           "/projects/$ProjectName/connections/$ConnectionName" +
           "?api-version=2025-04-01-preview"

$connBody = @{
    properties = @{
        authType    = "AgenticIdentityToken"
        category    = "RemoteA2A"
        target      = $a2aBaseUrl
        audience    = "https://ai.azure.com"
        Credentials = @{}
        metadata    = @{}
    }
} | ConvertTo-Json -Depth 4

try {
    $connResult = Invoke-RestMethod `
        -Method Put `
        -Uri $connUri `
        -Headers @{ Authorization = "Bearer $mgmtToken" } `
        -ContentType "application/json" `
        -Body $connBody
    Write-Host "  Connection created: $($connResult.name)"
}
catch {
    Write-Error "Failed to create connection: $_"
    exit 1
}

# ---------------------------------------------------------------------------
# 5. Summary
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "A2A setup complete."
Write-Host "  Agent A2A base URL : $a2aBaseUrl"
Write-Host "  Connection name    : $ConnectionName"
Write-Host ""
Write-Host "Next step: set 'a2aConnectionName' to '$ConnectionName' in orchestrator-agent.json."
