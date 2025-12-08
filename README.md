# Open Pharma Demo – Brazil Agentic APIs Experience Platform

End-to-end demo of a **tier-1-grade digital stack for a Brazilian pharma distributor + retail chain**, built around three main layers:

- **WSO2 Micro Integrator (MI) 4.5**  
  Mediation, orchestration, async queues & message stores, circuit breaking, centralized logging.

- **Pharma BI Agents (Ballerina)**  
  Multiple **LLM-powered agents** consuming MI APIs via typed tools and standardized envelopes, with **agentic orchestration patterns** (router, fan-out, overlay).

- **Node.js backend** (`pharma-backend-js`)  
  Mock “core systems” for:
  - Patient CRM (CPF-based), chronic conditions, prescriptions,
  - Store inventory (drogarias) and DC stock (centro de distribuição),
  - Prescription orders and shipments,
  - Compliance audit events (high-risk / cold-chain),
  - Tax reports (NFe-ish abstractions, ICMS),
  - Processor events and technical alerts.

> **Language policy**
>
> - All *code comments* and *prompts* are in **English** for auditability.  
> - All *agent responses* to end users are in **Brazilian Portuguese**.

---

## 1. Business & Technical Storyline

### 1.1 Business perspective

For a given **patient** and **store**, we demonstrate:

#### Patient 360

- Basic CRM: name, chronic conditions, preferred store.
- Active prescriptions and refillability.
- Whether a medication is refill-eligible and appears available at a specific store.

#### Store & DC inventory

- SKU-level inventory for a store (`MED-INSULINA`, `MED-ANTIBIOTICO`).
- `coldChain` flag for insulin.
- Replenishment flows towards the DC (async via queues).

#### Orders & shipments

- Prescription order creation (sync and async).
- Shipment dispatch from DC → store.
- Order & shipment lifecycle (mocked time-based transitions):
  - `PENDING_FULFILLMENT → COMPLETED`,
  - `IN_TRANSIT → DELIVERED`.

#### Compliance & Tax

- Recording compliance audit events (e.g., dispensing insulin to a diabetic).
- Asynchronous tax report submission via MI message stores.
- **Clear boundary**: the AI agents **do not** give medical, legal, or fiscal advice.

---

### 1.2 Technical perspective (layers)

#### Layer 1 – Node.js Backend (`pharma-backend-js`)

**File:** `pharma-backend-js/index.js`

- **Patient CRM**

  - `GET /patients/profile/:patientId`  
    In-memory `patientsDb` with demo patients:
    - `PAT-BR-001` – Ana Silva (Type 1 diabetes, insulin RX),
    - `PAT-BR-002` – Carlos Souza (antibiotic RX).

- **Store inventory**

  - `GET /stores/:storeId/inventory`
  - `GET /stores/:storeId/inventory?sku=MED-INSULINA`  
    In-memory `storeInventory` with:
    - `quantityOnHand`, `reorderPoint`, `coldChain`.

- **Orders**

  - `POST /orders/prescriptions`  
    Creates order in `ordersStore` with:
    - `status: "PENDING_FULFILLMENT"`,
    - `slaHours`, timestamps, `coldChain` flag.
  - `GET /orders/:id`  
    Time-based progression `PENDING_FULFILLMENT → COMPLETED`.

- **Shipments**

  - `POST /shipments/dispatch`  
    Creates shipment in `shipmentsStore` (linked to order + DC).
  - `GET /shipments/:id`  
    Time-based progression `IN_TRANSIT → DELIVERED`.

- **Compliance & tax**

  - `POST /compliance/audit`, `GET /compliance/audit` → `complianceEvents`.
  - `POST /finance/tax-report`, `GET /finance/tax-report` → `taxReports`.

- **Integration telemetry**

  - `POST /ops/processor-events`, `GET /ops/processor-events` → `processorEvents`.  
    Events from MI message processors (forward success/deactivation).
  - `POST /tech/alerts` → logs “tech alerts” from MI.

Backend is intentionally **simple and deterministic**: no AI, no retries, no circuit breaking – those concerns live in MI + Agentic layers.

---

#### Layer 2 – WSO2 Micro Integrator 4.5 (`pharma-mi`)

MI is the **canonical integration plane**:

- Normalizes REST interfaces.
- Applies circuit breaking, retries, and async queueing.
- Enforces a consistent logging & correlation model.

APIs use **versioning**:

