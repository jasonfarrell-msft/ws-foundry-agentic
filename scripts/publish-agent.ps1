#!/usr/bin/env pwsh

param(
    [string]$ConfigPath = "src/remediation-agent/remediation-agent.json",
    [string]$FoundryName,
    [string]$ResourceGroupName,
    [string]$ProjectName,
    [string]$ProjectEndpoint,
    [string]$McpServerUrl
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path $PSScriptRoot -Parent
$projectPath = Join-Path $repoRoot "src" "remediation-agent" "remediation-agent.csproj"
$publisherPath = Join-Path $PSScriptRoot "orch-agent-publisher" "OrchAgentPublisher.csproj"

if (-not [System.IO.Path]::IsPathRooted($ConfigPath)) {
    $ConfigPath = Join-Path $repoRoot $ConfigPath
}

if (-not (Test-Path $ConfigPath)) {
    Write-Host "Error: Missing config file: $ConfigPath" -ForegroundColor Red
    exit 1
}

$json = Get-Content $ConfigPath -Raw
if ($json -match '__FILL_ME__') {
    Write-Host "Error: Fill in name, description, modelDeploymentName, and instructions before publishing." -ForegroundColor Red
    exit 1
}
$config = $json | ConvertFrom-Json

$az = Get-Command az -ErrorAction SilentlyContinue

function Write-RbacGuidance {
    param(
        [string]$AgentName,
        [string]$PrincipalId,
        [string]$ProjectScope,
        [string]$ProjectEndpoint
    )

    Write-Host ""
    Write-Host "A2A runtime RBAC guidance:" -ForegroundColor Yellow
    Write-Host "Hosted agent '$AgentName' needs the 'Foundry User' role at the Foundry project scope so it can call the Foundry Responses API at runtime." -ForegroundColor Yellow

    if ($PrincipalId) {
        Write-Host "Ask a platform owner to run:" -ForegroundColor Yellow
        Write-Host "az role assignment create --assignee-object-id $PrincipalId --assignee-principal-type ServicePrincipal --role `"Foundry User`" --scope `"$ProjectScope`"" -ForegroundColor Cyan
        return
    }

    Write-Host "After the first publish, retrieve the hosted agent identity:" -ForegroundColor Yellow
    Write-Host "az rest --method get --url `"$ProjectEndpoint/agents/$($AgentName)?api-version=v1`" --resource https://ai.azure.com --query `"instance_identity.principal_id`" -o tsv" -ForegroundColor Cyan
    Write-Host "Then ask a platform owner to grant:" -ForegroundColor Yellow
    Write-Host "az role assignment create --assignee-object-id <principal-id> --assignee-principal-type ServicePrincipal --role `"Foundry User`" --scope `"$ProjectScope`"" -ForegroundColor Cyan
}

function Resolve-A2AConnectionIds {
    param(
        [string[]]$ConnectionNames,
        [string]$ProjectScope,
        [System.Management.Automation.CommandInfo]$AzCommand
    )

    $ids = @()
    foreach ($name in $ConnectionNames) {
        $armUrl = "https://management.azure.com$ProjectScope/connections/$($name)?api-version=2025-04-01-preview"
        $result = & $AzCommand.Source rest --method get --url $armUrl --only-show-errors 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  [WARNING] Could not resolve ARM ID for connection '$name': $([string]$result)" -ForegroundColor Yellow
            continue
        }
        $connObj = [string]$result | ConvertFrom-Json
        if ($connObj.id) {
            $ids += $connObj.id
            Write-Host "  [OK] Resolved connection '$name'" -ForegroundColor DarkGray
        }
    }
    return ,$ids
}

function Test-A2ARuntimeRbac {
    param(
        [string]$AgentName,
        [string]$ProjectEndpoint,
        [string]$ProjectScope,
        [System.Management.Automation.CommandInfo]$AzCommand
    )

    if (-not $AzCommand) {
        return @{
            Status = "unknown"
            Reason = "Azure CLI is not available, so the script cannot inspect hosted agent RBAC."
        }
    }

    $agentResponse = & $AzCommand.Source rest `
        --method get `
        --url "$ProjectEndpoint/agents/$($AgentName)?api-version=v1" `
        --resource https://ai.azure.com `
        --only-show-errors 2>&1

    if ($LASTEXITCODE -ne 0) {
        $message = [string]$agentResponse
        if ($message -match "404|NotFound") {
            return @{ Status = "agentMissing" }
        }

        return @{
            Status = "unknown"
            Reason = "Could not inspect hosted agent identity. $message"
        }
    }

    $agent = $agentResponse | ConvertFrom-Json
    $principalId = [string]$agent.instance_identity.principal_id
    if ([string]::IsNullOrWhiteSpace($principalId)) {
        return @{
            Status = "unknown"
            Reason = "Foundry did not return a hosted agent principal ID."
        }
    }

    $roleCount = & $AzCommand.Source role assignment list `
        --assignee-object-id $principalId `
        --scope $ProjectScope `
        --include-inherited `
        --query "[?roleDefinitionName=='Foundry User'] | length(@)" `
        --output tsv `
        --only-show-errors 2>&1

    if ($LASTEXITCODE -ne 0) {
        return @{
            Status = "unknown"
            PrincipalId = $principalId
            Reason = "Could not verify project-scope role assignments. $([string]$roleCount)"
        }
    }

    if ([int]$roleCount -gt 0) {
        return @{
            Status = "present"
            PrincipalId = $principalId
        }
    }

    return @{
        Status = "missing"
        PrincipalId = $principalId
    }
}

