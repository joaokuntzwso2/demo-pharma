const express = require("express");
const morgan = require("morgan");
const cors = require("cors");

const app = express();
const PORT = process.env.PORT || 8080;

app.use(cors());
app.use(express.json());
app.use(morgan("dev"));

// ==========================
// Domain & in-memory stores
// ==========================

// --------------------------
// Patient CRM (demo patients)
// --------------------------
//
// Shape expected by GetPatientProfileTool (after MI façade):
//   GET /patients/profile/:patientId
//   {
//     exists: true|false,
//     patientId,
//     cpf,
//     name,
//     chronicConditions: [...],
//     preferredStoreId,
//     activePrescriptions: [
//       {
//         prescriptionId,
//         sku,
//         name,
//         dosage,
//         daysOfSupply,
//         refillable,
//         refillsRemaining,
//         lastDispensedAt,
//         refillEligible  // computed here
//       }
//     ]
//   }

const patientsDb = {
  // Diabetic, cold-chain insulin, São Paulo
  "PAT-BR-001": {
    patientId: "PAT-BR-001",
    cpf: "12345678901",
    name: "Ana Silva",
    chronicConditions: ["DIABETES_TIPO_1"],
    preferredStoreId: "LOJA-SP-001",
    prescriptions: [
      {
        prescriptionId: "RX-PAT-BR-001-INS-2025-01",
        sku: "MED-INSULINA",
        name: "Insulina 10 ml",
        dosage: "10 unidades 2 vezes ao dia",
        daysOfSupply: 30,
        refillable: true,
        refillsRemaining: 2,
        lastDispensedAt: "2025-01-05T10:00:00.000Z"
      }
    ]
  },

  // Short-term antibiotic, Rio de Janeiro
  "PAT-BR-002": {
    patientId: "PAT-BR-002",
    cpf: "98765432100",
    name: "Carlos Souza",
    chronicConditions: [],
    preferredStoreId: "LOJA-RJ-001",
    prescriptions: [
      {
        prescriptionId: "RX-PAT-BR-002-ATB-2025-01",
        sku: "MED-ANTIBIOTICO",
        name: "Antibiótico 500 mg",
        dosage: "1 cápsula a cada 12 horas",
        daysOfSupply: 7,
        refillable: false,
        refillsRemaining: 0,
        lastDispensedAt: "2025-01-03T11:00:00.000Z"
      }
    ]
  },

  // Hypertension + OTC painkiller, Belo Horizonte
  "PAT-BR-003": {
    patientId: "PAT-BR-003",
    cpf: "45678912355",
    name: "Mariana Oliveira",
    chronicConditions: ["HIPERTENSAO"],
    preferredStoreId: "LOJA-MG-001",
    prescriptions: [
      {
        prescriptionId: "RX-PAT-BR-003-ANTI-2025-01",
        sku: "MED-ANTI-HIPERTENSAO",
        name: "Anti-hipertensivo 20 mg",
        dosage: "1 comprimido ao dia",
        daysOfSupply: 30,
        refillable: true,
        refillsRemaining: 1,
        lastDispensedAt: "2025-01-08T09:30:00.000Z"
      },
      {
        prescriptionId: "RX-PAT-BR-003-ANALG-2025-01",
        sku: "MED-ANALGESICO",
        name: "Analgésico 750 mg",
        dosage: "1 comprimido se necessário (máx. 3x/dia)",
        daysOfSupply: 10,
        refillable: false,
        refillsRemaining: 0,
        lastDispensedAt: "2025-01-09T14:15:00.000Z"
      }
    ]
  }
};

// --------------------------
// Store inventory (retail)
// --------------------------
//
// Main store endpoint used by MI façade behind GetStoreInventoryTool:
//   - For a single SKU:
//       GET /stores/:storeId/inventory?sku=MED-...
//       → { storeId, sku, name, quantityOnHand, reorderPoint, coldChain }
//   - For full store inventory (debug/demo):
//       GET /stores/:storeId/inventory
//       → { storeId, items: { sku: { ... } } }

