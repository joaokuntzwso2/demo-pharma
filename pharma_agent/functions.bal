import ballerina/time;
import ballerina/lang.'string as string;
import ballerinax/ai;

// -----------------------------------------------------------------------------
// Correlation IDs & safe logging helpers
// -----------------------------------------------------------------------------

public isolated function generateCorrelationId() returns string {
    return "corr-" + time:utcNow().toString();
}

public isolated function generateCorrelationIdForTool(string toolName) returns string {
    time:Utc now = time:utcNow();
    return string `corr-${toolName}-${now.toString()}`;
}

// Safely truncate a string for logs without panics.
public isolated function safeTruncate(string value, int maxLen) returns string {
    if value.length() <= maxLen {
        return value;
    }
    return value.substring(0, maxLen);
}

// Masking helpers (avoid PII in logs).
public isolated function maskPatientId(string patientId) returns string {
    return safeTruncate(patientId, 12);
}

public isolated function maskStoreId(string storeId) returns string {
    return safeTruncate(storeId, 12);
}

public isolated function maskOrderId(string orderId) returns string {
    return safeTruncate(orderId, 15);
}

public isolated function maskShipmentId(string shipmentId) returns string {
    return safeTruncate(shipmentId, 15);
}

// -----------------------------------------------------------------------------
// Domain routing helpers for Omni agent
// -----------------------------------------------------------------------------

// Case-insensitive "contains any of these markers?"
isolated function containsAnySubstringIgnoreCase(
    string sourceString,
    readonly & string[] markers
) returns boolean {
    if sourceString.length() == 0 {
        return false;
    }
    string normalized = sourceString.toLowerAscii();
    foreach string marker in markers {
        if string:includes(normalized, marker) {
            return true;
        }
    }
    return false;
}

// Keyword dictionaries for routing.
const string[] CARE_KEYWORDS = [
    "paciente", "receita", "prescrição", "refil", "refill", "remédio",
    "medicação", "dose", "dosagem", "farmácia", "loja"
];

const string[] OPS_KEYWORDS = [
    "estoque", "inventário", "disponível", "loja", "cd", "centro de distribuição",
    "pedido", "ordem", "remessa", "expedição", "reposição", "replenishment"
];

const string[] COMPLIANCE_KEYWORDS = [
    "controlado", "medicamento controlado", "tarja preta", "boas práticas",
    "compliance", "conformidade", "anvisa", "regulatório"
];

const string[] FINANCE_KEYWORDS = [
    "nota fiscal", "nf-e", "icms", "imposto", "taxa", "tributo", "fiscal"
];

// Detect one or more domains from the user message.
// Default to CARE for safety when nothing matches.
public isolated function detectPharmaDomains(string userMessage) returns PharmaDomain[] {
    string normalized = userMessage.toLowerAscii();
    PharmaDomain[] domains = [];

    if containsAnySubstringIgnoreCase(normalized, CARE_KEYWORDS) {
        domains.push(<PharmaDomain>"CARE");
    }
    if containsAnySubstringIgnoreCase(normalized, OPS_KEYWORDS) {
        domains.push(<PharmaDomain>"OPS");
    }
    if containsAnySubstringIgnoreCase(normalized, COMPLIANCE_KEYWORDS) {
        domains.push(<PharmaDomain>"COMPLIANCE");
    }
    if containsAnySubstringIgnoreCase(normalized, FINANCE_KEYWORDS) {
        domains.push(<PharmaDomain>"FINANCE");
    }

    if domains.length() == 0 {
        domains.push(<PharmaDomain>"CARE");
    }
    return domains;
}

// -----------------------------------------------------------------------------
// Transient LLM error detection: micro circuit-breaker at the agent layer
// -----------------------------------------------------------------------------

const string[] TRANSIENT_LLM_ERROR_MARKERS = [
    "rate limit", "tpm", "rpm", "timeout", "overloaded", "server error", "unavailable"
];

public isolated function isTransientLLMError(ai:Error err) returns boolean {
    return containsAnySubstringIgnoreCase(err.message(), TRANSIENT_LLM_ERROR_MARKERS);
}
