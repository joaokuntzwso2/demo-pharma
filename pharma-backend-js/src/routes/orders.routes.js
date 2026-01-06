const express = require("express");
const { getState } = require("../stores/memory.store");
const { nowIso, nowIdTs, hoursDiff } = require("../utils/time");
const { assertRequired, badRequest, notFound } = require("../utils/validation");

const router = express.Router();

function resolveColdChain(state, storeId, sku) {
  const storeItem = state.storeInventory?.[storeId]?.items?.[sku];
  if (storeItem && typeof storeItem.coldChain === "boolean") return storeItem.coldChain;

  return sku === "MED-INSULINA";
}

router.post("/prescriptions", (req, res, next) => {
  try {
    const body = req.body || {};
    assertRequired(body, ["patientId", "storeId", "sku", "quantity", "channel"]);

    const state = getState();
    const { patientId, storeId, sku, quantity, channel } = body;

    if (typeof quantity !== "number" || quantity <= 0) {
      throw badRequest("quantity deve ser um número > 0");
    }

    if (patientId !== "PAT-INTERNAL-REPLENISHMENT" && !state.patientsDb?.[patientId]) {
      throw notFound("Paciente não encontrado");
    }

    if (!state.storeInventory?.[storeId]) {
      throw notFound("Loja não encontrada");
    }

    const createdAt = nowIso();
    const idTs = nowIdTs();
    const orderId = `ORD-${storeId}-${sku}-${idTs}`;

    const order = {
      orderId,
      patientId,
      storeId,
      sku,
      quantity,
      channel,
      status: "PENDING_FULFILLMENT",
      slaHours: 24,
      coldChain: resolveColdChain(state, storeId, sku),
      createdAt,
      lastUpdatedAt: createdAt
    };

    state.ordersStore[orderId] = order;
    return res.status(201).json(order);
  } catch (e) {
    return next(e);
  }
});

router.get("/:id", (req, res) => {
  const { id } = req.params;
  const state = getState();

  const order = state.ordersStore[id];
  if (!order) {
    return res.status(404).json({ message: "Ordem não encontrada" });
  }

  if (order.status === "PENDING_FULFILLMENT" && hoursDiff(order.createdAt) > 0.1) {
    order.status = "COMPLETED";
    order.lastUpdatedAt = nowIso();

    const storeItem = state.storeInventory?.[order.storeId]?.items?.[order.sku];
    if (storeItem && typeof storeItem.quantityOnHand === "number") {
      storeItem.quantityOnHand = Math.max(0, storeItem.quantityOnHand - order.quantity);
    }
  }

  return res.json(order);
});

router.get("/", (req, res) => {
  const state = getState();
  const all = Object.values(state.ordersStore || {});
  all.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
  res.json(all.slice(0, 50));
});

module.exports = router;
