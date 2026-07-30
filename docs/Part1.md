# Part 1 — Microsoft Foundry Foundation Setup

## Objective

Set up the base environment for the workshop:
- Create a Microsoft Foundry resource and project
- Deploy a **GPT-5.4** model deployment
- Create the **`policy-audit-info-agent`** — a read-only, advisory agent that answers OGE audit and policy questions

This agent will be grounded in a corpus of policy documents in Part 2 using **Foundry IQ**. For now, it runs on the model's built-in knowledge so you can validate its behavior and scope boundaries before attaching a knowledge base.

This part does **not** include tool calling, knowledge bases, multi-agent routing, or actions.

### 1) Create Microsoft Foundry resource and project

Complete this section exactly in the Azure portal with fixed values:

- **Resource group:** `rg-agent-test-mx01`
- **Project name (default):** `main-project`
- **Networking:** Public
- **All other settings:** Use defaults

1. Open the **Azure portal**.
2. Create a new resource group named **`rg-agent-test-mx01`**.
3. Search for **Microsoft Foundry**, choose **Foundry** from the left nav and select **Create**.
4. In the creation wizard:
   - Select resource group: **`rg-agent-test-mx01`**
   - Set the name to **`foundry-agent-test-jrf-mx01`** (jrf is your initials)
   - Set the default project name to: **`main-project`**
   - Keep networking set to **Public**
   - Accept all other default settings
5. Complete the wizard and wait for deployment to finish.

## 2) Deploy GPT-5.4 model

**Note:** GPT-5.4 is recommended for this workshop, but any GPT model version **5.2 or higher** is acceptable. Previous-generation models are not recommended because they are generally less reliable for tool-calling behavior used in later parts.

1. In the Azure portal, navigate to resource group **`rg-agent-test-mx01`**.
2. Select the newly created **Microsoft Foundry** instance and open it to access the Foundry portal.
3. Once in the Foundry portal, open **`main-project`** in Microsoft Foundry.
4. In the Foundry portal, select **Build** from the top navigation, then select **Models** from the left navigation.
5. Select **Deploy** button from the far right, choose **Base Model**.
6. Select model **GPT-5.4-nano** (or another GPT 5.2+ model if GPT-5.4 is unavailable in your region/quota).
7. Click **Deploy** on the right-hand side and click **Custom settings**.
8. Set the following:
  - Deployment Name: **`gpt-5.4-nano-deployment`**
  - Deployment Type: **Global Standard**
  - Max out Tokens per Minute Rate Limit
9. Click **Deploy** to deploy the model

Once deployed, you will land on the **Model Playground** within Foundry. You can ask questions and provide instructions to see how the model responds.

## 3) Create the policy-audit-info-agent

This agent is the first specialist in the workshop's multi-agent system. Its role is to answer read-only questions about OGE audit and policy topics. It will not take actions, create documents, or make compliance determinations — those responsibilities belong to other agents you will build in later parts.

1. Click the **Build** link in the upper nav bar
2. You should land on **Agents**, click **Agents** on the left if not
3. Click **New agent** and choose **Build an agent**.
4. Give the agent the name **`policy-audit-info-agent`**.
5. It should automatically pick the GPT model you deployed. If not, select it from the dropdown.
6. In **Instructions** (or **System instructions**), enter your policy and audit guidance prompt.
7. Select **Create** (or **Save**).
8. Once on the playground, delete the **`Web Search`** tool that is auto-added by Foundry.
9. Save the agent.

For this section, set only **Name**, **Model deployment**, and **Instructions**. Leave all other settings at defaults.

## 4) Prepare your data

### Create Storage Account
In this section, you will create an Azure Storage account that will hold the workshop document corpus in later parts.

