<#
.SYNOPSIS
    Grants the orchestrator agent permission to call A2A agents.

.DESCRIPTION
    Finds the automatically created identity for the orchestrator prompt agent
    and assigns it the Foundry Agent Consumer role on the Foundry project. This
    role is required for incoming A2A calls, even when all agents live in the
    same project. The Foundry portal's role picker may not list this role yet;
    the role definition exists in the tenant and can be assigned via the CLI.

.PARAMETER FoundryName
    The Foundry account name.

.PARAMETER ResourceGroupName
    The resource group that contains the Foundry account.

.PARAMETER ProjectName
    The Foundry project name.

.PARAMETER AgentName
    The orchestrator agent name.

.EXAMPLE
    .\scripts\grant-a2a-access.ps1 `
        -FoundryName "my-foundry-account" `
        -ResourceGroupName "rg-agent-ws-mx01" `
        -ProjectName "main-project" `
        -AgentName "orchestrator-prompt-agent"
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
$Role = "Foundry Agent Consumer"

Write-Host "Retrieving the identity for '$AgentName'..."
$agentUrl = "https://$FoundryName.services.ai.azure.com/api/projects/$ProjectName/agents/$AgentName`?api-version=v1"
$agent = & $az rest `
    --method get `
    --url $agentUrl `
    --resource https://ai.azure.com |
    ConvertFrom-Json

$principalId = $agent.instance_identity.principal_id
if ([string]::IsNullOrWhiteSpace($principalId)) {
    Write-Error "The agent identity is not available. Publish or activate '$AgentName', then run this script again."
    exit 1
}

$subscriptionId = & $az account show --query id -o tsv
if ([string]::IsNullOrWhiteSpace($subscriptionId)) {
    Write-Error "Could not determine the active Azure subscription."
    exit 1
}

$projectScope = "/subscriptions/$subscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.CognitiveServices/accounts/$FoundryName/projects/$ProjectName"

Write-Host "Assigning '$Role' to the orchestrator identity..."
& $az role assignment create `
    --role $Role `
    --assignee-object-id $principalId `
    --assignee-principal-type ServicePrincipal `
    --scope $projectScope | Out-Null

Write-Host ""
Write-Host "A2A access granted."
Write-Host "  Agent      : $AgentName"
Write-Host "  Principal  : $principalId"
Write-Host "  Role       : $Role"
Write-Host "  Scope      : $projectScope"
