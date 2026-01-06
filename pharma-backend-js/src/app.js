const express = require("express");
const morgan = require("morgan");
const cors = require("cors");

// IMPORTANT: this matches your current tree: src/requestContext.js
const { requestContextMiddleware } = require("./requestContext");

const { notFoundHandler } = require("./middleware/notFound");
const { errorHandler } = require("./middleware/errorHandler");

const healthRouter = require("./routes/health.routes");
const patientsRouter = require("./routes/patients.routes");
const storesRouter = require("./routes/stores.routes");
const ordersRouter = require("./routes/orders.routes");
const shipmentsRouter = require("./routes/shipments.routes");
const complianceRouter = require("./routes/compliance.routes");
const financeRouter = require("./routes/finance.routes");
const opsRouter = require("./routes/ops.routes");
const techRouter = require("./routes/tech.routes");
const adminRouter = require("./routes/admin.routes");

function createApp() {
  const app = express();

  app.use(cors());
  app.use(express.json({ limit: "1mb" }));
  app.use(morgan("dev"));

  // Correlation Id + request context
  app.use(requestContextMiddleware);

  // Routes
  app.use("/", healthRouter);
  app.use("/patients", patientsRouter);
  app.use("/stores", storesRouter);
  app.use("/orders", ordersRouter);
  app.use("/shipments", shipmentsRouter);
  app.use("/compliance", complianceRouter);
  app.use("/finance", financeRouter);
  app.use("/ops", opsRouter);
  app.use("/tech", techRouter);

  // Optional demo utilities
  app.use("/admin", adminRouter);

  // 404 + error
  app.use(notFoundHandler);
  app.use(errorHandler);

  return app;
}

module.exports = { createApp };
