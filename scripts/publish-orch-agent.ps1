#!/usr/bin/env pwsh

param(
    [string]$ConfigPath = "src/orch-agent/orchestrator-agent.json",
    [string]$FoundryName,
    [string]$ResourceGroupName,
    [string]$ProjectName,
    [string]$ProjectEndpoint
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path $PSScriptRoot -Parent
$projectPath = Join-Path $repoRoot "src" "orch-agent" "orch-agent.csproj"
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

    $az = Get-Command az -ErrorAction SilentlyContinue
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

$tempPublishRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("orch-agent-publish-" + [System.Guid]::NewGuid().ToString("N"))
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
        Write-Host "Error: Orchestrator agent publish failed." -ForegroundColor Red
        exit $LASTEXITCODE
    }

    if (-not (Test-Path (Join-Path $tempPublishRoot "orchestrator-agent.json"))) {
        Write-Host "Error: Published output is missing orchestrator-agent.json." -ForegroundColor Red
        exit 1
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
