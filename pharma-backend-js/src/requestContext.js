const { randomUUID } = require("crypto");

function requestContextMiddleware(req, res, next) {
  const incoming =
    req.header("x-correlation-id") ||
    req.header("x-fapi-interaction-id") ||
    req.header("x-request-id") ||
    null;

  const correlationId = incoming || `corr-${randomUUID()}`;

  req.ctx = {
    correlationId,
    receivedAt: new Date().toISOString()
  };

  // Echo correlation id for clients/MI visibility
  res.setHeader("X-Correlation-Id", correlationId);

  next();
}

module.exports = { requestContextMiddleware };