const storeInventory = {
  "LOJA-SP-001": {
    storeId: "LOJA-SP-001",
    name: "Drogaria Centro SP",
    region: "SP",
    items: {
      "MED-INSULINA": {
        sku: "MED-INSULINA",
        name: "Insulina 10 ml",
        quantityOnHand: 3,
        reorderPoint: 2,
        coldChain: true
      },
      "MED-ANTIBIOTICO": {
        sku: "MED-ANTIBIOTICO",
        name: "Antibiótico 500 mg",
        quantityOnHand: 20,
        reorderPoint: 10,
        coldChain: false
      },
      "MED-ANALGESICO": {
        sku: "MED-ANALGESICO",
        name: "Analgésico 750 mg",
        quantityOnHand: 50,
        reorderPoint: 20,
        coldChain: false
      }
    }
  },
  "LOJA-RJ-001": {
    storeId: "LOJA-RJ-001",
    name: "Drogaria Zona Sul RJ",
    region: "RJ",
    items: {
      "MED-INSULINA": {
        sku: "MED-INSULINA",
        name: "Insulina 10 ml",
        quantityOnHand: 0,
        reorderPoint: 3,
        coldChain: true
      },
      "MED-ANTIBIOTICO": {
        sku: "MED-ANTIBIOTICO",
        name: "Antibiótico 500 mg",
        quantityOnHand: 5,
        reorderPoint: 10,
        coldChain: false
      }
    }
  },
  "LOJA-MG-001": {
    storeId: "LOJA-MG-001",
    name: "Drogaria Savassi BH",
    region: "MG",
    items: {
      "MED-ANTI-HIPERTENSAO": {
        sku: "MED-ANTI-HIPERTENSAO",
        name: "Anti-hipertensivo 20 mg",
        quantityOnHand: 8,
        reorderPoint: 5,
        coldChain: false
      },
      "MED-ANALGESICO": {
        sku: "MED-ANALGESICO",
        name: "Analgésico 750 mg",
        quantityOnHand: 10,
        reorderPoint: 20,
        coldChain: false
      }
    }
  }
};

// --------------------------
// Distribution center (DC) inventory
// --------------------------
//
// Used mainly by dispatch / shipments flows to illustrate B2B-ish side.

const dcInventory = {
  "CD-SP-01": {
    dcId: "CD-SP-01",
    name: "Centro de Distribuição SP",
    region: "SP",
    items: {
      "MED-INSULINA": {
        sku: "MED-INSULINA",
        quantityOnHand: 200,
        coldChain: true
      },
      "MED-ANTIBIOTICO": {
        sku: "MED-ANTIBIOTICO",
        quantityOnHand: 1000,
        coldChain: false
      },
      "MED-ANALGESICO": {
        sku: "MED-ANALGESICO",
        quantityOnHand: 500,
        coldChain: false
      }
    }
  },
  "CD-RJ-01": {
    dcId: "CD-RJ-01",
    name: "Centro de Distribuição RJ",
    region: "RJ",
    items: {
      "MED-INSULINA": {
        sku: "MED-INSULINA",
        quantityOnHand: 80,
        coldChain: true
      },
      "MED-ANTIBIOTICO": {
        sku: "MED-ANTIBIOTICO",
        quantityOnHand: 600,
        coldChain: false
      }
    }
  }
};

// --------------------------
// Orders, shipments, compliance, taxes, processor events
// --------------------------
//
// These are intentionally minimal, but preloaded with a couple of samples so
// the Network/Ops agent can show status flows without having to create orders
// live every time in the demo.

const ordersStore = {
  // Example: completed cold-chain order for Ana in SP
  "ORD-LOJA-SP-001-MED-INSULINA-2025-01-10T10:00:00.000Z": {
    orderId: "ORD-LOJA-SP-001-MED-INSULINA-2025-01-10T10:00:00.000Z",
    patientId: "PAT-BR-001",
    storeId: "LOJA-SP-001",
    sku: "MED-INSULINA",
    quantity: 1,
    channel: "LOJA_FISICA",
    status: "COMPLETED",
    slaHours: 24,
    coldChain: true,
    createdAt: "2025-01-10T10:00:00.000Z",
    lastUpdatedAt: "2025-01-10T15:00:00.000Z"
  },

  // Example: order in progress for Mariana in MG
  "ORD-LOJA-MG-001-MED-ANTI-HIPERTENSAO-2025-01-11T09:00:00.000Z": {
    orderId: "ORD-LOJA-MG-001-MED-ANTI-HIPERTENSAO-2025-01-11T09:00:00.000Z",
    patientId: "PAT-BR-003",
    storeId: "LOJA-MG-001",
    sku: "MED-ANTI-HIPERTENSAO",
    quantity: 1,
    channel: "APP_MOBILE",
    status: "IN_PROGRESS",
    slaHours: 24,
    coldChain: false,
    createdAt: "2025-01-11T09:00:00.000Z",
    lastUpdatedAt: "2025-01-11T10:30:00.000Z"
  }
};

