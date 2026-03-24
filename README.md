# Open Pharma Demo – Agentic APIs Experience Platform

End-to-end demo of a **tier-1-grade digital stack for a pharma distributor + retail chain**, built around three main layers:

* **WSO2 Micro Integrator (MI) 4.5**
  Mediation, orchestration, async queues and message stores, circuit breaking, retries, centralized logging, and fault normalization.

* **Pharma BI Agents (Ballerina)**
  Multiple **LLM-powered agents** consuming MI APIs through typed tools and standardized envelopes, with **agentic orchestration patterns** such as routing, fan-out, synthesis, and compliance overlay.

* **Node.js backend** (`pharma-backend-js`)
  Mock “core systems” for:

  * Patient CRM (CPF-based), chronic conditions, prescriptions
  * Store inventory and DC stock
  * Prescription orders and shipments
  * Compliance audit events
  * Tax reports
  * Processor events and technical alerts

> **Language policy**
>
> * All code comments and prompts are in **English** for auditability.
> * The agent layer is configured to answer in **English**.

---

## 1. Business and Technical Storyline

### 1.1 Business perspective

For a given **patient** and **store**, this demo shows:

#### Patient 360

* Basic CRM: name, chronic conditions, preferred store
* Active prescriptions and refillability
* Whether a medication appears available at a specific store

#### Store and DC inventory

* SKU-level inventory for a store
* `coldChain` flag for temperature-sensitive medication such as insulin
* Replenishment flows toward the DC, asynchronously through MI queues

#### Orders and shipments

* Prescription order creation, both sync and async
* Shipment dispatch from DC to store
* Order and shipment lifecycle with mocked status progression

#### Compliance and tax

* Recording compliance audit events
* Asynchronous tax report submission via MI message stores
* Clear safety boundary: the AI agents do **not** provide medical, legal, or fiscal advice

---

### 1.2 Technical perspective

#### Layer 1 – Node.js Backend (`pharma-backend-js`)

Main files:

* `pharma-backend-js/server.js`
* `pharma-backend-js/src/app.js`

The backend is the deterministic mock system of record for the demo.

It exposes:

* **Patient CRM**

  * `GET /patients/profile/:patientId`

* **Store inventory**

  * `GET /stores/:storeId/inventory`
  * `GET /stores/:storeId/inventory?sku=...`

* **Orders**

  * `POST /orders/prescriptions`
  * `GET /orders/:id`
  * `GET /orders`

* **Shipments**

  * `POST /shipments/dispatch`
  * `GET /shipments/:id`
  * `GET /shipments`

* **Compliance**

  * `POST /compliance/audit`
  * `GET /compliance/audit`

* **Finance**

  * `POST /finance/tax-report`
  * `GET /finance/tax-report`

* **Operational telemetry**

  * `POST /ops/processor-events`
  * `GET /ops/processor-events`
  * `POST /tech/alerts`

* **Demo admin**

  * `POST /admin/reset`
  * `GET /admin/snapshot`

Backend behavior is intentionally simple:

* no AI
* no persistence beyond memory
* no circuit breaking or retries
* state resets cleanly for each demo

---

#### Layer 2 – WSO2 Micro Integrator 4.5 (`pharma-mi`)

MI is the canonical integration layer.

It:

* normalizes REST interfaces
* routes requests to backend endpoints
* applies async queueing and scheduled forwarding
* centralizes logging and correlation
* normalizes faults and backend unavailability

MI façade URLs are versioned under `1.0.0`, such as:

* `/customers/1.0.0/...`
* `/inventory/1.0.0/...`
* `/orders/1.0.0/...`
* `/shipments/1.0.0/...`
* `/compliance/1.0.0/...`
* `/finance/1.0.0/...`

### MI façade behavior

#### Customers

* `GET /customers/1.0.0/patient/{patientId}`
* Proxies to backend patient profile lookup

#### Inventory

* `GET /inventory/1.0.0/stores/{storeId}/items/{sku}`
* Proxies to backend store inventory lookup
* `POST /inventory/1.0.0/replenishment/async`
* Queues replenishment into `ReplenishmentStore`, then forwards through `ReplenishmentProcessor`

#### Orders

