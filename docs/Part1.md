# Part 1: Microsoft Foundry Foundation Setup

[Final Architecture Diagram](./final-architecture.svg)

## Objective

Stand up the workshop foundation: resource group, shared Application Insights for telemetry, Microsoft Foundry and `main-project`, a chat model deployment, the policy-and-audit corpus in Blob Storage, Foundry IQ over that corpus, and the `policy-audit-info-agent` that answers from it.

**Why this matters:** In a regulated setting, an assistant that answers from general model knowledge is a liability — a confident, unsupported claim about a requirement is worse than no answer, and the cost of one wrong answer trusted by the wrong person dwarfs the cost of the tooling that would have caught it. Grounding answers in a controlled corpus with citations makes them reviewable and traceable to source. The telemetry you wire up here is what keeps every later part observable rather than a black box.

**Diagram color:** Purple — Foundry foundation and grounded policy agent.

## Prerequisites

- An Azure subscription with permission to **create resources and assign RBAC roles** on the Foundry resource and storage account
- Model quota for a **GPT 5.2 or higher** deployment (GPT-5.4 recommended)
- [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) (`az`), logged in via `az login`
- [PowerShell 7+](https://learn.microsoft.com/powershell/scripting/install/installing-powershell)

---

## 1) Create the resource group and Application Insights

Application Insights is created first so that every component you deploy or configure in Parts 1–4 can send application traces to the same destination. Use its backing Log Analytics workspace for Foundry resource diagnostics as well. Each component still needs its own tracing configuration; creating Application Insights alone does not enable collection.

- **Resource group:** `rg-agent-ws-mx01`
- **Application Insights name:** `appi-agentapp-<initials>-mx01` — for example, `appi-agentapp-jrf-mx01`
- **Region:** The region you will use for every other workshop resource

1. Open the [Azure portal](https://portal.azure.com).
2. Create a new resource group named **`rg-agent-ws-mx01`** in your chosen region.
3. Search for **Application Insights** and select **+ Create**.
4. On the **Basics** tab, set:
    - **Subscription:** Your workshop subscription
    - **Resource group:** `rg-agent-ws-mx01`
    - **Name:** `appi-agentapp-<initials>-mx01`
    - **Region:** The same region as the resource group and all other workshop resources
    - **Resource mode:** **Workspace-based** (create a new Log Analytics workspace if prompted)
5. Select **Review + create**, then **Create**, and wait for deployment to complete.
6. Open the new Application Insights resource, go to **Overview**, and copy the **Connection String**.

> **Keep this connection string handy.** In Section 2, you select this Application Insights resource in Foundry rather than paste its connection string. The Container Apps components deployed in Part 2 need their own exporter configuration. Do not commit connection strings to source control; supply configuration through Azure Key Vault-backed environment variables. Also note the **Log Analytics workspace** linked on the Application Insights **Overview** page; you will select that workspace for resource diagnostics.

## 2) Create Microsoft Foundry resource and project

Complete this section exactly in the Azure portal with fixed values:

- **Resource group:** `rg-agent-ws-mx01`
- **Project name (default):** `main-project`
- **Networking:** Public
- **All other settings:** Use defaults

1. Open the **Azure portal**.
2. Search for **Microsoft Foundry**, choose **Foundry** from the left nav and select **Create**.
3. In the creation wizard:
   - Select resource group: **`rg-agent-ws-mx01`**
   - Set the name to **`foundry-agent-ws-jrf-mx01`** (jrf is your initials)
   - Set the default project name to: **`main-project`**
   - Keep networking set to **Public**
   - Accept all other default settings
4. Complete the wizard and wait for deployment to finish.

### Connect Foundry observability to Application Insights

There is no **Observability** tab to open in the new Foundry portal. Microsoft Learn documents a project connection that enables **server-side agent tracing**, plus separate configuration for application instrumentation and model resource diagnostics. Complete each applicable path below; there is no single switch that captures every interaction across a Foundry resource and all its clients.

#### A. Connect the project and enable server-side agent traces

1. Sign in to [Microsoft Foundry](https://ai.azure.com), use the **new Foundry** experience (turn on **New Foundry** if the toggle is displayed), and open **`main-project`**.
2. Select **Build**, then **Agents** in the left navigation.
3. At the top of the Agents page, select **Traces**, then select **Connect** on the right.
4. Select the existing Application Insights resource **`appi-agentapp-<initials>-mx01`** in `rg-agent-ws-mx01`, then select **Connect**. Wait for the success confirmation.
5. If **Connect** is not displayed, use the documented alternative: **Manage** in the upper-right navigation → **Project details** → **Connected resources** → **Add connection** → **Application Insights**. Select the same existing resource and complete the connection.
6. In **Manage** → **Project details** → **Connected resources**, confirm the connected resource has category **AppInsights** and points to your workshop Application Insights instance.

Foundry automatically enables server-side tracing after the connection succeeds; no application code change is required for this path. It captures supported agent execution, model calls within those runs, and tool/retrieval operations visible to the service. It does not instrument the internals of a remote tool, your API, or your MCP server.

> **Scope and availability:** The connection is per project, not a resource-wide setting. Repeat it for any other Foundry project you use. Microsoft Learn identifies tracing for prompt and hosted agents as generally available; workflow and external-agent tracing are preview features. Do not assume that standalone **Model Playground** calls or arbitrary direct model API calls become agent traces just because this connection exists.

Source: [Set up tracing in Microsoft Foundry](https://learn.microsoft.com/azure/foundry/observability/how-to/trace-agent-setup).

#### B. Instrument application-side agent and model calls

For code you run locally or in Container Apps in later parts, the project connection is the destination, not the instrumentation. To capture the client side of agent calls, direct model calls, and custom tool execution:

1. Configure an **Azure Monitor OpenTelemetry** exporter in each application process, targeting the same Application Insights resource. Supply `APPLICATIONINSIGHTS_CONNECTION_STRING` through secure runtime configuration, or use the Foundry SDK's documented project telemetry lookup. An environment variable alone does not install or initialize instrumentation.
2. Enable the instrumentation appropriate to the SDK/framework **before creating clients or making calls**. Follow the language-specific [client-side tracing instructions](https://learn.microsoft.com/azure/foundry/observability/how-to/trace-agent-client-side). For example, the Python Foundry SDK requires `AZURE_EXPERIMENTAL_ENABLE_GENAI_TRACING=true` and `AIProjectInstrumentor().instrument()`; .NET and JavaScript have their own explicit opt-in settings.
3. Instrument the model client actually in use. The Python Foundry instrumentor supports OpenAI **Responses** and **Conversations** calls; do not assume it covers a separate Chat Completions client or another framework. Use the matching [framework integration](https://learn.microsoft.com/azure/foundry/observability/how-to/trace-agent-framework) for those paths, and add custom spans around application/tool logic not covered automatically.
4. Preserve **W3C trace context** across outbound agent and HTTP/tool calls so supported client, service, and tool spans correlate into an end-to-end trace. Exporting to the same resource alone does not correlate independent spans.
5. For workshop verification that requires every instrumented request rather than sampled traces, configure the SDK/exporter's sampling to retain **100%** of traces and check that ingestion sampling, telemetry processors, and daily caps are not dropping data. Do not assume the SDK defaults retain everything. This increases ingestion cost and still does not provide a lossless audit-log guarantee. For production, deliberately choose the retention/sampling tradeoff rather than leaving a troubleshooting configuration enabled. See [Application Insights sampling guidance](https://learn.microsoft.com/azure/azure-monitor/app/opentelemetry-sampling).

> **Preview and privacy:** The linked client-side GenAI instrumentation is currently documented as preview. Message-content recording is separate from tracing and is off by default in that SDK guidance. Leave it off for sensitive policy/audit data unless explicitly approved; enabling it can record prompts, model outputs, and tool arguments. Never put credentials or secrets in telemetry. Use managed identity for supported Azure authentication and least-privilege access to telemetry.

#### C. Collect resource-level model diagnostics, including playground traffic

To monitor model requests independently of whether their caller is instrumented, configure diagnostic settings on the **Foundry resource**, not just the project. These resource logs complement agent traces; they do not create an end-to-end application trace or guarantee full prompt/response content.

1. In the **Azure portal**, open **`foundry-agent-ws-<initials>-mx01`**.
2. Select **Monitoring** → **Diagnostic settings** → **+ Add diagnostic setting**.
3. Name the setting **`foundry-to-workshop-logs`**.
4. Select the available **Request and Response Logs** (`RequestResponse`) and **Azure OpenAI Request Usage** categories for inference request/usage telemetry, plus **Audit Logs** for administrative activity. Category availability depends on the resource; select the categories exposed by your resource rather than treating a missing category as enabled.
5. Select **AllMetrics** to export platform metrics.
6. Under **Destination details**, select **Send to Log Analytics workspace** and choose the **same backing workspace** linked to **`appi-agentapp-<initials>-mx01`** in Section 1. Select **Save**.

**Destination distinction:** Diagnostic settings send resource logs to **Log Analytics**, not directly into Application Insights request/dependency tables or Foundry's agent **Traces** view. Using the same workspace makes both data sets queryable together in Azure Monitor. Platform model metrics are also available in Azure Monitor without diagnostic settings; export them only when you need workspace queries. Review ingestion charges and retention for the selected categories.

> **Diagnostic data can also be sensitive.** Review the records emitted by your enabled categories, workspace access, table permissions, and retention before using this configuration with regulated or confidential workloads. Do not assume that request/response diagnostics contain only harmless metadata.

Sources: [Enable diagnostic logging for Microsoft Foundry](https://learn.microsoft.com/azure/foundry/how-to/diagnostic-logging) and [Monitor model deployments in Microsoft Foundry Models](https://learn.microsoft.com/azure/foundry/foundry-models/how-to/monitor-models#configure-diagnostic-settings).

#### D. Verify collection after creating the model and agent

Complete these checks after Sections 3 and 6; a connected resource alone is not evidence that telemetry is arriving.

1. Ensure the person querying traces has **Log Analytics Reader** access on the connected Application Insights resource and appropriate access to its backing workspace. Protected tables additionally require **Privileged Monitoring Data Reader**. Configuring Foundry diagnostic settings requires **Monitoring Contributor** or equivalent permissions on the Foundry resource, plus access to the destination workspace.
2. Run **`policy-audit-info-agent`** in the playground with one of the Section 7 questions. Note the time and response/conversation ID.
3. Return to **Build** → **Agents** → **Traces**. Wait a few minutes and refresh. Open the new trace and inspect the model and Foundry IQ/tool spans, status, and duration. You can also inspect agent **Traces** and **Monitor** tabs; neither requires an **Observability** navigation tab.
4. Open the workshop **Application Insights** resource in the Azure portal and select **Agents (Preview)** for the agent visualizations. Inspect the **Models** and **Tool Calls** tiles, then select **View Traces with Agent Runs** and open a trace's **End-to-end transaction details** to see its agent, model, and tool steps. This view requires agent telemetry using OpenTelemetry GenAI semantic conventions; sending resource diagnostic logs to the same workspace alone does not populate it. The dedicated Agents view is preview; use **Logs** or the available transaction diagnostics to investigate the underlying telemetry if the view is unavailable. See [Monitor AI agents with Application Insights](https://learn.microsoft.com/azure/azure-monitor/app/agents-view).
5. Make a separate **Model Playground** request. In the backing **Log Analytics workspace** → **Logs**, check the Foundry resource's diagnostic records for that time and resource ID (for example, `AzureDiagnostics` with category `RequestResponse`, where that category is enabled). Check exported platform metrics in `AzureMetrics`. Resource diagnostic ingestion can take longer than agent traces; Microsoft Learn notes that initial diagnostic data can take up to **two hours**.
6. When you add an instrumented application, make an agent call and a direct model call from that application and confirm both produce client spans in the same Application Insights instance. Check trace correlation across supported boundaries rather than assuming the server-side check covers application telemetry.

If data is absent, check the selected project/resource/workspace, generate fresh traffic after enabling collection, verify query time range and RBAC, and check exporter initialization, sampling/caps, and network access to ingestion endpoints. Do not mark observability complete until each traffic path you actually use has produced telemetry.

## 3) Deploy a model

1. In the Azure portal, navigate to resource group **`rg-agent-ws-mx01`**.
2. Select the newly created **Microsoft Foundry** instance and open it to access the Foundry portal.
3. Once in the Foundry portal, open **`main-project`** in Microsoft Foundry.
4. In the Foundry portal, select **Build** from the top navigation, then select **Models** from the left navigation.
5. Select **Deploy** button from the far right, choose **Base Model**.
6. Deploy one of the following models. These models are officially supported by Foundry IQ as the Chat completions model. Try them in order until one deploys successfully in your region/quota:

    - `gpt-5.4-mini`
    - `gpt-5.4`
    - `gpt-5.2`
    - `gpt-5.1`
    - `gpt-5-mini`

7. Click **Deploy** on the right-hand side and click **Custom settings**.
8. Set the following:
    - Deployment Name: Use the model name with `-deployment` appended, for example **`gpt-5.4-mini-deployment`**
    - Deployment Type: **Global Standard**
    - Max out Tokens per Minute Rate Limit
9. Click **Deploy** to deploy the model

Once deployed, you will land on the **Model Playground** within Foundry. You can ask questions and provide instructions to see how the model responds.

> Throughout the rest of this guide, references to deployment names mean "the chat-model deployment you created in this step." Use the actual deployment name from step 8 (e.g., `gpt-5.4-mini-deployment`).

## 4) Prepare your data

> Before creating the agent, you will provide the shared policy-and-audit corpus it will use for grounding. The storage account and uploaded documents give Foundry IQ a common evidence source for retrieval and reasoning in the later OGE audit and multi-agent exercises.

### Create Storage Account
In this section, you will create an Azure Storage account that will hold the workshop document corpus later in this part and in later parts.

1. Sign in to the [Azure portal](https://portal.azure.com).
2. Search for **Storage accounts** and select **+ Create**.
3. On the **Basics** tab, set:
    - **Subscription:** Your workshop subscription
    - **Resource group:** `rg-agent-ws-mx01`
    - **Storage account name:** `azagentws<initials>lx01`
    - Example: `azagentwsjflx01`
    - Use lowercase letters and numbers only, no spaces or hyphens, and ensure the name is globally unique.
    - **Region:** Your desired region (preferably the same region as your Foundry resource)
    - **Storage type:** Azure Blob Storage or Azure Data Lake Storage
    - **Performance:** Standard
    - **Redundancy:** LRS
4. Keep remaining settings at defaults, select **Review + create**, then **Create**.
5. Wait for deployment to complete and open the storage account resource.

### Upload the workshop corpus

After the storage account finishes provisioning, copy its connection string and run the upload script.

**Copy the connection string:**

1. Open your storage account in the Azure portal.
2. In the left navigation, select **Security + networking** → **Access keys**.
3. Under **key1** (or **key2**), select **Show** next to the **Connection string** field.
4. Copy the full connection string value.

**Run the upload script from the repository root:**

```powershell
./scripts/corpus-upload.ps1 -ConnectionString "<paste-connection-string-here>"
```

This script creates the `docs` container if needed and uploads all files from `data/docs`, overwriting blobs with the same name.

> **Security note:** Microsoft does not recommend using connection strings for Azure Storage connectivity. Connection strings contain shared keys that grant full access to the storage account and should never be committed to source control or shared. They are used here for workshop simplicity only and are not a production-grade practice. In production, use Managed Identity or Azure AD-based authentication instead.

## 5) Configure Foundry IQ

**Foundry IQ** is Microsoft Foundry's knowledge-grounding capability. It connects your agent to enterprise content so answers are grounded in your data with citations.

Your workshop corpus is already in Azure Blob Storage in the `docs` container. In this section, create an **Azure AI Search** service and a knowledge base from that source. The knowledge base must be active before you build the agent.

### Create an Azure AI Search service

Foundry IQ requires an Azure AI Search service that supports **agentic retrieval** and **semantic ranker**.

1. Open the **Azure portal**.
2. Search for **Azure AI Search** and select it.
3. Select **+ Create**.
4. On the **Basics** tab, set:
    - **Subscription:** Your workshop subscription
    - **Resource group:** `rg-agent-ws-mx01`
    - **Service name:** `srch-agentws-<initials>-lx01` — for example, `srch-agentws-jrf-lx01`
    - **Region:** Same region as your Foundry resource — confirm the region supports agentic retrieval at the [Azure AI Search region support page](https://learn.microsoft.com/azure/search/search-region-support)
    - **Pricing tier:** **Standard**

5. Select **Review + create**, then **Create**.
6. Wait for deployment to complete before continuing.

### Configure Azure AI Search identity access

Foundry IQ uses the Azure AI Search system-assigned managed identity for two separate operations: calling the embedding or chat model hosted by Foundry, and reading the documents from Azure Blob Storage. Assign both roles before creating the knowledge base.

> **Warning:** You must have permission to assign Azure roles on the Foundry resource and storage account. If you cannot assign roles, ask a subscription or resource owner to perform these steps.

#### Enable the Search managed identity

1. Open the Azure AI Search service **`srch-agentws-<initials>-lx01`**.
2. In the left navigation, select **Security + networking** → **Identity**.
3. On the **System assigned** tab, set **Status** to **On**, select **Save**. Wait for the operation to complete

#### Assign Cognitive Services User on the Foundry resource

1. Open the Foundry resource that contains the workshop project, not the project child resource.
2. Select **Access control (IAM)**.
3. Select **Add** → **Add role assignment**.
4. Select the **Cognitive Services User** role.
5. For the member, choose **Managed identity**, select the Azure AI Search service, and select **Review + assign**.

This allows Azure AI Search to call the embedding and chat model deployments used by the knowledge base.

#### Assign Storage Blob Data Reader on the Storage Account container

1. Open the storage account created in Section 4.
2. Select **Access control (IAM)**.
3. Select **Add** → **Add role assignment**.
4. Select the **Storage Blob Data Reader** role.
5. For the member, choose **Managed identity**, select the Azure AI Search service, and select **Review + assign**.

This allows Azure AI Search to read and index the workshop documents. Wait a few minutes for both role assignments to propagate before creating the knowledge source.

### Create the knowledge base in Foundry IQ

1. In the Foundry portal, open `main-project`.
2. Select **Build**, then open the **Knowledge** tab.
3. Select the Azure AI Search service you just created. **Authentication type:** You can leave **API Key** selected.
4. Click **Connect**.
5. Click **Create a knowledge base**.
6. Set the following fields before selecting a knowledge source:
    - **Name:** `kb-policy-audit-documents`
    - **Chat completions model:** Select your deployed model
    - **Retrieval reasoning effort:** `low`
    - **Output mode:** `Answer synthesis`
    - **Answer instructions:** `Answer using only retrieved evidence. Be concise, cite sources, state confidence, and identify missing evidence.`
    - **Retrieval instructions:** `Use only the connected corpus. Prioritize the most relevant policy/audit documents and sections that directly answer the question, preferring authoritative evidence with clear citation metadata. Do not use external sources.`
7. Select **Add knowledge source**, then choose **Azure Blob Storage**. ONLY modify the fields listed below:
    - **Name:** `ks-azureblob-docs`
    - **Storage account:** Select the storage account you created in Section 4.
    - **Container name:** `docs`
    - **Content extraction mode:** `Standard`
12. For **Embedding model,** deploy an instance of`text-embedding-3-small` using the **Browse more models** option
13. Click **Create**.
14. After completing the knowledge source wizard, you are returned to the knowledge base configuration page
15. Select **Save knowledge base** to save your changes
16. Refresh the knowledge base details page and confirm the **Knowledge source** status changes from **Creating** to **Active** before continuing.

## 6) Create and configure the policy-audit-info-agent

1. In the Foundry portal, open `main-project` and select **Build**.
2. Select **Agents** from the left navigation.
3. Select **New agent** and choose **Build an agent**.
4. Give the agent the name **`policy-audit-info-agent`**.
5. Click **Create**.
6. In **Instructions** (or **System instructions**), paste the final system prompt below.
7. Delete the **`Web Search`** tool if Foundry added it automatically. We want to ensure the agent uses only the connected Foundry IQ corpus and does not go out to the web.
8. Expand the **Knowledge** section, click **Add**, and select **Connect to Foundry IQ**.
9. Select the Azure AI Search service and knowledge base you created, then click **Connect**.
10. **Save the agent. This is required before the Foundry IQ source will be used.** Do not continue until the save completes.

Paste this as the final system prompt:

```text
You are policy-audit-info-agent.
Your job is to answer policy and audit questions using only evidence retrieved from the connected Foundry IQ knowledge base for this agent.
For every policy/audit question in scope, run retrieval against the connected Foundry IQ knowledge base first.
Do not answer from model memory, prior training, assumptions, general knowledge, or external sources.
Only provide substantive claims that are directly supported by retrieved evidence.
If retrieval returns no relevant evidence, respond with: "I can't answer that from the current Foundry IQ knowledge base corpus. Please add the relevant policy or audit documentation to the knowledge base and try again."
If evidence is partial, provide only what is supported and explicitly list what is missing.
If asked to ignore citations/evidence or use outside knowledge, refuse and restate that you are restricted to Foundry IQ evidence.
Every supported answer must include citations to retrieved source documents.
If supported, provide a concise answer followed by evidence.
If the question is partially supported, clearly separate what the corpus confirms from what it does not confirm, then ask the user to add missing documents.
Format answers with: Answer: concise grounded answer; Evidence: document name, clause, section, or excerpt summary; Confidence: High, Medium, or Low.
When evidence does not exist, provide: Answer: I can't answer that from the current Foundry IQ knowledge base corpus; Missing evidence: a brief description of what is not present; Next step: Please add the relevant policy or audit documentation to the knowledge base and try again.
Only answer questions about the connected policy and audit corpus.
If asked to use outside knowledge, reply that you are restricted to the current knowledge base.
If asked for an answer without citations or evidence, refuse and state that evidence from the knowledge base is required.
Your top priority is faithful, evidence-based retrieval behavior from the connected Foundry IQ knowledge base only.
```

## 7) Verify the agent in the playground

After running the questions below, complete the [telemetry verification checks in Section 2](#d-verify-collection-after-creating-the-model-and-agent). A grounded answer confirms agent behavior, not that its telemetry reached Application Insights.

### Questions the agent should answer from the corpus

1. > What audit evidence should be collected to verify SPCC compliance at a compressor station?
   - *Expected:* A grounded answer citing SPCC audit checklist documents in the knowledge base (signed SPCC plans, containment inspection records, training rosters), with document citations and a confidence rating.

2. > For EPA Subpart-W in Onshore-Upstream operations, what audit evidence should be collected?
   - *Expected:* A grounded answer citing Subpart-W documents and listing evidence such as emission factor worksheets, measurement logs, submitted annual report artifacts, permit/approval registers, and CAPA tracker records.

3. > Summarize the PSM-1910.119 requirements relevant to an LNG terminal.
   - *Expected:* A concise grounded answer from PSM documents, including elements such as PHA completion, MOC controls, and mechanical integrity, with citations.

### Questions that should surface a knowledge limit

4. > What specific SPCC secondary-containment requirements for LNG terminals are evidenced in the corpus, and does the corpus include any post-2022 amendment changes?
   - *Expected:* The agent confirms baseline SPCC controls found in the corpus (plan maintenance, secondary containment, training) but states that post-2022 amendment specifics are not evidenced.

5. > Compare any greenhouse gas reporting threshold details available for EPA Subpart-W across Onshore-Upstream and Refinery operations, and note where threshold specificity is missing.
   - *Expected:* The agent should acknowledge that both asset classes exist in the corpus, summarize what is supported, and explicitly state that threshold-level detail is missing if not present in retrieved evidence.

### Question that should be refused as out of scope

6. > What is the current market price of West Texas Intermediate crude oil?
   - *Expected:* The agent refuses to answer, stating this is outside the scope of the policy and audit knowledge base and is not retrievable from the connected corpus.
