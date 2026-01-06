function notFoundHandler(req, res) {
  res.status(404).json({
    message: "Resource not found",
    path: req.path
  });
}

module.exports = { notFoundHandler };
