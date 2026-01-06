function errorHandler(err, req, res, _next) {
  console.error("[ERROR]", {
    correlationId: req?.ctx?.correlationId,
    message: err?.message,
    stack: err?.stack
  });

  const status = err?.statusCode || 500;

  res.status(status).json({
    message: "An error occurred while processing the request",
    correlationId: req?.ctx?.correlationId,
    error: err?.message || "Unknown error"
  });
}

module.exports = { errorHandler };