* `POST /orders/1.0.0/prescriptions/sync`
* Synchronous order creation through MI
* `POST /orders/1.0.0/prescriptions/async`
* Asynchronous order queue via `RxOrderStore` and `RxOrderProcessor`
* `GET /orders/1.0.0?orderId=...`
* Order status lookup through MI

#### Shipments

* `GET /shipments/1.0.0?shipmentId=...`
* Shipment status lookup through MI

#### Compliance

* `POST /compliance/1.0.0/audit`
* Compliance event creation through MI

#### Finance

* `POST /finance/1.0.0/tax-report/async`
* Queues tax report into `TaxReportStore`, then forwards asynchronously

> **Important**
>
> Order and shipment lookups in MI use **query parameters** in this final version:
>
> * `/orders/1.0.0?orderId=...`
> * `/shipments/1.0.0?shipmentId=...`

---

#### Layer 3 – Pharma BI Agents (`pharma_agent`)

Key files:

* `config.bal`
* `types.bal`
* `functions.bal`
* `tools.bal`
* `agents.bal`
* `main.bal`

This layer provides:

* specialized LLM agents
* typed tool access to MI
* consistent error envelopes
* session-based memory
* an omni-agent that orchestrates other agents

### Specialized agents

* **Care agent**

  * Patient context, prescriptions, apparent store availability
  * No medical advice

* **Ops agent**

  * Inventory, order status, shipment status
  * Operational language only

* **Compliance agent**

  * Conservative compliance interpretation
  * No legal or clinical advice

* **Finance agent**

  * Tax report submission explanation
  * No fiscal advice

* **Omni agent**

  * Orchestrates sub-agents
  * Produces a single executive-style answer

* **Compliance overlay agent**

  * Post-processes omni output
  * Removes unsafe wording and adds disclaimer

### Tool layer

The tools call MI, not the backend directly.

Implemented tools:

* `GetPatientProfileTool`
* `GetStoreInventoryTool`
* `GetOrderStatusTool`
* `GetShipmentStatusTool`
* `SubmitTaxReportTool`

Each tool returns a standard envelope like:

```json
{
  "tool": "GetPatientProfileTool",
  "status": "SUCCESS",
  "errorCode": "",
  "httpStatus": 200,
  "safeToRetry": false,
  "message": "",
  "result": {},
  "correlationId": "corr-..."
}
```

---

## 2. Repository Structure

```text
.
├── README.md
├── docker-compose.yml
├── openapi
│   ├── admin.yml
│   ├── compliance.yml
│   ├── finance.yml
│   ├── operations.yml
│   ├── orders.yml
│   ├── patients.yml
│   ├── shipments.yml
│   ├── stores.yml
│   ├── tech.yml
│   └── wso2-integrator.yml
├── pharma-backend-js
│   ├── Dockerfile
│   ├── package-lock.json
│   ├── package.json
│   ├── server.js
│   └── src
│       ├── app.js
│       ├── data
│       │   └── seed.js
│       ├── middleware
│       │   ├── errorHandler.js
│       │   └── notFound.js
│       ├── requestContext.js
│       ├── routes
│       │   ├── admin.routes.js
│       │   ├── compliance.routes.js
│       │   ├── finance.routes.js
│       │   ├── health.routes.js
│       │   ├── ops.routes.js
│       │   ├── orders.routes.js
│       │   ├── patients.routes.js
│       │   ├── shipments.routes.js
│       │   ├── stores.routes.js
│       │   └── tech.routes.js
│       ├── stores
│       │   └── memory.store.js
│       └── utils
│           ├── time.js
│           └── validation.js
├── pharma-mi
│   ├── deployment
│   │   ├── deployment.toml
│   │   └── docker
│   │       ├── Dockerfile
│   │       └── resources
│   │           ├── client-truststore.jks
│   │           └── wso2carbon.jks
│   ├── pom.xml
│   └── src
│       └── main
│           └── wso2mi
│               ├── artifacts
│               │   ├── apis
│               │   │   └── PharmaUnifiedAPI.xml
│               │   ├── endpoints
│               │   ├── inbound-endpoints
│               │   ├── local-entries
│               │   ├── message-processors
│               │   ├── message-stores
│               │   └── sequences
│               └── resources
│                   ├── api-definitions
│                   ├── conf
│                   └── metadata
└── pharma_agent
    ├── Ballerina.toml
    ├── Config.toml
    ├── Dependencies.toml
    ├── Dockerfile
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

* Docker and Docker Compose
* An OpenAI API key

### 3.2 Environment variable

```bash
export OPENAI_API_KEY="sk-..."
```

### 3.3 Start everything

```bash
docker compose up --build -d
```

### 3.4 Service endpoints

* Backend: `http://localhost:8080`
* MI: `http://localhost:8290`
* Agent layer: `http://localhost:8293`

