const express = require("express");
const { getState } = require("../stores/memory.store");

const router = express.Router();

/**
 * GET /stores/:storeId/inventory?sku=...
 * (Also supports GET /stores/:storeId/inventory without sku)
 */
router.get("/:storeId/inventory", (req, res) => {
  const { storeId } = req.params;
  const { sku } = req.query;

  const { storeInventory } = getState();
  const store = storeInventory[storeId];

  if (!store) {
    return res.status(404).json({ message: "Store not found" });
  }

  if (!sku) {
    return res.json({ storeId, items: store.items });
  }

  const item = store.items?.[sku];
  if (!item) {
    return res.status(404).json({ message: "SKU not found in the store inventory" });
  }

  return res.json({
    storeId,
    ...item
  });
});

module.exports = router;
