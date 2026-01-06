const express = require("express");
const { getState } = require("../stores/memory.store");
const { nowIso } = require("../utils/time");

/* eslint-disable no-console */

const router = express.Router();

/**
 * POST /ops/processor-events
 */
router.post("/processor-events", (req, res) => {
  const { processorEvents } = getState();

  const event = req.body || {};
  const enrichedEvent = {
    ...event,
    receivedAt: nowIso()
  };

  processorEvents.push(enrichedEvent);
  console.log("Processor event from MI:", JSON.stringify(enrichedEvent, null, 2));

  return res.status(202).json({ status: "RECEIVED", count: processorEvents.length });
});

/**
 * GET /ops/processor-events
 */
router.get("/processor-events", (req, res) => {
  const { processorEvents } = getState();
  const last = [...processorEvents].reverse().slice(0, 50);
  res.json(last);
});

module.exports = router;