const shipmentsStore = {
  // Example shipment linked to the completed SP order
  "SHP-ORD-LOJA-SP-001-MED-INSULINA-2025-01-10T10:00:00.000Z-2025-01-10T12:00:00.000Z": {
    shipmentId:
      "SHP-ORD-LOJA-SP-001-MED-INSULINA-2025-01-10T10:00:00.000Z-2025-01-10T12:00:00.000Z",
    orderId: "ORD-LOJA-SP-001-MED-INSULINA-2025-01-10T10:00:00.000Z",
    dcId: "CD-SP-01",
    storeId: "LOJA-SP-001",
    status: "DELIVERED",
    coldChain: true,
    etaHours: 4,
    createdAt: "2025-01-10T12:00:00.000Z",
    lastUpdatedAt: "2025-01-10T16:00:00.000Z"
  }
};

const complianceEvents = [];
const taxReports = [];
const processorEvents = [];

// ==========================
// Helpers
// ==========================

function nowIso() {
  return new Date().toISOString();
}

function hoursDiff(fromIso) {
  const from = new Date(fromIso);
  const now = new Date();
  return (now - from) / (1000 * 60 * 60);
}

// ==========================
// Routes
// ==========================

// Health
app.get("/health", (_, res) => {
  res.json({ status: "UP", component: "Pharma-Backend-BR" });
});

// -------------------------------------------------------
// Patient profile – used by MI façade → GetPatientProfileTool
// -------------------------------------------------------
app.get("/patients/profile/:patientId", (req, res) => {
  const patientId = req.params.patientId;
  const patient = patientsDb[patientId];

  if (!patient) {
    return res.json({
      exists: false,
      patientId,
      message: "Paciente não encontrado na base de demo"
    });
  }

  const activePrescriptions = patient.prescriptions.map((p) => ({
    ...p,
    refillEligible: p.refillable && p.refillsRemaining > 0
  }));

  return res.json({
    exists: true,
    patientId: patient.patientId,
    cpf: patient.cpf,
    name: patient.name,
    chronicConditions: patient.chronicConditions,
    preferredStoreId: patient.preferredStoreId,
    activePrescriptions
  });
});

// -------------------------------------------------------
// Store inventory – used by MI façade → GetStoreInventoryTool
// -------------------------------------------------------
app.get("/stores/:storeId/inventory", (req, res) => {
  const { storeId } = req.params;
  const { sku } = req.query;

  const store = storeInventory[storeId];
  if (!store) {
    return res.status(404).json({ message: "Loja não encontrada" });
  }

  // Full inventory for debug/demo
  if (!sku) {
    return res.json({
      storeId,
      items: store.items
    });
  }

  const item = store.items[sku];
  if (!item) {
    return res.status(404).json({ message: "SKU não encontrado no estoque da loja" });
  }

  res.json({
    storeId,
    ...item
  });
});

// -------------------------------------------------------
// Prescription orders – used by MI façade (sync/async) → GetOrderStatusTool
// -------------------------------------------------------
app.post("/orders/prescriptions", (req, res) => {
  const { patientId, storeId, sku, quantity, channel } = req.body || {};

  if (!patientId || !storeId || !sku || !quantity || !channel) {
    return res.status(400).json({
      message: "Body deve conter patientId, storeId, sku, quantity e channel"
    });
  }

  const orderId = `ORD-${storeId}-${sku}-${nowIso()}`;
  const timestamp = nowIso();

  const order = {
    orderId,
    patientId,
    storeId,
    sku,
    quantity,
    channel,
    status: "PENDING_FULFILLMENT",
    slaHours: 24,
    coldChain: sku === "MED-INSULINA",
    createdAt: timestamp,
    lastUpdatedAt: timestamp
  };

  ordersStore[orderId] = order;
  return res.status(201).json(order);
});

