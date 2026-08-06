# Orchestrator Agent

Fill in `orchestrator-agent.json` with:

- `name`
- `description`
- `modelDeploymentName`
- `instructions`

Then run `scripts/publish-orch-agent.ps1 -FoundryName <resource-name> -ResourceGroupName <resource-group> -ProjectName <project-name>`. The script packages the published output, resolves the Foundry project endpoint, injects it into the published `orchestrator-agent.json`, and publishes the hosted agent. For hosted runtime startup, endpoint resolution checks `FOUNDRY_PROJECT_ENDPOINT`, then `AZURE_AI_PROJECT_ENDPOINT`, then the injected `projectEndpoint`.

If `a2aConnectionNames` are configured, the publish script also performs an A2A RBAC preflight:

- On the **first publish**, the hosted agent identity does not exist yet, so the script prints follow-up commands and continues.
- On later publishes, if the hosted agent identity is missing **Foundry User** at the Foundry project scope, the script stops and prints the exact `az role assignment create` command for a platform owner to run.
- If the script cannot verify RBAC because the current user lacks visibility, it reports that as a platform-owned prerequisite instead of guessing.
