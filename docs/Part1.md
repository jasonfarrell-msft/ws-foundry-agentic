# Part 1 — Microsoft Foundry Foundation Setup

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

## 3) Prepare your data

> Before creating the agent, you will provide the shared policy-and-audit corpus it will use for grounding. The storage account and uploaded documents give Foundry IQ a common evidence source for retrieval and reasoning in the later OGE audit and multi-agent exercises.

### Create Storage Account
In this section, you will create an Azure Storage account that will hold the workshop document corpus later in this part and in later parts.

1. Sign in to the [Azure portal](https://portal.azure.com).
2. Search for **Storage accounts** and select **+ Create**.
3. On the **Basics** tab, set:
    - **Subscription:** Your workshop subscription
    - **Resource group:** `rg-agent-test-mx01` (or the same resource group used for Foundry)
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

This script creates the `docs` container if needed and uploads all files from `data/docs`, overwriting blobs with the same name. No `az login` is required.

> **Security note:** Microsoft does not recommend using connection strings for Azure Storage connectivity. Connection strings contain shared keys that grant full access to the storage account and should never be committed to source control or shared. They are used here for workshop simplicity only and are not a production-grade practice. In production, use Managed Identity or Azure AD-based authentication instead.

## 4) Configure Foundry IQ

**Foundry IQ** is Microsoft Foundry's knowledge-grounding capability. It connects your agent to enterprise content so answers are grounded in your data with citations.

Your workshop corpus is already in Azure Blob Storage in the `docs` container. In this section, create an **Azure AI Search** service and a knowledge base from that source. The knowledge base must be active before you build the agent.

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

### Configure Azure AI Search identity access

Foundry IQ uses the Azure AI Search system-assigned managed identity for two separate operations: calling the embedding or chat model hosted by Foundry, and reading the documents from Azure Blob Storage. Assign both roles before creating the knowledge base.

> **Warning:** You must have permission to assign Azure roles on the Foundry resource and storage account. If you cannot assign roles, ask a subscription or resource owner to perform these steps.

#### Enable the Search managed identity

1. Open the Azure AI Search service **`srch-agentws-<initials>-lx01`**.
2. In the left navigation, select **Settings** → **Identity**.
3. On the **System assigned** tab, set **Status** to **On**, select **Save**, and record the displayed object ID.

#### Assign Cognitive Services User on the Foundry resource

1. Open the Foundry resource that contains the workshop project, not the project child resource.
2. Select **Access control (IAM)**.
3. Select **Add** → **Add role assignment**.
4. Select the **Cognitive Services User** role.
5. For the member, choose **Managed identity**, select the Azure AI Search service, and select **Review + assign**.

This allows Azure AI Search to call the embedding and chat model deployments used by the knowledge base.

#### Assign Storage Blob Data Reader on the `docs` container

1. Open the storage account created in Section 3.
2. Open **Containers**, select the **`docs`** container, and select **Access control (IAM)**.
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
    - **Retrieval reasoning effort:** `low`
    - **Retrieval instructions:** `Use only the connected corpus. Prioritize the most relevant policy/audit documents and sections that directly answer the question, preferring authoritative evidence with clear citation metadata. Do not use external sources.`
    - **Output mode:** `Answer synthesis`
    - **Answer instructions:** `Answer using only retrieved evidence. Be concise, cite sources, state confidence, and identify missing evidence.`
7. Select **Add knowledge source**, then choose **Azure Blob Storage**.
    - **Name:** `ks-azureblob-docs`
    - **Storage account:** Select the storage account you created in Section 3.
    - **Container name:** `docs`
    - **Content extraction mode:** `Standard`
12. Select an existing `text-embedding-3-small` deployment for **Embedding model**. If none exists, deploy the `text-embedding-3-small` model using the available deployment name, then select it.
13. Confirm **Chat completions model** is set to a compatible chat-model deployment in your project, such as a GPT-5.x deployment. If you already have a compatible deployment with a different name, select it; if none exists, deploy a supported chat model and then select it.
14. Click **Create**.
15. After completing the knowledge source wizard, you are returned to the knowledge base configuration page.
16. Select **Save knowledge base** to save your changes before continuing.
17. Refresh the knowledge base details page and confirm the **Knowledge source** status changes from **Creating** to **Active** before continuing.

## 5) Create and configure the policy-audit-info-agent

The data and Foundry IQ knowledge base are ready before you create the agent. Build the agent with the final system prompt below, attach the active knowledge base, and remove the default Web Search tool.

1. In the Foundry portal, open `main-project` and select **Build**.
2. Open **Knowledge** and confirm that `kb-policy-audit-documents` has **Status: Active**. If it is still processing, wait for ingestion and indexing to finish before continuing.
3. Select **Agents** from the left navigation.
4. Select **New agent** and choose **Build an agent**.
5. Give the agent the name **`policy-audit-info-agent`**.
6. Click **Create**.
7. In **Instructions** (or **System instructions**), paste the final system prompt below.
8. Delete the **`Web Search`** tool if Foundry added it automatically. We want to ensure the agent uses only the connected Foundry IQ corpus and does not go out to the web.
9. Expand the **Knowledge** section, click **Add**, and select **Connect to Foundry IQ**.
10. Select the Azure AI Search service and knowledge base you created, then click **Connect**.
11. **Save the agent. This is required before the Foundry IQ source will be used.** Do not continue until the save completes.

Paste this as the final system prompt:

> You are policy-audit-info-agent.
> Your job is to answer policy and audit questions using only evidence retrieved from the connected Foundry IQ knowledge base for this agent.
> For every policy/audit question in scope, run retrieval against the connected Foundry IQ knowledge base first.
> Do not answer from model memory, prior training, assumptions, general knowledge, or external sources.
> Only provide substantive claims that are directly supported by retrieved evidence.
> If retrieval returns no relevant evidence, respond with: "I can't answer that from the current Foundry IQ knowledge base corpus. Please add the relevant policy or audit documentation to the knowledge base and try again."
> If evidence is partial, provide only what is supported and explicitly list what is missing.
> If asked to ignore citations/evidence or use outside knowledge, refuse and restate that you are restricted to Foundry IQ evidence.
> Every supported answer must include citations to retrieved source documents.
> If supported, provide a concise answer followed by evidence.
> If the question is partially supported, clearly separate what the corpus confirms from what it does not confirm, then ask the user to add missing documents.
> Format answers with: Answer: concise grounded answer; Evidence: document name, clause, section, or excerpt summary; Confidence: High, Medium, or Low.
> When evidence does not exist, provide: Answer: I can't answer that from the current Foundry IQ knowledge base corpus; Missing evidence: a brief description of what is not present; Next step: Please add the relevant policy or audit documentation to the knowledge base and try again.
> Only answer questions about the connected policy and audit corpus.
> If asked to use outside knowledge, reply that you are restricted to the current knowledge base.
> If asked for an answer without citations or evidence, refuse and state that evidence from the knowledge base is required.
> Your top priority is faithful, evidence-based retrieval behavior from the connected Foundry IQ knowledge base only.

## 6) Verify the agent in the playground

Open the agent playground and test the following questions. They are designed to exercise different agent behaviors — grounded answers, acknowledged limits, and out-of-scope refusals.

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

## 7) Assign Foundry Agent Consumer role for A2A access

> **Warning:** You must have permission to assign Azure roles on the `main-project` Foundry project to complete this section. If you cannot assign roles, ask a subscription or resource owner to perform these steps before Part 3.

This agent's identity will be used in Part 3 for A2A communication. The identity is created when the agent is created and may take a few minutes to become visible. Assign it the **Foundry Agent Consumer** role on `main-project` so it can call other agents through A2A in later parts.

1. Wait 2–3 minutes for the agent identity to propagate.
2. In the Azure portal, navigate to the Foundry project resource (`main-project`).
3. In the left navigation, select **Access Control (IAM)**.
4. Select **+ Add** → **Add role assignment**.
5. On the **Role** tab, search for and select **Foundry Agent Consumer**.
6. On the **Members** tab, select **Assign access to** → **Managed identity** → **+ Select members**.
7. In the subscription dropdown, select your workshop subscription.
8. In the managed-identity picker, search for `policy-audit-info-agent` and select it.
9. Select **Select**, then **Review + assign**.

This assignment allows `policy-audit-info-agent` to call other Foundry agents through A2A connections in Part 3.