if (-not $ProjectEndpoint) {
    $ProjectEndpoint = $env:FOUNDRY_PROJECT_ENDPOINT
}

if (-not $ProjectEndpoint) {
    if (-not $FoundryName -or -not $ResourceGroupName) {
        Write-Host "Error: Provide -ProjectEndpoint or all of -FoundryName, -ResourceGroupName, and -ProjectName." -ForegroundColor Red
        exit 1
    }

    if (-not $ProjectName) {
        Write-Host "Error: Provide -ProjectName when resolving the Foundry project endpoint." -ForegroundColor Red
        exit 1
    }

    if (-not $az) {
        Write-Host "Error: Azure CLI is required to resolve the Foundry project endpoint." -ForegroundColor Red
        exit 1
    }

    $accountArgs = @(
        "cognitiveservices", "account", "show",
        "--name", $FoundryName,
        "--resource-group", $ResourceGroupName,
        "--query", "properties.endpoint",
        "--output", "tsv"
    )

    $accountEndpoint = & $az.Source @accountArgs 2>&1

    if ($LASTEXITCODE -ne 0) {
        Write-Host $accountEndpoint -ForegroundColor Red
        Write-Host "Error: Failed to resolve the Foundry project endpoint." -ForegroundColor Red
        exit 1
    }

    $accountEndpoint = [string]$accountEndpoint
    $accountEndpoint = $accountEndpoint.Trim()
    if (-not $accountEndpoint) {
        Write-Host "Error: Foundry account endpoint was empty." -ForegroundColor Red
        exit 1
    }

    $ProjectEndpoint = "{0}/api/projects/{1}" -f $accountEndpoint.TrimEnd('/'), $ProjectName
}

if ([string]::IsNullOrWhiteSpace($McpServerUrl)) {
    Write-Host "Error: Provide -McpServerUrl using the endpoint printed by scripts/deploy-mcp.ps1." -ForegroundColor Red
    exit 1
}

$projectScope = $null
if ($az -and $FoundryName -and $ResourceGroupName -and $ProjectName) {
    $subscriptionId = & $az.Source account show --query id --output tsv --only-show-errors 2>&1
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace([string]$subscriptionId)) {
        $projectScope = "/subscriptions/$([string]$subscriptionId)/resourceGroups/$ResourceGroupName/providers/Microsoft.CognitiveServices/accounts/$FoundryName/projects/$ProjectName"
    }
}