---

## 4. Good Practices Demonstrated

* **Correlation IDs end to end**

  * Propagated across agent, MI, and backend

* **Strong separation of concerns**

  * Backend: domain state and rules
  * MI: mediation, resilience, async
  * Agents: language interface and orchestration

* **Safety boundaries**

  * No medical, legal, or fiscal advice
  * Overlay agent adds final disclaimer

* **Resilience**

  * MI retries and circuit breaking
  * async stores and processors
  * one transient retry at LLM layer

* **Observability**

  * MI IN/OUT/FAULT logs
  * backend processor-event tracking
  * agent logs with prompt versions and correlation IDs

* **Sticky sessions**

  * `sessionId` controls memory window in agent interactions

---

## 5. Curl Cookbook

## 0) Pre-flight

### Start everything

This builds and starts the three services.

```bash
docker compose up --build -d
```

### Set base URLs

These variables make the rest of the demo faster to run.

```bash
export BACKEND=http://localhost:8080
export MI=http://localhost:8290
export AGENT=http://localhost:8293
export CID=demo-$(date +%s)
```

### Quick health checks

These verify that the backend and agent are up.

Backend health:

* Calls the Node.js backend directly
* Expected behavior: HTTP `200` with component status

```bash
curl -i "$BACKEND/health"
```

Agent health:

* Calls the Ballerina agent directly
* Expected behavior: HTTP `200`

```bash
curl -i "$AGENT/v1/health"
```

Agent readiness:

* Shows agent dependency status
* Expected behavior: HTTP `200`

```bash
curl -i "$AGENT/v1/health/ready"
```

### Reset backend state before the demo

This restores the in-memory state to a known clean seed.

```bash
curl -i -X POST "$BACKEND/admin/reset"
```

---

## 1) All reachable `pharma-backend-js` endpoints

### 1.1 Health

Checks whether the backend service is up.

```bash
curl -i "$BACKEND/health"
```

Expected behavior:

* HTTP `200`
* JSON with `status: "UP"` and backend component name

### 1.2 Patients

Existing seeded patient:

* Returns patient profile, chronic conditions, preferred store, and active prescriptions

```bash
curl -i "$BACKEND/patients/profile/PAT-BR-001"
```

Another seeded patient:

```bash
curl -i "$BACKEND/patients/profile/PAT-BR-003"
```

Expected behavior:

* HTTP `200`
* JSON payload with patient data from the in-memory seed

### 1.3 Stores

Specific SKU inventory:

* Looks up one SKU in one store

```bash
curl -i "$BACKEND/stores/LOJA-SP-001/inventory?sku=MED-INSULINA"
```

All inventory for one store:

* Returns the whole store inventory map

```bash
curl -i "$BACKEND/stores/LOJA-MG-001/inventory"
```

Expected behavior:

* HTTP `200`
* JSON inventory payload including quantity, reorder point, and cold-chain information when applicable

### 1.4 Orders

Create a new order directly in backend:

* Creates a prescription order without MI
* Captures the generated `orderId`

```bash
ORDER_ID=$(
  curl -s -X POST "$BACKEND/orders/prescriptions" \
    -H "Content-Type: application/json" \
    -H "X-Correlation-Id: $CID" \
    -d '{
      "patientId": "PAT-BR-001",
      "storeId": "LOJA-SP-001",
      "sku": "MED-INSULINA",
      "quantity": 1,
      "channel": "APP_MOBILE"
    }' | python3 -c "import sys,json; print(json.load(sys.stdin)['orderId'])"
)

echo "$ORDER_ID"
```

Expected behavior:

* HTTP `201`
* New order created with status `PENDING_FULFILLMENT`

