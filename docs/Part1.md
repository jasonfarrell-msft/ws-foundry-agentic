# Part 1 — Microsoft Foundry Foundation Setup

## Objective

Set up the base environment for the workshop:
- Create a Microsoft Foundry resource
- Create a project named **`main-project`**
- Deploy a **GPT-5.4** model deployment
- Create an initial **Orchestrator** agent that is **Q&A only** (non-agentic)

This part does **not** include tool calling, multi-agent routing, or actions.

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
  - If quota presents as a problem, try other versions of GPT here
7. Click **Deploy** on the right-hand side and click **Custom settings**.
8. Set the following:
  - Deployment Name: **`gpt-5.4-deployment`**
  - Deployment Type: **Global Standard**
  - Tokens per Minute Rate Limit: **3333000**
9. Click **Deploy** to deploy the model

Once deployed, you will land on the **Model Playground** within Foundry. You can ask questions and provide instructions to see how the model responds.

## 3) Create initial orchestration agent (non-agentic)

1. Click the **Build** link in the upper nav bar
2. You should land on **Agents**, click **Agents** on the left if not
2. Click **New agent** and choose **Build an agent**.
3. Give the agent a name like **`orchestrator-agent`**.
4. It should automatically pick the GPT model you deployed. If not, select it from drop down.
5. In **Instructions** (or **System instructions**), paste the prompt below.
6. Select **Create** (or **Save**).
7. Confirm the agent appears in the Agents list.

For this section, set only **Name**, **Model deployment**, and **Instructions**. Leave all other settings at defaults.

### System instruction (copy/paste)

You are an OGE (Oversight, Governance, and Efficiency) policy assistant.

Scope:
- Answer questions about OGE auditability only.
- Keep responses concise and factual.
- Cite relevant policy sections or clause IDs when available.

Auditability:
- Keep reasoning clear and brief.
- If policy evidence is missing or ambiguous, state that explicitly.
- Do not invent policy text, clause IDs, or compliance decisions.

Refusal behavior:
- Refuse requests outside OGE auditability scope.
- Refuse requests to bypass policy, hide evidence, or produce deceptive compliance output.
- When refusing, explain briefly and suggest a compliant next step.

## 4) Quick validation prompts

1. In-scope:  
   `What controls improve auditability for policy exception handling?`
2. Out-of-scope:  
   `Create a remediation ticket for control ownership gaps.`
3. Boundary check:  
   `How should we document approvals to improve OGE audit trails?`

Expected behavior: the agent answers OGE auditability questions only, and refuses action-taking requests.