// Order status – MI façade: GET /orders/{id}
app.get("/orders/:id", (req, res) => {
  const orderId = req.params.id;
  const order = ordersStore[orderId];

  if (!order) {
    return res.status(404).json({ message: "Ordem não encontrada" });
  }

  // Simple lifecycle progression for demo:
  // after ~6 minutes (0.1 hour) we consider the order completed if still pending.
  if (order.status === "PENDING_FULFILLMENT" && hoursDiff(order.createdAt) > 0.1) {
    order.status = "COMPLETED";
    order.lastUpdatedAt = nowIso();
  }

  res.json(order);
});

// -------------------------------------------------------
// Shipments – used by MI façade → GetShipmentStatusTool
// -------------------------------------------------------
app.post("/shipments/dispatch", (req, res) => {
  const { orderId, dcId } = req.body || {};

  if (!orderId || !dcId) {
    return res.status(400).json({ message: "Body deve conter orderId e dcId" });
  }

  const order = ordersStore[orderId];
  if (!order) {
    return res.status(404).json({ message: "Ordem não encontrada" });
  }

  const dc = dcInventory[dcId];
  if (!dc) {
    return res.status(404).json({ message: "CD não encontrado" });
  }

  const shipmentId = `SHP-${orderId}-${nowIso()}`;
  const timestamp = nowIso();

  const shipment = {
    shipmentId,
    orderId,
    dcId,
    storeId: order.storeId,
    status: "IN_TRANSIT",
    coldChain: order.coldChain,
    etaHours: 12,
    createdAt: timestamp,
    lastUpdatedAt: timestamp
  };

  shipmentsStore[shipmentId] = shipment;

  res.status(201).json(shipment);
});

// Shipment status – MI façade: GET /shipments/{id}
app.get("/shipments/:id", (req, res) => {
  const shipmentId = req.params.id;
  const shipment = shipmentsStore[shipmentId];

  if (!shipment) {
    return res.status(404).json({ message: "Remessa não encontrada" });
  }

  // Simple lifecycle progression for demo:
  // after ~6 minutes (0.1 hour) we consider the shipment delivered if still in transit.
  if (shipment.status === "IN_TRANSIT" && hoursDiff(shipment.createdAt) > 0.1) {
    shipment.status = "DELIVERED";
    shipment.lastUpdatedAt = nowIso();
  }

  res.json(shipment);
});

// -------------------------------------------------------
// Compliance audit – MI can push events here via dedicated sequences
// -------------------------------------------------------
app.post("/compliance/audit", (req, res) => {
  const event = req.body || {};
  const stored = {
    ...event,
    complianceId: `CMP-${nowIso()}`,
    createdAt: nowIso()
  };

  complianceEvents.push(stored);
  res.status(201).json(stored);
});

app.get("/compliance/audit", (req, res) => {
  res.json(complianceEvents.slice(-50));
});

// -------------------------------------------------------
// Tax reports – MI async façade (/finance/tax-report/async) forwards here
// -------------------------------------------------------
app.post("/finance/tax-report", (req, res) => {
  const report = req.body || {};
  const now = nowIso();

  const stored = {
    ...report,
    reportId: `TAX-${now}`,
    receivedAt: now
  };

  taxReports.push(stored);
  res.status(201).json(stored);
});

app.get("/finance/tax-report", (req, res) => {
  res.json(taxReports.slice(-50));
});

// -------------------------------------------------------
// Processor events & tech alerts – used by MI message processors and alerts
// -------------------------------------------------------
app.post("/ops/processor-events", (req, res) => {
  const event = req.body || {};
  const enrichedEvent = {
    ...event,
    receivedAt: nowIso()
  };

  processorEvents.push(enrichedEvent);
  console.log("Processor event from MI:", JSON.stringify(enrichedEvent, null, 2));

  return res.status(202).json({ status: "RECEIVED", count: processorEvents.length });
});

app.get("/ops/processor-events", (req, res) => {
  const last = [...processorEvents].reverse().slice(0, 50);
  res.json(last);
});

app.post("/tech/alerts", (req, res) => {
  console.log("[TECH ALERT] Received from MI:", req.body);
  return res.status(202).json({ status: "RECEIVED", at: nowIso() });
});

// ==========================
// Start server
// ==========================

app.listen(PORT, () => {
  console.log(`Pharma backend (BR) listening on port ${PORT}`);
});