Get that order:

```bash
curl -i "$BACKEND/orders/$ORDER_ID"
```

List recent orders:

```bash
curl -i "$BACKEND/orders"
```

Get a seeded order that already exists:

```bash
curl -i "$BACKEND/orders/ORD-LOJA-SP-001-MED-INSULINA-2025-01-10T10:00:00.000Z"
```

Expected behavior:

* HTTP `200`
* Order details and current status

### 1.5 Shipments

Create shipment for the order you just created:

* Dispatches from DC `CD-SP-01`
* Captures the generated `shipmentId`

```bash
SHIPMENT_ID=$(
  curl -s -X POST "$BACKEND/shipments/dispatch" \
    -H "Content-Type: application/json" \
    -H "X-Correlation-Id: $CID" \
    -d "{
      \"orderId\": \"$ORDER_ID\",
      \"dcId\": \"CD-SP-01\"
    }" | python3 -c "import sys,json; print(json.load(sys.stdin)['shipmentId'])"
)

echo "$SHIPMENT_ID"
```

Expected behavior:

* HTTP `201`
* Shipment created with status `IN_TRANSIT`

Get that shipment:

```bash
curl -i "$BACKEND/shipments/$SHIPMENT_ID"
```

List recent shipments:

```bash
curl -i "$BACKEND/shipments"
```

Get a seeded shipment that already exists:

```bash
curl -i "$BACKEND/shipments/SHP-ORD-LOJA-SP-001-MED-INSULINA-2025-01-10T10:00:00.000Z-2025-01-10T12:00:00.000Z"
```

Expected behavior:

* HTTP `200`
* Shipment details with shipment status and cold-chain flag

### 1.6 Compliance

Create a compliance audit event:

```bash
curl -i -X POST "$BACKEND/compliance/audit" \
  -H "Content-Type: application/json" \
  -H "X-Correlation-Id: $CID" \
  -d '{
    "eventType": "COLD_CHAIN_CHECK",
    "storeId": "LOJA-SP-001",
    "sku": "MED-INSULINA",
    "notes": "Cold-chain transport validation for VP demo"
  }'
```

List audit events:

```bash
curl -i "$BACKEND/compliance/audit"
```

Expected behavior:

* POST returns HTTP `201` with generated compliance event metadata
* GET returns HTTP `200` with recent events

### 1.7 Finance

Create a tax report directly in backend:

```bash
curl -i -X POST "$BACKEND/finance/tax-report" \
  -H "Content-Type: application/json" \
  -H "X-Correlation-Id: $CID" \
  -d '{
    "storeId": "LOJA-SP-001",
    "amountBr": 15432.75
  }'
```

List tax reports:

```bash
curl -i "$BACKEND/finance/tax-report"
```

Expected behavior:

* POST returns HTTP `201`
* GET returns HTTP `200` with recent reports

### 1.8 Ops

Post a processor event manually:

```bash
curl -i -X POST "$BACKEND/ops/processor-events" \
  -H "Content-Type: application/json" \
  -H "X-Correlation-Id: $CID" \
  -d '{
    "processor": "MANUAL_DEMO_PROCESSOR",
    "operation": "DEMO_EVENT",
    "eventType": "MESSAGE_FORWARDED"
  }'
```

List processor events:

```bash
curl -i "$BACKEND/ops/processor-events"
```

Expected behavior:

* POST returns HTTP `202`
* GET returns HTTP `200` with event history

### 1.9 Tech

Send a tech alert:

```bash
curl -i -X POST "$BACKEND/tech/alerts" \
  -H "Content-Type: application/json" \
  -H "X-Correlation-Id: $CID" \
  -d '{
    "severity": "WARN",
    "component": "MI",
    "message": "Technical alert test for the demo"
  }'
```

Expected behavior:

* HTTP `202`
* Alert is logged by backend

### 1.10 Admin

Get snapshot:

```bash
curl -i "$BACKEND/admin/snapshot"
```

Reset state again:

```bash
curl -i -X POST "$BACKEND/admin/reset"
```

Expected behavior:

* Snapshot returns HTTP `200` with counts of in-memory entities
* Reset restores seed data

---

## 2) All reachable `pharma-mi` endpoints

