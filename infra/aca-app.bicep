@description('Deployment location.')
param location string = resourceGroup().location

@description('Container App name.')
param containerAppName string = 'workshop-audit-api'

@description('Container Apps environment resource ID.')
param containerAppsEnvironmentId string

@description('Azure Container Registry login server.')
param acrLoginServer string

@description('Azure Container Registry resource ID.')
param acrResourceId string

@description('Container image, including tag, hosted in ACR.')
param containerImage string

@secure()
@description('API key for agent-1-orchestrator.')
param mcpApiKeyAgent1 string

@secure()
@description('API key for agent-2-audit-readiness.')
param mcpApiKeyAgent2 string

@secure()
@description('API key for agent-4-remediation.')
param mcpApiKeyAgent4 string

@secure()
@description('API key for human-approver.')
param mcpApiKeyHumanApprover string

@description('User-assigned managed identity name for the Container App.')
param userAssignedIdentityName string = '${containerAppName}-uami'

resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = {
  name: last(split(acrResourceId, '/'))
}

resource uami 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: userAssignedIdentityName
  location: location
}

resource acrPullRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acr.id, uami.id, 'acrpull')
  scope: acr
  properties: {
    principalId: uami.properties.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')
    principalType: 'ServicePrincipal'
  }
}

resource containerApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: containerAppName
  location: location
  dependsOn: [
    acrPullRoleAssignment
  ]
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${uami.id}': {}
    }
  }
  properties: {
    managedEnvironmentId: containerAppsEnvironmentId
    configuration: {
      secrets: [
        {
          name: 'mcp-api-key-agent-1'
          value: mcpApiKeyAgent1
        }
        {
          name: 'mcp-api-key-agent-2'
          value: mcpApiKeyAgent2
        }
        {
          name: 'mcp-api-key-agent-4'
          value: mcpApiKeyAgent4
        }
        {
          name: 'mcp-api-key-human-approver'
          value: mcpApiKeyHumanApprover
        }
      ]
      ingress: {
        external: true
        targetPort: 8080
        transport: 'auto'
      }
      registries: [
        {
          server: acrLoginServer
          identity: uami.id
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'api'
          image: containerImage
          resources: {
            cpu: json('0.5')
            memory: '1Gi'
          }
          env: [
            {
              name: 'MCP_API_KEY_AGENT_1'
              secretRef: 'mcp-api-key-agent-1'
            }
            {
              name: 'MCP_API_KEY_AGENT_2'
              secretRef: 'mcp-api-key-agent-2'
            }
            {
              name: 'MCP_API_KEY_AGENT_4'
              secretRef: 'mcp-api-key-agent-4'
            }
            {
              name: 'MCP_API_KEY_HUMAN_APPROVER'
              secretRef: 'mcp-api-key-human-approver'
            }
            {
              name: 'PORT'
              value: '8080'
            }
          ]
          probes: [
            {
              type: 'Liveness'
              httpGet: {
                path: '/health'
                port: 8080
              }
              initialDelaySeconds: 10
              periodSeconds: 15
            }
            {
              type: 'Readiness'
              httpGet: {
                path: '/health'
                port: 8080
              }
              initialDelaySeconds: 5
              periodSeconds: 10
            }
          ]
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: 1
      }
    }
  }
}

output containerAppUrl string = 'https://${containerApp.properties.configuration.ingress.fqdn}'