```xml
version="1.0.0"
version-type="context"
````

So URLs are:

* `/customers/1.0.0/...`
* `/inventory/1.0.0/...`
* `/orders/1.0.0/...`
* `/shipments/1.0.0/...`
* `/compliance/1.0.0/...`
* `/finance/1.0.0/...`

##### 2.2.1 REST APIs (Synapse configs)

**Artifacts directory:** `pharma-mi/src/main/wso2mi/artifacts/apis`

* **`PharmaCustomerAPI.xml`** – context `/customers`

  * `GET /customers/1.0.0/patient/{patientId}`
    → `CustomerProfileEP` → `GET http://pharma-backend:8080/patients/profile/{patientId}`

* **`PharmaInventoryAPI.xml`** – context `/inventory`

  * `GET /inventory/1.0.0/stores/{storeId}/items/{sku}`
    → `StoreInventoryEP` (`http uri-template` to backend).
  * `POST /inventory/1.0.0/replenishment/async`
    → `ReplenishmentStore` + `ReplenishmentProcessor`
    → transforms payload into a **prescription order** and forwards to backend via processor.

* **`PharmaOrdersAPI.xml`** – context `/orders`

  * `POST /orders/1.0.0/prescriptions/sync`
    → `PrescriptionOrderEP` (sync).
  * `POST /orders/1.0.0/prescriptions/async`
    → `RxOrderStore` + `RxOrderProcessor`.
  * `GET /orders/1.0.0/*`
    → rebuilds backend URL `/orders/{id}`
    → `OrdersStatusEP`.

* **`PharmaShipmentsAPI.xml`** – context `/shipments`

  * `GET /shipments/1.0.0/*`
    → rebuilds backend URL `/shipments/{id}`
    → `ShipmentsStatusEP`.

* **`PharmaComplianceAPI.xml`** – context `/compliance`

  * `POST /compliance/1.0.0/audit`
    → `ComplianceAuditEP`.

* **`PharmaFinanceAPI.xml`** – context `/finance`

  * `POST /finance/1.0.0/tax-report/async`
    → `TaxReportStore` + `TaxReportProcessor`.

##### 2.2.2 Shared sequences

**Artifacts directory:** `pharma-mi/src/main/wso2mi/artifacts/sequences`

* **`CommonInSeq.xml`**

  * Derives `CorrelationId` from `axis2:MessageID`.
  * Captures `IN_TIMESTAMP` (`SYSTEM_TIME`).
  * Propagates `X-Correlation-Id` on transport.
  * Logs `IN` with:

    * `api.name`, `resource` (`REST_URL_POSTFIX`),
    * `HTTP_METHOD`, `REMOTE_ADDR`,
    * `CorrelationId`.

* **`CommonOutSeq.xml`**

  * Captures `OUT_TIMESTAMP`.
  * Uses a small JavaScript block to compute `LATENCY_MS = OUT_TIMESTAMP - IN_TIMESTAMP`.
  * Logs `OUT` with:

    * `api.name`, `resource`,
    * `http.status` (`axis2:HTTP_SC`),
    * `CorrelationId`, `latency.ms`.

* **`CommonFaultSeq.xml`**

  * Default `HTTP_SC = 500`.
  * If `ERROR_CODE` is `101503` / `101504` / `101505` → set `HTTP_SC = 502` (gateway).
  * Logs `FAULT` with:

    * `API_NAME`, `REST_URL_POSTFIX`,
    * `CorrelationId`, `ERROR_CODE`, `ERROR_MESSAGE`.
  * Returns JSON fault envelope:

    ```json
    {
      "message": "Erro na camada de integração farma (Brasil)",
      "correlationId": "...",
      "errorCode": "101503",
      "errorMessage": "..."
    }
    ```

* **`AsyncAckSeq.xml`**

  * Builds a standardized **202 QUEUED** JSON:

    ```json
    {
      "status": "QUEUED",
      "operation": "PRESCRIPTION_ORDER",
      "correlationId": "...",
      "queue": "RxOrderStore",
      "processor": "RxOrderProcessor",
      "timestamp": "..."
    }
    ```

  * Sets `axis2:HTTP_SC = 202`.

  * Runs `CommonOutSeq` and replies.

* **Processor sequences:**

  * **`ProcessorAsyncReplySeq.xml`**
    Emits `"MESSAGE_FORWARDED"` events to backend `/ops/processor-events`.

  * **`ProcessorAsyncDeactivateSeq.xml`**
    Emits `"DEACTIVATED"` events to backend `/ops/processor-events` and can also be used to trigger `/tech/alerts` if desired.

These sequences demonstrate **centralized logging, correlation, and fault normalization**.

##### 2.2.3 Message stores & processors

**Artifacts directories:**