1. Sign in to the [Azure portal](https://portal.azure.com).
2. Search for **Storage accounts** and select **+ Create**.
3. On the **Basics** tab, set:
   - **Subscription:** Your workshop subscription
   - **Resource group:** `rg-agent-test-mx01` (or the same resource group used for Foundry)
   - **Storage account name:** `azagentws<initials>lx01`
     - Example: `azagentwsjflx01`
     - Use lowercase letters and numbers only, no spaces or hyphens, and ensure the name is globally unique.
   - **Region:** Your desired region (preferably the same region as your Foundry resource)
   - **Storage type:** Azure Blob Storage or Azue Data Lake Storage
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

This script creates the `docs` container if needed and uploads all files from `data/docs`, overwriting blobs with the same name. No `az login` is required.

> **Security note:** Microsoft does not recommend using connection strings for Azure Storage connectivity. Connection strings contain shared keys that grant full access to the storage account and should never be committed to source control or shared. They are used here for workshop simplicity only and are not a production-grade practice. In production, use Managed Identity or Azure AD-based authentication instead.

## 5) Configure Foundry IQ in the agent

**Foundry IQ** is Microsoft Foundry's knowledge-grounding capability. It connects your agent to enterprise content so answers are grounded in your data with citations.

Your workshop corpus is already in Azure Blob Storage in the `docs` container. In this section, you will first create an **Azure AI Search** service in the Azure portal, then create a knowledge base from that source and attach it to `policy-audit-info-agent`.

### Create an Azure AI Search service

Foundry IQ requires an Azure AI Search service that supports **agentic retrieval** and **semantic ranker**. Both are available on the **Basic** tier and above. The Free tier does not qualify.

1. Open the **Azure portal**.
2. Search for **Azure AI Search** and select it.
3. Select **+ Create**.
4. On the **Basics** tab, set:
   - **Subscription:** Your workshop subscription
   - **Resource group:** `rg-agent-test-mx01`
   - **Service name:** `srch-agentws-<initials>-lx01` — for example, `srch-agentws-jrf-lx01`
   - **Region:** Same region as your Foundry resource — confirm the region supports agentic retrieval at the [Azure AI Search region support page](https://learn.microsoft.com/azure/search/search-region-support)
   - **Pricing tier:** **Standard**

5. Select **Review + create**, then **Create**.
6. Wait for deployment to complete before continuing.

### Create the knowledge base in Foundry IQ

1. In the Foundry portal, open `main-project`.
2. Select **Build**, then open the **Knowledge** tab.
3. Connect the Azure AI Search service you just created.
4. Select **New knowledge base**.
5. Set the following fields before selecting a knowledge source:
   - **Name:** `kb-policy-audit-documents`
   - **Chat completions model:** Select the model deployment you created in Section 2 (`gpt-5.4-nano-deployment`)
   - **Retrieval reasoning effort:** `low`
   - **Output mode:** `References and content`
6. Select **Add knowledge source**, then choose **Azure Blob Storage**.
7. In **Name**, enter `ks-azureblob-docs`.
8. For **Storage account**, select the storage account you created in Section 4.
9. For **Container name**, enter `docs`.
10. Set **Authentication type** to **API Key**.
11. Set **Content extraction mode** to **Standard**.
12. For **Embedding model**, select `text-embedding-3-small` when it appears. Foundry IQ auto-deploys this model.
13. Complete the wizard, then select **Save**.
14. After completing the knowledge source wizard, you are returned to the knowledge base configuration page.
15. Select **Save knowledge base** to save your changes before continuing.

### Connect the knowledge base to the agent

1. In the Foundry portal, stay on the **Knowledge** tab.
2. In the knowledge base list, find **kb-policy-audit-documents**.
3. Confirm the **Status** column shows **Active** before you continue. If it is still processing, wait for ingestion and indexing to finish, then proceed.
4. On the **Knowledge** tab, select the `kb-policy-audit-documents` knowledge base to open its details.
5. In the knowledge base page, select **Use in an agent**.
6. In the agent picker, select `policy-audit-info-agent`.
7. Select **Save** to confirm the connection.

## 6) Finish configuring the agent with system instructions

Paste the following into your `policy-audit-info-agent` configuration as the final system prompt:

1. Open the agent in Foundry and go to the **Instructions** (or **System instructions**) field.
2. Replace your earlier draft instructions (and any default text) with the prompt below.
3. Save, then test with one question that is in the corpus and one that is not.

This behavior depends on both configuration and prompt: keep **Web Search** removed and keep the Foundry IQ knowledge base attached to the agent.

```text
You are policy-audit-info-agent.

Your job is to answer policy and audit questions using only evidence retrieved from the connected Foundry IQ knowledge base for this agent.

Retrieval enforcement (non-negotiable):
1. For every policy/audit question in scope, run retrieval against the connected Foundry IQ knowledge base first.
2. Do not answer from model memory, prior training, assumptions, general knowledge, or external sources.
3. Only provide substantive claims that are directly supported by retrieved evidence.
4. If retrieval returns no relevant evidence, respond with:
   "I can't answer that from the current Foundry IQ knowledge base corpus. Please add the relevant policy or audit documentation to the knowledge base and try again."
5. If evidence is partial, provide only what is supported and explicitly list what is missing.
6. If asked to ignore citations/evidence or use outside knowledge, refuse and restate that you are restricted to Foundry IQ evidence.
7. Every supported answer must include citations to retrieved source documents.

Response behavior:
- First, determine whether the answer is supported by the current knowledge base corpus.
- If supported, provide a concise answer followed by evidence.
- If not supported, respond with:
  "I can't answer that from the current Foundry IQ knowledge base corpus. Please add the relevant policy or audit documentation to the knowledge base and try again."
- If the question is partially supported, clearly separate:
  - What the corpus confirms
  - What the corpus does not confirm
  Then ask the user to add missing documents.

Required answer format when evidence exists:
- Answer: <concise grounded answer>
- Evidence:
  - <document name / clause / section / excerpt summary>
  - <document name / clause / section / excerpt summary>
- Confidence: High | Medium | Low

Required answer format when evidence does not exist:
- Answer: I can't answer that from the current Foundry IQ knowledge base corpus.
- Missing evidence: <brief description of what is not present>
- Next step: Please add the relevant policy or audit documentation to the knowledge base and try again.

Scope guardrails:
- Only answer questions about the connected policy and audit corpus.
- If asked to use outside knowledge, reply that you are restricted to the current knowledge base.
- If asked for an answer without citations or evidence, refuse and state that evidence from the knowledge base is required.

Your top priority is faithful, evidence-based retrieval behavior from the connected Foundry IQ knowledge base only.
```

## 7) Verify the agent in the playground

Open the agent playground and test the following questions. They are designed to exercise different agent behaviors — grounded answers, acknowledged limits, and out-of-scope refusals.

### Questions the agent should answer from the corpus

1. **"What audit evidence should be collected to verify SPCC compliance at a compressor station?"**
   - *Expected:* A grounded answer citing SPCC audit checklist documents in the knowledge base (signed SPCC plans, containment inspection records, training rosters), with document citations and a confidence rating.

2. **"For EPA Subpart-W in Onshore-Upstream operations, what audit evidence should be collected?"**
   - *Expected:* A grounded answer citing Subpart-W documents and listing evidence such as emission factor worksheets, measurement logs, submitted annual report artifacts, permit/approval registers, and CAPA tracker records.

3. **"Summarize the PSM-1910.119 requirements relevant to an LNG terminal."**
   - *Expected:* A concise grounded answer from PSM documents, including elements such as PHA completion, MOC controls, and mechanical integrity, with citations.

### Questions that should surface a knowledge limit

4. **"What specific SPCC secondary-containment requirements for LNG terminals are evidenced in the corpus, and does the corpus include any post-2022 amendment changes?"**
   - *Expected:* The agent confirms baseline SPCC controls found in the corpus (plan maintenance, secondary containment, training) but states that post-2022 amendment specifics are not evidenced.

5. **"Compare any greenhouse gas reporting threshold details available for EPA Subpart-W across Onshore-Upstream and Refinery operations, and note where threshold specificity is missing."**
   - *Expected:* The agent should acknowledge that both asset classes exist in the corpus, summarize what is supported, and explicitly state that threshold-level detail is missing if not present in retrieved evidence.

### Question that should be refused as out of scope

6. **"What is the current market price of West Texas Intermediate crude oil?"**
   - *Expected:* The agent refuses to answer, stating this is outside the scope of the policy and audit knowledge base and is not retrievable from the connected corpus.