$configuredA2aConnections = if ($null -ne $config.a2aConnectionNames) { @($config.a2aConnectionNames) } else { @() }
if ($configuredA2aConnections.Count -gt 0) {
    if ($projectScope) {
        Write-Host "Checking hosted agent RBAC for A2A connections..." -ForegroundColor Yellow
        $rbacCheck = Test-A2ARuntimeRbac `
            -AgentName $config.name `
            -ProjectEndpoint $ProjectEndpoint `
            -ProjectScope $projectScope `
            -AzCommand $az

        switch ($rbacCheck.Status) {
            "present" {
                Write-Host "  [OK] Hosted agent identity already has 'Foundry User' at the project scope." -ForegroundColor Green
            }
            "missing" {
                Write-Host "Error: Hosted agent identity is missing 'Foundry User' at the Foundry project scope." -ForegroundColor Red
                Write-Host "Publishing now would produce a hosted agent that starts but cannot load its RemoteA2A connections." -ForegroundColor Red
                Write-RbacGuidance `
                    -AgentName $config.name `
                    -PrincipalId $rbacCheck.PrincipalId `
                    -ProjectScope $projectScope `
                    -ProjectEndpoint $ProjectEndpoint
                exit 1
            }
            "agentMissing" {
                Write-Host "No existing hosted agent named '$($config.name)' was found. The first publish will create its runtime identity." -ForegroundColor Yellow
                Write-Host "After the first publish completes, rerun this script so it can verify the A2A RBAC prerequisite." -ForegroundColor Yellow
                Write-RbacGuidance `
                    -AgentName $config.name `
                    -PrincipalId $null `
                    -ProjectScope $projectScope `
                    -ProjectEndpoint $ProjectEndpoint
            }
            default {
                Write-Host "Warning: Unable to verify hosted agent RBAC before publish." -ForegroundColor Yellow
                Write-Host "  $($rbacCheck.Reason)" -ForegroundColor Yellow
                Write-Host "Treat this as a platform prerequisite if you do not have RBAC visibility." -ForegroundColor Yellow
                Write-RbacGuidance `
                    -AgentName $config.name `
                    -PrincipalId $rbacCheck.PrincipalId `
                    -ProjectScope $projectScope `
                    -ProjectEndpoint $ProjectEndpoint
            }
        }
    }
    else {
        Write-Host "Warning: Skipping hosted agent RBAC preflight because the Foundry project scope could not be determined." -ForegroundColor Yellow
        Write-Host "Provide -FoundryName, -ResourceGroupName, and -ProjectName so the script can check the A2A RBAC prerequisite." -ForegroundColor Yellow
    }
}

$tempPublishRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("remediation-agent-publish-" + [System.Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $tempPublishRoot | Out-Null

try {
    Write-Host "Publishing hosted agent code..." -ForegroundColor Yellow
    dotnet publish $projectPath `
        -c Release `
        -r linux-x64 `
        --self-contained false `
        -o $tempPublishRoot `
        --nologo
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Error: Remediation agent publish failed." -ForegroundColor Red
        exit $LASTEXITCODE
    }

    if (-not (Test-Path (Join-Path $tempPublishRoot "remediation-agent.json"))) {
        Write-Host "Error: Published output is missing remediation-agent.json." -ForegroundColor Red
        exit 1
    }

    $publishedConfigPath = Join-Path $tempPublishRoot "remediation-agent.json"
    $publishedConfig = Get-Content $publishedConfigPath -Raw | ConvertFrom-Json
    $publishedConfig | Add-Member -NotePropertyName "projectEndpoint" -NotePropertyValue $ProjectEndpoint -Force
    if (-not [string]::IsNullOrWhiteSpace($McpServerUrl)) {
        $publishedConfig | Add-Member -NotePropertyName "mcpServerUrl" -NotePropertyValue $McpServerUrl.TrimEnd('/') -Force
    }

    # Resolve A2A connection ARM IDs at publish time so the runtime can use them
    # directly without calling GetConnection (which requires elevated permissions).
    if ($configuredA2aConnections.Count -gt 0 -and $projectScope -and $az) {
        Write-Host "Resolving A2A connection ARM IDs..." -ForegroundColor Yellow
        $resolvedIds = Resolve-A2AConnectionIds `
            -ConnectionNames $configuredA2aConnections `
            -ProjectScope $projectScope `
            -AzCommand $az
        if ($resolvedIds.Count -gt 0) {
            $publishedConfig | Add-Member -NotePropertyName "a2aConnectionIds" -NotePropertyValue $resolvedIds -Force
            Write-Host "Injected $($resolvedIds.Count) A2A connection ARM ID(s) into published remediation-agent.json." -ForegroundColor DarkGray
        } else {
            Write-Host "Warning: No A2A connection ARM IDs were resolved. Runtime will fall back to GetConnection (may fail without elevated permissions)." -ForegroundColor Yellow
        }
    }

    $publishedConfig | ConvertTo-Json -Depth 20 | Set-Content -Path $publishedConfigPath -Encoding UTF8
    Write-Host "Injected project endpoint into published remediation-agent.json." -ForegroundColor DarkGray
    if (-not [string]::IsNullOrWhiteSpace($McpServerUrl)) {
        Write-Host "Injected audit MCP server URL into published remediation-agent.json." -ForegroundColor DarkGray
    }

    Write-Host "Publishing hosted agent to Foundry..." -ForegroundColor Yellow
    dotnet run `
        --project $publisherPath `
        -- `
        --project-endpoint $ProjectEndpoint `
        --package-path $tempPublishRoot
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Error: Foundry publish failed." -ForegroundColor Red
        exit $LASTEXITCODE
    }
}
finally {
    if (Test-Path $tempPublishRoot) {
        Remove-Item -Recurse -Force $tempPublishRoot
    }
}