* Stores: `pharma-mi/src/main/wso2mi/artifacts/message-stores`
* Processors: `pharma-mi/src/main/wso2mi/artifacts/message-processors`

Stores (in-memory for demo):

* `ReplenishmentStore.xml`
* `RxOrderStore.xml`
* `TaxReportStore.xml`

Processors (Scheduled Forwarding):

* `ReplenishmentProcessor.xml` → target `PrescriptionOrderEP`
* `RxOrderProcessor.xml` → target `PrescriptionOrderEP`
* `TaxReportProcessor.xml` → target `TaxReportEP`

Each processor config:

* `interval` (ms),
* `is.active=true`,
* `concurrency=1`,
* `non.retry.status.codes=200,201,202`,
* `max.delivery.attempts`,
* `max.delivery.drop=Enabled`,
* `message.processor.reply.sequence=ProcessorAsyncReplySeq`,
* `message.processor.deactivate.sequence=ProcessorAsyncDeactivateSeq`.

This pattern gives you **reliable async execution** plus a **DLQ-style drop semantics** on repeated failure.

##### 2.2.4 Endpoints (circuit breaking + retries)

**Artifacts directory:** `pharma-mi/src/main/wso2mi/artifacts/endpoints`

Endpoints like:

* `CustomerProfileEP.xml`
* `StoreInventoryEP.xml`
* `OrdersStatusEP.xml`
* `ShipmentsStatusEP.xml`
* `PrescriptionOrderEP.xml`
* `TaxReportEP.xml`
* `ComplianceAuditEP.xml`
* `ProcessorOpsEP.xml`
* `TechAlertsEP.xml`

Showcase:

* Timeouts:

  ```xml
  <timeout>
      <duration>30000</duration>
      <responseAction>fault</responseAction>
  </timeout>
  ```

* Retry behavior:

  ```xml
  <retryConfig>
      <count>2</count>
      <delay>1000</delay>
  </retryConfig>
  ```

* Circuit breaking:

  ```xml
  <markForSuspension>
      <errorCodes>101503,101504,101505</errorCodes>
      <retriesBeforeSuspension>3</retriesBeforeSuspension>
  </markForSuspension>
  <suspendOnFailure>
      <errorCodes>101503,101504,101505</errorCodes>
      <initialDuration>5000</initialDuration>
      <progressionFactor>1.5</progressionFactor>
      <maximumDuration>120000</maximumDuration>
  </suspendOnFailure>
  ```

**Key point**: circuit breaking + retries live here, **not** in the AI layer.

---

#### Layer 3 – Pharma BI Agents (Ballerina, `pharma_agent`)

**Key files:**

* `config.bal` – configuration (OpenAI, backend URL, retry config).
* `types.bal` – shared domain types (`AgentRequest`, `AgentResponse`, tool inputs).
* `functions.bal` – helpers:

  * Correlation ID generators,
  * Safe truncation & masking (PII),
  * Keyword-based domain detection,
  * Transient LLM error detection.
* `tools.bal` – **LLM tools** (MI façade).
* `agents.bal` – **agent definitions** (system prompts, tools, memory).
* `main.bal` – HTTP service (`/v1`), single-agent endpoints, omni orchestration.

##### 3.1 Tool layer – MI façade with envelopes

**File:** `pharma_agent/tools.bal`

Each tool:

* Is declared with `@ai:AgentTool` so it appears in the LLM tool catalog.
* Uses a shared `http:Client backendClient` pointing at MI (`BACKEND_BASE_URL`, e.g. `http://wso2mi:8290`).
* Sends `X-Correlation-Id` and `x-fapi-interaction-id` headers.
* Wraps MI responses in a **standard envelope**:

  ```json
  {
    "tool": "GetPatientProfileTool",
    "status": "SUCCESS" | "ERROR",
    "errorCode": "BACKEND_UNAVAILABLE" | "BACKEND_HTTP_ERROR" | "BACKEND_CLIENT_ERROR",
    "httpStatus": 200,
    "safeToRetry": false,
    "message": "",
    "result": { /* MI JSON payload */ },
    "correlationId": "corr-GetPatientProfile-..."
  }
  ```

Tools implemented:

* `GetPatientProfileTool` → `GET /customers/1.0.0/patient/{patientId}`
* `GetStoreInventoryTool` → `GET /inventory/1.0.0/stores/{storeId}/items/{sku}`
* `GetOrderStatusTool` → `GET /orders/1.0.0/{orderId}`
* `GetShipmentStatusTool` → `GET /shipments/1.0.0/{shipmentId}`
* `SubmitTaxReportTool` → `POST /finance/1.0.0/tax-report/async`