These are the integration-layer endpoints.

Reset first so the MI demo starts clean:

```bash
curl -i -X POST "$BACKEND/admin/reset"
```

### 2.1 Compliance API via MI

This enters through MI, which applies common mediation and forwards to backend compliance audit.

```bash
curl -i -X POST "$MI/compliance/1.0.0/audit" \
  -H "Content-Type: application/json" \
  -H "X-Correlation-Id: $CID" \
  -d '{
    "eventType": "COLD_CHAIN_AUDIT",
    "storeId": "LOJA-SP-001",
    "sku": "MED-INSULINA",
    "notes": "Event received via WSO2 MI"
  }'
```

Verify in backend:

```bash
curl -i "$BACKEND/compliance/audit"
```

Expected behavior:

* MI call returns HTTP `201`
* backend list shows the new compliance event

### 2.2 Customer API via MI

This shows MI acting as façade for patient profile retrieval.

```bash
curl -i "$MI/customers/1.0.0/patient/PAT-BR-001"
```

```bash
curl -i "$MI/customers/1.0.0/patient/PAT-BR-003"
```

Expected behavior:

* HTTP `200`
* same patient data as backend, but accessed through MI

### 2.3 Finance async API via MI

This is an async flow using `TaxReportStore` and `TaxReportProcessor`.

Queue a tax report:

```bash
curl -i -X POST "$MI/finance/1.0.0/tax-report/async" \
  -H "Content-Type: application/json" \
  -H "X-Correlation-Id: $CID" \
  -d '{
    "storeId": "LOJA-SP-001",
    "amountBr": 9876.54
  }'
```

Wait for processor:

```bash
sleep 9
```

Verify it reached backend:

```bash
curl -i "$BACKEND/finance/tax-report"
```

Verify processor events:

```bash
curl -i "$BACKEND/ops/processor-events"
```

Expected behavior:

* initial MI response is HTTP `202` with `QUEUED`
* after waiting, backend tax reports should include the new report
* backend processor events should show forwarding activity

### 2.4 Inventory API via MI

This shows MI inventory mediation.

```bash
curl -i "$MI/inventory/1.0.0/stores/LOJA-SP-001/items/MED-INSULINA"
```

```bash
curl -i "$MI/inventory/1.0.0/stores/LOJA-RJ-001/items/MED-ANTIBIOTICO"
```

Expected behavior:

* HTTP `200`
* inventory payload returned through MI

### 2.5 Replenishment async API via MI

This shows MI async replenishment via queue and processor.

Queue replenishment:

```bash
curl -i -X POST "$MI/inventory/1.0.0/replenishment/async" \
  -H "Content-Type: application/json" \
  -H "X-Correlation-Id: $CID" \
  -d '{
    "storeId": "LOJA-RJ-001",
    "sku": "MED-INSULINA"
  }'
```

Wait for processor:

```bash
sleep 7
```

Verify order was created in backend:

```bash
curl -i "$BACKEND/orders"
```

Verify processor events:

```bash
curl -i "$BACKEND/ops/processor-events"
```

Expected behavior:

* initial MI response is HTTP `202` with `QUEUED`
* backend orders should now include a replenishment-generated order
* processor events should confirm forwarding

### 2.6 Orders sync API via MI

This is synchronous order creation through MI.

Create synchronous prescription order via MI:

```bash
MI_SYNC_ORDER_ID=$(
  curl -s -X POST "$MI/orders/1.0.0/prescriptions/sync" \
    -H "Content-Type: application/json" \
    -H "X-Correlation-Id: $CID" \
    -d '{
      "patientId": "PAT-BR-001",
      "storeId": "LOJA-SP-001",
      "sku": "MED-INSULINA",
      "quantity": 1,
      "channel": "APP_MOBILE"
    }' | python3 -c "import sys,json; print(json.load(sys.stdin)['orderId'])"
)

echo "$MI_SYNC_ORDER_ID"
```

Get that order through MI:

```bash
curl -i "$MI/orders/1.0.0?orderId=$MI_SYNC_ORDER_ID"
```

Also get a seeded completed order through MI:

```bash
curl -i "$MI/orders/1.0.0?orderId=ORD-LOJA-SP-001-MED-INSULINA-2025-01-10T10:00:00.000Z"
```

