const express = require("express");
const { getState } = require("../stores/memory.store");
const { nowIso } = require("../utils/time");

const router = express.Router();

/**
 * POST /finance/tax-report
 */
router.post("/tax-report", (req, res) => {
  const { taxReports } = getState();

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

/**
 * GET /finance/tax-report
 */
router.get("/tax-report", (req, res) => {
  const { taxReports } = getState();
  res.json(taxReports.slice(-50));
});

module.exports = router;
