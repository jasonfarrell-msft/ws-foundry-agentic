[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ConnectionString,

    [Parameter(Mandatory = $false)]
    [string]$SourcePath = (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath "data/docs")
)

$ErrorActionPreference = "Stop"
if ($PSVersionTable.PSVersion.Major -ge 7) {
    $PSNativeCommandUseErrorActionPreference = $true
}

function Assert-CommandExists {
    param([Parameter(Mandatory = $true)][string]$CommandName)

    if (-not (Get-Command $CommandName -ErrorAction SilentlyContinue)) {
        throw "Required command '$CommandName' was not found. Install it and retry."
    }
}

function Invoke-AzCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    & az @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Azure CLI command failed: az $($Arguments -join ' ')"
    }
}

Assert-CommandExists -CommandName "az"

if (-not (Test-Path -Path $SourcePath -PathType Container)) {
    throw "Source directory does not exist: $SourcePath"
}
$resolvedSourcePath = (Resolve-Path -Path $SourcePath).Path

$containerName = "docs"
$exists = az storage container exists `
    --connection-string $ConnectionString `
    --name $containerName `
    --query "exists" `
    --output tsv `
    --only-show-errors
if ($LASTEXITCODE -ne 0) {
    throw "Failed to check if container '$containerName' exists. Verify the connection string and try again."
}

if ($exists -ne "true") {
    Invoke-AzCommand -Arguments @(
        "storage", "container", "create",
        "--connection-string", $ConnectionString,
        "--name", $containerName,
        "--public-access", "off",
        "--only-show-errors"
    )
}

Invoke-AzCommand -Arguments @(
    "storage", "blob", "upload-batch",
    "--connection-string", $ConnectionString,
    "--destination", $containerName,
    "--source", $resolvedSourcePath,
    "--overwrite", "true",
    "--only-show-errors"
)

Write-Host "Upload complete: '$resolvedSourcePath' -> container '$containerName'."
