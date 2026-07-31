# Orchestrator Agent

Fill in `orchestrator-agent.json` with:

- `name`
- `description`
- `modelDeploymentName`
- `instructions`

Then run `scripts/publish-orch-agent.ps1 -FoundryName <resource-name> -ResourceGroupName <resource-group> -ProjectName <project-name>`. The script packages the published output, resolves the Foundry project endpoint, and publishes the hosted agent using the values from `orchestrator-agent.json`. You can also set `FOUNDRY_PROJECT_ENDPOINT` directly.
