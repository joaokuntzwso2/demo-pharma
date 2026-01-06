function badRequest(message, details) {
  const err = new Error(message);
  err.statusCode = 400;
  if (details) err.details = details;
  return err;
}

function notFound(message) {
  const err = new Error(message);
  err.statusCode = 404;
  return err;
}

function assertRequired(obj, fields) {
  const missing = [];
  for (const f of fields) {
    if (obj?.[f] === undefined || obj?.[f] === null || obj?.[f] === "") missing.push(f);
  }
  if (missing.length) throw badRequest(`Body must contain ${missing.join(", ")}`, { missing });
}

module.exports = { badRequest, notFound, assertRequired };
