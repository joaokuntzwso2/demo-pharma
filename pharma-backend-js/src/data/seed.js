const seed = {
  patientsDb: {
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
  },

  storeInventory: {
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
  },

  dcInventory: {
    "CD-SP-01": {
      dcId: "CD-SP-01",
      name: "Centro de Distribuição SP",
      region: "SP",
      items: {
        "MED-INSULINA": { sku: "MED-INSULINA", quantityOnHand: 200, coldChain: true },
        "MED-ANTIBIOTICO": { sku: "MED-ANTIBIOTICO", quantityOnHand: 1000, coldChain: false },
        "MED-ANALGESICO": { sku: "MED-ANALGESICO", quantityOnHand: 500, coldChain: false }
      }
    },
    "CD-RJ-01": {
      dcId: "CD-RJ-01",
      name: "Centro de Distribuição RJ",
      region: "RJ",
      items: {
        "MED-INSULINA": { sku: "MED-INSULINA", quantityOnHand: 80, coldChain: true },
        "MED-ANTIBIOTICO": { sku: "MED-ANTIBIOTICO", quantityOnHand: 600, coldChain: false }
      }
    }
  },

  ordersStore: {
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
  },

  shipmentsStore: {
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
  },

  complianceEvents: [],
  taxReports: [],
  processorEvents: []
};

module.exports = { seed };
