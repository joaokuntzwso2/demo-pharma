const express = require("express");
const { getState } = require("../stores/memory.store");

const router = express.Router();

/**
 * GET /patients/profile/:patientId
 * Must match original response shape used by MI façade.
 */
router.get("/profile/:patientId", (req, res) => {
  const { patientId } = req.params;
  const { patientsDb } = getState();

  const patient = patientsDb[patientId];

  if (!patient) {
    return res.json({
      exists: false,
      patientId,
      message: "Patient not found in the demo database"
    });
  }

  const activePrescriptions = (patient.prescriptions || []).map((p) => ({
    ...p,
    refillEligible: Boolean(p.refillable && p.refillsRemaining > 0)
  }));

  return res.json({
    exists: true,
    patientId: patient.patientId,
    cpf: patient.cpf,
    name: patient.name,
    chronicConditions: patient.chronicConditions,
    preferredStoreId: patient.preferredStoreId,
    activePrescriptions
  });
});

module.exports = router;
