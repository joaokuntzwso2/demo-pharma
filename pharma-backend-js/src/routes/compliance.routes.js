const express = require("express");
const { getState } = require("../stores/memory.store");
const { nowIso } = require("../utils/time");

const router = express.Router();

/**
 * POST /compliance/audit
 */
router.post("/audit", (req, res) => {
  const { complianceEvents } = getState();
  const event = req.body || {};

  const stored = {
    ...event,
    complianceId: `CMP-${nowIso()}`,
    createdAt: nowIso()
  };

  complianceEvents.push(stored);
  res.status(201).json(stored);
});

/**
 * GET /compliance/audit
 */
router.get("/audit", (req, res) => {
  const { complianceEvents } = getState();
  res.json(complianceEvents.slice(-50));
});

module.exports = router;