**Resilience at tool layer:**

* HTTP retry handled by **Ballerina client** via `retryConfig` (status codes `[500, 502, 503, 504]`).
* MI also has retries + circuit breaks, so you get **stacked reliability**.
* Errors normalized with `buildBackendErrorEnvelope` / `buildClientErrorEnvelope`.

##### 3.2 Specialized agents (single-agent pattern)

**File:** `pharma_agent/agents.bal`

Agents:

* `careAgent` (`PHARMA_CARE_SYSTEM_PROMPT`)

  * Tools: `GetPatientProfileTool`, `GetStoreInventoryTool`.
  * Focus:

    * Patient context & prescriptions (no medical advice),
    * Refillability from data,
    * Availability in given store.
  * Always answers in **Brazilian Portuguese**.

* `opsAgent` (`PHARMA_OPS_SYSTEM_PROMPT`)

  * Tools: `GetStoreInventoryTool`, `GetOrderStatusTool`, `GetShipmentStatusTool`.
  * Focus:

    * Store/DC operations, inventory, replenishment,
    * Order & shipment status.

* `complianceAgent` (`PHARMA_COMPLIANCE_SYSTEM_PROMPT`)

  * Tools: all read-only (patient, inventory, order, shipment).
  * Focus:

    * Compliance aspects (controlled drugs, cold chain, prescription validity),
    * No legal/clinical advice.

* `financeAgent` (`PHARMA_FINANCE_SYSTEM_PROMPT`)

  * Tools: `SubmitTaxReportTool`.
  * Focus:

    * Explaining tax report submissions,
    * No fiscal/legal advice.

* `omniAgent` (`PHARMA_OMNI_SYSTEM_PROMPT`)

  * **No tools** – purely synthesizes input from other agents.

* `complianceOverlayAgent` (`PHARMA_COMPLIANCE_OVERLAY_SYSTEM_PROMPT`)

  * **No tools** – post-processor for the omni answer.

Each agent uses:

* `ai:MessageWindowChatMemory(AGENT_MEMORY_SIZE)` to implement **sticky sessions** keyed by `sessionId`.

##### 3.3 HTTP service and orchestration

**File:** `pharma_agent/main.bal`

Service base path: `/v1`.

###### 3.3.1 Single-agent endpoints

* `POST /v1/care/chat`
* `POST /v1/ops/chat`
* `POST /v1/compliance/chat`
* `POST /v1/finance/chat`

Request payload:

```json
{
  "sessionId": "sess-123",
  "message": "Pergunta em português..."
}
```

Handler: `handleAgentRequestSimple`:

* Validates `sessionId` and `message`.
* Logs **IN** with `agentName`, `promptVersion`, `CorrelationId`.
* Calls `agent->run(message, sessionId = sessionId)`.

**LLM-level circuit breaker:**

* If result is `ai:Error` **and** `isTransientLLMError(err)` is true (checks substrings like `"rate limit"`, `"overloaded"`):

  * Logs warning,
  * Retries **once**.
* If still failing → `500` with error details.

Response payload:

```json
{
  "sessionId": "sess-123",
  "agentName": "PharmaBrazilCareAgent",
  "promptVersion": "pharma-care-v1.0.0",
  "message": "Resposta em português..."
}
```

###### 3.3.2 Omni orchestration endpoint

* `POST /v1/omni/chat`

Handler: `handleOmniRequest(req, correlationId)`.

Patterns implemented:

1. **Router pattern (domain detection)**
   **File:** `functions.bal` → `detectPharmaDomains(userMessage)`.

   * Normalizes message to lowercase.
   * Checks domain keyword arrays:

     * `CARE_KEYWORDS`, `OPS_KEYWORDS`, `COMPLIANCE_KEYWORDS`, `FINANCE_KEYWORDS`.
   * Returns `PharmaDomain[]` subset: `"CARE" | "OPS" | "COMPLIANCE" | "FINANCE"`.
   * If no match → defaults to `"CARE"`.

2. **Parallel fan-out**
   For each needed domain:

   ```ballerina
   if needsCare {
       careFuture = start careAgent->run(userMessage, sessionId = sessionId);
   }
   ...
   string|ai:Error careResult = wait careFuture;
   ```

   * Each result can be retried once on transient LLM error.
   * `materializeSubAgentAnswer(...)` converts `ai:Error` to a neutral Portuguese explanation, so omni always has something to read per domain.