Expected behavior:

* POST returns HTTP `201`
* GET returns HTTP `200` with the order record

### 2.7 Orders async API via MI

This is asynchronous order creation via `RxOrderStore` and `RxOrderProcessor`.

Queue asynchronous prescription order:

```bash
curl -i -X POST "$MI/orders/1.0.0/prescriptions/async" \
  -H "Content-Type: application/json" \
  -H "X-Correlation-Id: $CID" \
  -d '{
    "patientId": "PAT-BR-003",
    "storeId": "LOJA-MG-001",
    "sku": "MED-ANTI-HIPERTENSAO",
    "quantity": 1,
    "channel": "APP_MOBILE"
  }'
```

Wait for processor:

```bash
sleep 5
```

Verify new order exists in backend:

```bash
curl -i "$BACKEND/orders"
```

Verify processor events:

```bash
curl -i "$BACKEND/ops/processor-events"
```

Expected behavior:

* immediate MI response is HTTP `202` with `QUEUED`
* after waiting, backend should show the new order
* processor events should show forwarding

### 2.8 Shipments status API via MI

This uses the corrected query-parameter shipment lookup.

Get seeded shipment via MI:

```bash
curl -i "$MI/shipments/1.0.0?shipmentId=SHP-ORD-LOJA-SP-001-MED-INSULINA-2025-01-10T10:00:00.000Z-2025-01-10T12:00:00.000Z"
```

Expected behavior:

* HTTP `200`
* seeded shipment payload returned through MI

---

## 3) All reachable `pharma_agent` endpoints

### 3.1 Health

```bash
curl -i "$AGENT/v1/health"
```

```bash
curl -i "$AGENT/v1/health/ready"
```

Expected behavior:

* both return HTTP `200`
* readiness includes dependency summary

### 3.2 Care agent

This uses natural language to trigger patient and inventory tools through MI.

```bash
curl -i -X POST "$AGENT/v1/care/chat" \
  -H "Content-Type: application/json" \
  -H "X-Correlation-Id: $CID" \
  -d '{
    "sessionId": "vp-demo-care-01",
    "message": "Please look up patient PAT-BR-001, summarize the active prescriptions, and tell me whether MED-INSULINA appears to be available at store LOJA-SP-001."
  }'
```

Expected behavior:

* HTTP `200`
* English response summarizing patient profile, active prescriptions, and apparent store stock

### 3.3 Ops agent

This uses inventory, order, and shipment lookup tools.

```bash
curl -i -X POST "$AGENT/v1/ops/chat" \
  -H "Content-Type: application/json" \
  -H "X-Correlation-Id: $CID" \
  -d '{
    "sessionId": "vp-demo-ops-01",
    "message": "Please check the MED-INSULINA stock at store LOJA-SP-001 and the status of order ORD-LOJA-SP-001-MED-INSULINA-2025-01-10T10:00:00.000Z and shipment SHP-ORD-LOJA-SP-001-MED-INSULINA-2025-01-10T10:00:00.000Z-2025-01-10T12:00:00.000Z."
  }'
```

Expected behavior:

* HTTP `200`
* English operational answer with stock, order status, and shipment status

### 3.4 Compliance agent

This produces a conservative compliance-oriented summary.

```bash
curl -i -X POST "$AGENT/v1/compliance/chat" \
  -H "Content-Type: application/json" \
  -H "X-Correlation-Id: $CID" \
  -d '{
    "sessionId": "vp-demo-compliance-01",
    "message": "Please analyze possible compliance considerations for patient PAT-BR-001, MED-INSULINA, store LOJA-SP-001, and shipment SHP-ORD-LOJA-SP-001-MED-INSULINA-2025-01-10T10:00:00.000Z-2025-01-10T12:00:00.000Z."
  }'
```

Expected behavior:

* HTTP `200`
* English answer highlighting cold-chain and compliance considerations without legal or medical advice

### 3.5 Finance agent

This has a side effect: it triggers tax-report submission through MI.

