const express = require("express");
const { getState, resetState } = require("../stores/memory.store");

const router = express.Router();

router.post("/reset", (req, res) => {
  const state = resetState();
  res.json({ status: "RESET", snapshot: summarize(state) });
});

router.get("/snapshot", (req, res) => {
  res.json({ snapshot: summarize(getState()) });
});

function summarize(state) {
  return {
    patients: Object.keys(state.patientsDb || {}).length,
    stores: Object.keys(state.storeInventory || {}).length,
    dcs: Object.keys(state.dcInventory || {}).length,
    orders: Object.keys(state.ordersStore || {}).length,
    shipments: Object.keys(state.shipmentsStore || {}).length,
    complianceEvents: (state.complianceEvents || []).length,
    taxReports: (state.taxReports || []).length,
    processorEvents: (state.processorEvents || []).length
  };
}

module.exports = router;