3. **Synthesis via omni agent**

   * Builds a **structured text** (multi-section doc) matching `PHARMA_OMNI_SYSTEM_PROMPT`:

     ```text
     Pergunta original do usuário:

     {userMessage}

     === Resposta do agente de cuidado ao paciente (care) ===

     {careAnswer}

     === Resposta do agente de operações (ops) ===

     {opsAnswer}

     === Resposta do agente de compliance (compliance) ===

     {complianceAnswer}

     === Resposta do agente financeiro (finance) ===

     {financeAnswer}
     ```

   * Calls `omniAgent->run(omniInput, sessionId = sessionId)`.

   * On failure, falls back to a “combined raw view” multi-section text.

4. **Compliance overlay (post-processing pattern)**

   * `complianceOverlayAgent->run(synthesizedAnswer, sessionId = sessionId)`:

     * Removes legal/fiscal/medical **ad-hoc advice**.
     * Tones down over-promises (“garantimos que” → “a expectativa é que”).
     * Adds disclaimer:

       > "Aviso: esta resposta é apenas informativa e não substitui orientação médica, jurídica ou fiscal."

   * On failure → returns `synthesizedAnswer` without overlay.

This endpoint alone demonstrates a **complete agentic orchestration pipeline**:

> **Router → Fan-out → Aggregator/Synthesizer → Compliance Overlay**

---

## 2. Repository Structure

```text
.
├── README.md
├── docker-compose.yml
├── pharma-backend-js
│   ├── Dockerfile
│   ├── index.js
│   └── package.json
├── pharma-mi
│   ├── deployment
│   │   ├── deployment.toml
│   │   ├── docker
│   │   │   ├── Dockerfile
│   │   │   └── resources
│   │   │       ├── client-truststore.jks
│   │   │       └── wso2carbon.jks
│   │   └── libs
│   ├── mvnw
│   ├── mvnw.cmd
│   ├── pom.xml
│   └── src
│       ├── main
│       │   ├── java
│       │   └── wso2mi
│       │       ├── artifacts
│       │       │   ├── apis
│       │       │   ├── endpoints
│       │       │   ├── message-processors
│       │       │   ├── message-stores
│       │       │   ├── sequences
│       │       │   └── ...
│       │       └── resources
│       │           └── conf
│       └── test
└── pharma_agent
    ├── Ballerina.toml
    ├── Config.toml
    ├── agents.bal
    ├── automation.bal
    ├── config.bal
    ├── connections.bal
    ├── data_mappings.bal
    ├── functions.bal
    ├── main.bal
    ├── tools.bal
    └── types.bal
```

---

## 3. Running the Stack

### 3.1 Prerequisites

* Docker + Docker Compose.
* An OpenAI API key.

### 3.2 Environment variables

Set `OPENAI_API_KEY` in your shell:

```bash
export OPENAI_API_KEY="sk-..."   # your key
```

### 3.3 Docker Compose

**File:** `docker-compose.yml`

Key points:

* `pharma-backend` (Node.js, `8080:8080`)
* `wso2mi` (MI 4.5, `8290:8290`)

  * Built from `pharma-mi/deployment/docker/Dockerfile`.
  * Uses `BASE_IMAGE=wso2/wso2mi:4.5.0`.
  * Mounts artifacts (`artifacts/apis`, `.../endpoints`, `.../sequences`, `.../message-stores`, `.../message-processors`).
  * Mounts `deployment/deployment.toml` and keystores.
* `pharma-agent` (Ballerina, `8293:8293`)

  * Env:

    * `OPENAI_API_KEY=${OPENAI_API_KEY}`
    * `OPENAI_MODEL=GPT_4O`
    * `BACKEND_BASE_URL=http://wso2mi:8290`
    * `BACKEND_ACCESS_TOKEN=` (empty in demo)

Run:

```bash
docker-compose up --build
```

Check:

```bash
# Backend
curl -s http://localhost:8080/health | jq

# MI
curl -s http://localhost:8290/services | head -n 20 || true   # basic Synapse listing

# Agent layer
curl -s http://localhost:8293/v1/health | jq
```

---

## 4. Good Practices Demonstrated

* **Correlation IDs everywhere**

  * Generated in Ballerina and MI.
  * Propagated as `X-Correlation-Id` and `x-fapi-interaction-id`.
  * Visible in backend, MI, and agent logs.

* **Separation of concerns**

  * Backend: pure business rules and state.
  * MI: integration, resilience, async, fault normalization.
  * Agentic layer: natural language interface, tool orchestration, safety.

* **Safety (regulatory)**

  * Prompts explicitly forbid medical, legal, and fiscal advice.
  * Compliance overlay removes over-promises and adds disclaimers.
  * Tool envelopes force agents to handle `status != "SUCCESS"` correctly (no hallucinated data).

