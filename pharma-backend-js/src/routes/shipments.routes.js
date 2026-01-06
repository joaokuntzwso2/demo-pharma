const express = require("express");
const { getState } = require("../stores/memory.store");
const { nowIso, nowIdTs, hoursDiff } = require("../utils/time");
const { assertRequired, notFound, badRequest } = require("../utils/validation");

const router = express.Router();

router.post("/dispatch", (req, res, next) => {
  try {
    const body = req.body || {};
    assertRequired(body, ["orderId", "dcId"]);

    const { orderId, dcId } = body;
    const state = getState();

    const order = state.ordersStore?.[orderId];
    if (!order) throw notFound("Ordem não encontrada");

    const dc = state.dcInventory?.[dcId];
    if (!dc) throw notFound("CD não encontrado");

    const dcItem = dc.items?.[order.sku];
    if (!dcItem) throw notFound("SKU não encontrado no estoque do CD");

    if (typeof dcItem.quantityOnHand !== "number" || dcItem.quantityOnHand < order.quantity) {
      throw badRequest("Estoque insuficiente no CD para atender a remessa");
    }

    dcItem.quantityOnHand -= order.quantity;

    const createdAt = nowIso();
    const idTs = nowIdTs();
    const shipmentId = `SHP-${orderId}-${idTs}`;

    const shipment = {
      shipmentId,
      orderId,
      dcId,
      storeId: order.storeId,
      status: "IN_TRANSIT",
      coldChain: order.coldChain,
      etaHours: 12,
      createdAt,
      lastUpdatedAt: createdAt
    };

    state.shipmentsStore[shipmentId] = shipment;
    return res.status(201).json(shipment);
  } catch (e) {
    return next(e);
  }
});

router.get("/:id", (req, res) => {
  const { id } = req.params;
  const state = getState();

  const shipment = state.shipmentsStore?.[id];
  if (!shipment) {
    return res.status(404).json({ message: "Remessa não encontrada" });
  }

  if (shipment.status === "IN_TRANSIT" && hoursDiff(shipment.createdAt) > 0.1) {
    shipment.status = "DELIVERED";
    shipment.lastUpdatedAt = nowIso();
  }

  return res.json(shipment);
});

router.get("/", (req, res) => {
  const state = getState();
  const all = Object.values(state.shipmentsStore || {});
  all.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
  res.json(all.slice(0, 50));
});

module.exports = router;
