const { seed } = require("../data/seed");

function deepClone(obj) {
  return JSON.parse(JSON.stringify(obj));
}

let state = deepClone(seed);

function getState() {
  return state;
}

function resetState() {
  state = deepClone(seed);
  return getState();
}

module.exports = { getState, resetState };