* **Resilience patterns**

  * MI endpoints: timeouts, retries, circuit breakers.
  * Message stores + processors: async execution and DLQ behavior.
  * Agent layer: one retry for transient LLM errors (rate limits, overloads).

* **Observability**

  * IN/OUT/FAULT logs at MI level with latency.
  * Processor events posted to backend `/ops/processor-events`.
  * Ballerina logs include agent name, prompt version, correlation ID.

* **Sticky sessions**

  * `sessionId` used consistently as LLM memory key.
  * Multi-turn conversations preserve context across tools and agents.

---

## 5. Curl Cookbook

> Adjust `localhost` vs container hostnames as needed if you run from inside containers.

### 5.1 Backend (Node.js) – direct tests

#### Health

```bash
curl -s http://localhost:8080/health | jq
```

#### Patient profiles

```bash
# Ana Silva (diabetes, insulin prescription)
curl -s http://localhost:8080/patients/profile/PAT-BR-001 | jq

# Carlos Souza (antibiotic prescription)
curl -s http://localhost:8080/patients/profile/PAT-BR-002 | jq
```

#### Store inventory

```bash
# Full inventory of LOJA-SP-001
curl -s "http://localhost:8080/stores/LOJA-SP-001/inventory" | jq

# Specific SKU in LOJA-SP-001
curl -s "http://localhost:8080/stores/LOJA-SP-001/inventory?sku=MED-INSULINA" | jq
```

#### Create prescription order (sync, direct backend)

```bash
curl -s -X POST http://localhost:8080/orders/prescriptions \
  -H "Content-Type: application/json" \
  -d '{
    "patientId": "PAT-BR-001",
    "storeId": "LOJA-SP-001",
    "sku": "MED-INSULINA",
    "quantity": 1,
    "channel": "STORE"
  }' | jq
```

Copy `orderId` from response, then:

```bash
ORDER_ID="ORD-LOJA-SP-001-MED-INSULINA-..."   # replace with actual
curl -s "http://localhost:8080/orders/$ORDER_ID" | jq
```

#### Shipments

```bash
# Dispatch shipment from DC-SP-01 for an order
curl -s -X POST http://localhost:8080/shipments/dispatch \
  -H "Content-Type: application/json" \
  -d "{
    \"orderId\": \"$ORDER_ID\",
    \"dcId\": \"CD-SP-01\"
  }" | jq
```

Copy `shipmentId`, then:

```bash
SHIPMENT_ID="SHP-..."          # replace with actual
curl -s "http://localhost:8080/shipments/$SHIPMENT_ID" | jq
```

#### Compliance events & tax reports

```bash
# Create a compliance audit event
curl -s -X POST http://localhost:8080/compliance/audit \
  -H "Content-Type: application/json" \
  -d '{
    "eventType": "DISPENSE_INSULIN",
    "patientId": "PAT-BR-001",
    "storeId": "LOJA-SP-001",
    "sku": "MED-INSULINA"
  }' | jq

# List last compliance events
curl -s http://localhost:8080/compliance/audit | jq

# Submit a tax report directly (sync)
curl -s -X POST http://localhost:8080/finance/tax-report \
  -H "Content-Type: application/json" \
  -d '{
    "storeId": "LOJA-SP-001",
    "amountBr": 1500.50
  }' | jq

# List last tax reports
curl -s http://localhost:8080/finance/tax-report | jq
```

#### Processor events & tech alerts

```bash
# See processor events pushed by MI
curl -s http://localhost:8080/ops/processor-events | jq

# Manual tech alert
curl -s -X POST http://localhost:8080/tech/alerts \
  -H "Content-Type: application/json" \
  -d '{"source": "manual-test", "message": "hello from curl"}' | jq
```

---

### 5.2 MI APIs – integration layer tests

Assuming MI is at `http://localhost:8290`:

```bash
BASE_MI=http://localhost:8290
```

#### 5.2.1 Customers (Patient 360 via MI)

```bash
curl -s "$BASE_MI/customers/1.0.0/patient/PAT-BR-001" | jq
curl -s "$BASE_MI/customers/1.0.0/patient/PAT-BR-002" | jq
```

#### 5.2.2 Inventory

```bash
curl -s "$BASE_MI/inventory/1.0.0/stores/LOJA-SP-001/items/MED-INSULINA" | jq
curl -s "$BASE_MI/inventory/1.0.0/stores/LOJA-RJ-001/items/MED-INSULINA" | jq
```