```bash
curl -i -X POST "$AGENT/v1/finance/chat" \
  -H "Content-Type: application/json" \
  -H "X-Correlation-Id: $CID" \
  -d '{
    "sessionId": "vp-demo-finance-01",
    "message": "Please submit a tax report for store LOJA-SP-001 in the amount of 12345.67 BRL and explain what the integration just did."
  }'
```

Expected behavior:

* HTTP `200`
* English answer explaining that the tax-report submission was triggered asynchronously through the integration layer

---

## 4) Recommended Omni chats

Use the same `sessionId` to demonstrate conversation continuity and memory.

### Omni chat 1 — patient and store inventory

This is the best opening omni demo.

```bash
curl -i -X POST "$AGENT/v1/omni/chat" \
  -H "Content-Type: application/json" \
  -H "X-Correlation-Id: $CID" \
  -d '{
    "sessionId": "vp-demo-omni-01",
    "message": "Please look up patient PAT-BR-001, review the prescription, tell me whether MED-INSULINA appears to be available at store LOJA-SP-001, and highlight any relevant compliance considerations."
  }'
```

Expected behavior:

* HTTP `200`
* combined English answer synthesized from care, ops, and compliance perspectives

### Omni chat 2 — order and shipment operational visibility

This shows end-to-end operational tracking.

```bash
curl -i -X POST "$AGENT/v1/omni/chat" \
  -H "Content-Type: application/json" \
  -H "X-Correlation-Id: $CID" \
  -d '{
    "sessionId": "vp-demo-omni-01",
    "message": "Now check order ORD-LOJA-SP-001-MED-INSULINA-2025-01-10T10:00:00.000Z and shipment SHP-ORD-LOJA-SP-001-MED-INSULINA-2025-01-10T10:00:00.000Z-2025-01-10T12:00:00.000Z, summarizing status, operations, and compliance."
  }'
```

Expected behavior:

* HTTP `200`
* answer combining order lookup, shipment lookup, and compliance-oriented summary

### Omni chat 3 — out-of-stock and replenishment narrative

This is strong because seeded data shows zero insulin stock in RJ.

```bash
curl -i -X POST "$AGENT/v1/omni/chat" \
  -H "Content-Type: application/json" \
  -H "X-Correlation-Id: $CID" \
  -d '{
    "sessionId": "vp-demo-omni-01",
    "message": "Please analyze the MED-INSULINA situation at store LOJA-RJ-001. I want a combined view of inventory, operations, and possible compliance considerations."
  }'
```

Expected behavior:

* HTTP `200`
* executive English answer about stock situation, operational implications, and compliance concerns

### Omni chat 4 — finance and omni orchestration

This has a side effect because it triggers the finance tool.

```bash
curl -i -X POST "$AGENT/v1/omni/chat" \
  -H "Content-Type: application/json" \
  -H "X-Correlation-Id: $CID" \
  -d '{
    "sessionId": "vp-demo-omni-01",
    "message": "Please submit a tax report for store LOJA-SP-001 in the amount of 8888.90 BRL and give me an executive summary of what the integration did, including invoice, tax, operations, and traceability."
  }'
```

Expected behavior:

* HTTP `200`
* synthesized English answer combining finance and operational context
* underlying async tax-report submission is queued through MI

### Omni chat 5 — mixed executive summary

This is good for executive storytelling.

```bash
curl -i -X POST "$AGENT/v1/omni/chat" \
  -H "Content-Type: application/json" \
  -H "X-Correlation-Id: $CID" \
  -d '{
    "sessionId": "vp-demo-omni-01",
    "message": "Please provide an executive summary of patient PAT-BR-003, the MED-ANTI-HIPERTENSAO stock at store LOJA-MG-001, and what this means for operations and compliance."
  }'
```

Expected behavior:

* HTTP `200`
* English executive summary combining care, inventory, operations, and compliance

### Omni chat 6 — memory follow-up

This demonstrates sticky memory using the same session.

```bash
curl -i -X POST "$AGENT/v1/omni/chat" \
  -H "Content-Type: application/json" \
  -H "X-Correlation-Id: $CID" \
  -d '{
    "sessionId": "vp-demo-omni-01",
    "message": "Please summarize the most important points we have seen so far in five lines so I can present them to the VPs."
  }'
```

Expected behavior:

* HTTP `200`
* short English summary referring back to earlier conversation context
