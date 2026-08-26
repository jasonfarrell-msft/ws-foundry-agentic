# Part 1 — Microsoft Foundry Foundation Setup

[Final Architecture Diagram](./final-architecture.svg)

### What you will do
In this part, you will establish the workshop foundation by creating the resource group and a shared Application Insights instance for end-to-end telemetry, provisioning Foundry and core services, loading the shared corpus, configuring Foundry IQ, and creating the policy-audit-info-agent for grounded policy and audit responses. Color alignment: Purple.

## 1) Create the resource group and Application Insights

Application Insights is created first so that every component you deploy or configure in Parts 1–4 can be wired into a single telemetry destination. This gives you unified tracing across Foundry, agents, the audit API, and the MCP server.

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

> **Keep this connection string handy.** You will attach it to Foundry in Section 2 and to the Container Apps components deployed in Part 2. Treat it as a secret: do not commit it to source control. In production, source it from Azure Key Vault or app configuration rather than pasting it inline.

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

Wire the Foundry project to the Application Insights instance created in Section 1 so agent runs, traces, and tool calls are captured centrally.

1. In the Foundry portal, open **`main-project`**.
2. Open the **Observability** (or **Tracing**) area from the left navigation.
3. Select the option to connect Application Insights.
4. Choose the existing resource **`appi-agentapp-<initials>-mx01`** in `rg-agent-ws-mx01`.
5. Save the connection and confirm the project shows Application Insights as connected.

> If your Foundry portal exposes this as a project **Connection**, add a new connection of type **Application Insights** and select the same resource. Every agent you build in Parts 1–4 inherits this project-level telemetry connection.

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