#### 5.2.3 Prescription orders – sync

```bash
curl -s -X POST "$BASE_MI/orders/1.0.0/prescriptions/sync" \
  -H "Content-Type: application/json" \
  -d '{
    "patientId": "PAT-BR-001",
    "storeId": "LOJA-SP-001",
    "sku": "MED-INSULINA",
    "quantity": 1,
    "channel": "STORE"
  }' | jq
```

Copy `orderId` and check status through MI:

```bash
ORDER_ID="ORD-..."    # from previous response
curl -s "$BASE_MI/orders/1.0.0/$ORDER_ID" | jq
```

#### 5.2.4 Prescription orders – async (message store)

```bash
curl -s -X POST "$BASE_MI/orders/1.0.0/prescriptions/async" \
  -H "Content-Type: application/json" \
  -d '{
    "patientId": "PAT-BR-001",
    "storeId": "LOJA-SP-001",
    "sku": "MED-INSULINA",
    "quantity": 1,
    "channel": "STORE"
  }' | jq
```

You should see a **QUEUED** ACK from `AsyncAckSeq`.

Then observe processor events on backend:

```bash
curl -s http://localhost:8080/ops/processor-events | jq
```

#### 5.2.5 Replenishment async

```bash
curl -s -X POST "$BASE_MI/inventory/1.0.0/replenishment/async" \
  -H "Content-Type: application/json" \
  -d '{
    "storeId": "LOJA-SP-001",
    "sku": "MED-INSULINA"
  }' | jq
```

After some seconds, check:

```bash
curl -s http://localhost:8080/ops/processor-events | jq
```

#### 5.2.6 Shipments via MI

Once you have a shipment in backend:

```bash
SHIPMENT_ID="SHP-..."  # from backend /shipments/dispatch
curl -s "$BASE_MI/shipments/1.0.0/$SHIPMENT_ID" | jq
```

#### 5.2.7 Compliance via MI

```bash
curl -s -X POST "$BASE_MI/compliance/1.0.0/audit" \
  -H "Content-Type: application/json" \
  -d '{
    "eventType": "DISPENSE_INSULIN",
    "patientId": "PAT-BR-001",
    "storeId": "LOJA-SP-001",
    "sku": "MED-INSULINA"
  }' | jq
```

#### 5.2.8 Finance – async tax report via MI

```bash
curl -s -X POST "$BASE_MI/finance/1.0.0/tax-report/async" \
  -H "Content-Type: application/json" \
  -d '{
    "storeId": "LOJA-SP-001",
    "amountBr": 2500.75
  }' | jq
```

#### 5.2.9 Correlation ID from client

```bash
curl -s "$BASE_MI/customers/1.0.0/patient/PAT-BR-001" \
  -H "X-Correlation-Id: demo-corr-123" | jq
```

Check MI logs and backend logs to see the same correlation ID flowing through.

---

### 5.3 Agentic APIs – Ballerina (LLM layer)

Assuming Ballerina service at `http://localhost:8293` and valid `OPENAI_API_KEY`.

Use a consistent `sessionId` per “user” to see memory in action.

#### 5.3.1 Care agent – patient question

```bash
curl -s -X POST http://localhost:8293/v1/care/chat \
  -H "Content-Type: application/json" \
  -d '{
    "sessionId": "sess-ana-1",
    "message": "Sou a Ana PAT-BR-001. Minha insulina está para acabar, posso pedir um novo frasco na loja LOJA-SP-001?"
  }' | jq
```

Expected behavior:

* Agent calls `GetPatientProfileTool` + `GetStoreInventoryTool` through MI.
* Explains in **PT-BR**:

  * Refill eligibility,
  * Apparent stock at LOJA-SP-001,
  * Without giving medical advice.

#### 5.3.2 Ops agent – operations view

```bash
curl -s -X POST http://localhost:8293/v1/ops/chat \
  -H "Content-Type: application/json" \
  -d '{
    "sessionId": "sess-ops-1",
    "message": "Como está o estoque de insulina na loja LOJA-SP-001 e se preciso repor do CD?"
  }' | jq
```

#### 5.3.3 Compliance agent – controlled drug

```bash
curl -s -X POST http://localhost:8293/v1/compliance/chat \
  -H "Content-Type: application/json" \
  -d '{
    "sessionId": "sess-comp-1",
    "message": "Quais cuidados de compliance devo considerar ao dispensar insulina para o paciente PAT-BR-001 na LOJA-SP-001?"
  }' | jq
```

#### 5.3.4 Finance agent – async tax via tools

