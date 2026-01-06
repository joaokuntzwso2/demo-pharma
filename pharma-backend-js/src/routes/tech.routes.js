const express = require("express");
const { nowIso } = require("../utils/time");

/* eslint-disable no-console */

const router = express.Router();

/**
 * POST /tech/alerts
 */
router.post("/alerts", (req, res) => {
  console.log("[TECH ALERT] Received from MI:", req.body);
  return res.status(202).json({ status: "RECEIVED", at: nowIso() });
});

module.exports = router;