```bash
curl -s -X POST http://localhost:8293/v1/finance/chat \
  -H "Content-Type: application/json" \
  -d '{
    "sessionId": "sess-fin-1",
    "message": "Envie um relatório de imposto para a loja LOJA-SP-001 no valor de 1500 reais e me explique o que foi feito."
  }' | jq
```

#### 5.3.5 Omni – full agentic orchestration

Ask something that touches **care + ops + compliance + finance**:

```bash
curl -s -X POST http://localhost:8293/v1/omni/chat \
  -H "Content-Type: application/json" \
  -d '{
    "sessionId": "sess-omni-1",
    "message": "Sou o paciente PAT-BR-001. Minha insulina está acabando na loja LOJA-SP-001, preciso repor do CD e também registrar os impostos e garantir que está tudo conforme as regras para medicamento controlado. O que vocês conseguem me dizer?"
  }' | jq
```

Under the hood:

1. **Router** (`detectPharmaDomains`) maps the message to domains CARE, OPS, COMPLIANCE, FINANCE.
2. **Fan-out** runs `careAgent`, `opsAgent`, `complianceAgent`, `financeAgent` in parallel with Ballerina futures.
3. **Omni synthesis** combines sub-answers into a single narrative (in PT-BR).
4. **Compliance overlay** removes advice, tones down commitments, and adds a legal/medical disclaimer.

---

## 6. Demo Flow

Suggested sequence for a live demo:

1. **Set the scene**

   * Business story: Brazilian pharma distributor, chronic patients, cold chain, tax & compliance.
   * Show the **layered diagram**: Apps → Agents → MI → Backend.

2. **Start at the core (Node.js)**

   * Show small snippets of `patientsDb` and `storeInventory`.

   * Run:

     ```bash
     curl -s http://localhost:8080/patients/profile/PAT-BR-001 | jq
     curl -s "http://localhost:8080/stores/LOJA-SP-001/inventory?sku=MED-INSULINA" | jq
     ```

   * Emphasize: no AI here, just deterministic behavior.

3. **Move to MI (integration plane)**

   * Open `PharmaCustomerAPI.xml` and `CustomerProfileEP.xml`.

     * Point out `version="1.0.0"`, `version-type="context"`.
     * Show `CommonInSeq`, `CommonOutSeq`, `CommonFaultSeq`.

   * Run:

     ```bash
     curl -s "$BASE_MI/customers/1.0.0/patient/PAT-BR-001" | jq
     ```

   * Show logs in MI with `CorrelationId` and `latency.ms`.

4. **Show async pattern**

   * Open `PharmaOrdersAPI.xml`, `RxOrderStore.xml`, `RxOrderProcessor.xml`.

   * Call:

     ```bash
     curl -s -X POST "$BASE_MI/orders/1.0.0/prescriptions/async" ...
     ```

   * Then:

     ```bash
     curl -s http://localhost:8080/ops/processor-events | jq
     ```

   * Explain how MI acts as **reliable async orchestrator**.

5. **Introduce Agentic layer**

   * Show `agents.bal`:

     * Briefly read out roles of care, ops, compliance, finance, omni, overlay.
   * Show `tools.bal`:

     * Highlight `@ai:AgentTool` and the **uniform envelope**.
   * Show `main.bal`:

     * `handleAgentRequestSimple` (single-agent pattern with retry),
     * `handleOmniRequest` (router + fan-out + overlay).

6. **Single-agent demo**

   * Call care agent:

     ```bash
     curl -s -X POST http://localhost:8293/v1/care/chat ...
     ```

   * Explain how it calls MI via tools, interprets envelopes, and answers in Portuguese.

7. **Omni orchestration demo**

   * Call `/v1/omni/chat` with the multi-domain question.
   * Narrate the step-by-step orchestration:

     * Router (`detectPharmaDomains`),
     * Parallel calls with `start`/`wait`,
     * Omni synthesis,
     * Compliance overlay and disclaimer.

8. **Failure mode (optional)**

   * Stop `pharma-backend` container temporarily.
   * Hit care or omni again and show:

     * MI returns `502` with JSON fault envelope.
     * Tools wrap that into `status:"ERROR", errorCode:"BACKEND_UNAVAILABLE"`.
     * Prompts force the agent to say **systems are temporarily unavailable**, without fabricating data.

9. **Wrap up**

   * Emphasize:

     * How **agentic orchestration** is layered over traditional integration patterns.
     * How **resilience** is handled jointly by MI and Ballerina.
     * How **safety** and **observability** are not afterthoughts, but baked into every layer through prompts, envelopes, and standardized logging.