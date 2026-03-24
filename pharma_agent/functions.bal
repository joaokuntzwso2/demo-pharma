import ballerina/uuid;
import ballerina/lang.'string as string;
import ballerinax/ai;

// -----------------------------------------------------------------------------
// Correlation IDs & safe logging helpers
// -----------------------------------------------------------------------------

public isolated function generateCorrelationId() returns string {
    return "corr-" + uuid:createType4AsString();
}

public isolated function generateCorrelationIdForTool(string toolName) returns string {
    return string `corr-${toolName}-${uuid:createType4AsString()}`;
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

// ASCII case-insensitive substring check.
// This is intentionally simple and robust for mixed English/PT-BR prompts.
isolated function containsAnySubstringIgnoreCase(
    string sourceString,
    readonly & string[] markers
) returns boolean {
    if sourceString.length() == 0 {
        return false;
    }

    string normalized = sourceString.toLowerAscii();

    foreach string marker in markers {
        string m = marker.toLowerAscii();
        if string:includes(normalized, m) {
            return true;
        }
    }
    return false;
}

// Keyword dictionaries for routing.
// Include both English and Portuguese for robustness, even though the final
// agent responses are expected to be in English.
const string[] CARE_KEYWORDS = [
    "patient", "patients", "profile", "crm",
    "prescription", "prescriptions", "refill", "refillable", "renewal",
    "medication", "medicine", "drug", "drugs",
    "dose", "dosage", "pharmacy", "store",
    "paciente", "pacientes", "receita", "receitas", "prescrição", "prescrições",
    "refil", "renovação", "remédio", "remedios", "remédios",
    "medicação", "medicacao", "dose", "dosagem", "farmácia", "farmacia", "loja"
];

const string[] OPS_KEYWORDS = [
    "inventory", "stock", "availability", "available",
    "store", "stores", "dc", "distribution center",
    "order", "orders", "shipment", "shipments", "dispatch",
    "fulfillment", "replenishment", "replenish", "supply chain",
    "estoque", "inventário", "inventario", "disponível", "disponivel",
    "loja", "lojas", "cd", "centro de distribuição", "centro de distribuicao",
    "pedido", "pedidos", "ordem", "ordens", "remessa", "remessas",
    "expedição", "expedicao", "reposição", "reposicao", "replenishment"
];

const string[] COMPLIANCE_KEYWORDS = [
    "compliance", "regulatory", "regulation", "regulated",
    "controlled", "controlled drug", "controlled medication",
    "cold chain", "audit", "documentation", "document",
    "prescription validity", "valid prescription", "traceability",
    "controlado", "medicamento controlado", "tarja preta",
    "boas práticas", "boas praticas", "conformidade", "anvisa",
    "regulatório", "regulatorio", "auditoria", "documentação", "documentacao",
    "prescrição válida", "prescricao valida", "rastreabilidade"
];

const string[] FINANCE_KEYWORDS = [
    "finance", "financial", "tax", "taxes", "tax report",
    "invoice", "electronic invoice", "fiscal", "icms", "nf-e",
    "tribute", "revenue",
    "nota fiscal", "nf-e", "icms", "imposto", "impostos",
    "taxa", "tributo", "tributos", "fiscal", "financeiro", "relatório fiscal", "relatorio fiscal"
];

// Detect one or more domains from the user message.
// Default to CARE for safety when nothing matches.
public isolated function detectPharmaDomains(string userMessage) returns PharmaDomain[] {
    PharmaDomain[] domains = [];

    if containsAnySubstringIgnoreCase(userMessage, CARE_KEYWORDS) {
        domains.push(<PharmaDomain>"CARE");
    }
    if containsAnySubstringIgnoreCase(userMessage, OPS_KEYWORDS) {
        domains.push(<PharmaDomain>"OPS");
    }
    if containsAnySubstringIgnoreCase(userMessage, COMPLIANCE_KEYWORDS) {
        domains.push(<PharmaDomain>"COMPLIANCE");
    }
    if containsAnySubstringIgnoreCase(userMessage, FINANCE_KEYWORDS) {
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
    "rate limit", "tpm", "rpm", "timeout", "timed out",
    "overloaded", "server error", "unavailable",
    "temporarily unavailable", "try again later", "gateway timeout"
];

public isolated function isTransientLLMError(ai:Error err) returns boolean {
    return containsAnySubstringIgnoreCase(err.message(), TRANSIENT_LLM_ERROR_MARKERS);
}

// -----------------------------------------------------------------------------
// LLM usage estimation helpers for APIM AI Vendor integration
// -----------------------------------------------------------------------------

// Simple token estimator (approx): chars / 4.
public isolated function estimateTokenCount(string text) returns int {
    int charLen = text.length();

    if charLen == 0 {
        return 0;
    }

    int approxCharsPerToken = 4;
    int tokens = charLen / approxCharsPerToken;
    if charLen % approxCharsPerToken != 0 {
        tokens += 1;
    }

    return tokens;
}

// Build the LlmUsage record based on prompt + completion texts.
public isolated function buildLlmUsage(
    string responseModel,
    string promptText,
    string completionText,
    int? remainingTokenCount = ()
) returns LlmUsage {

    int promptTokens = estimateTokenCount(promptText);
    int completionTokens = estimateTokenCount(completionText);
    int totalTokens = promptTokens + completionTokens;

    if remainingTokenCount is int {
        return {
            responseModel: responseModel,
            promptTokenCount: promptTokens,
            completionTokenCount: completionTokens,
            totalTokenCount: totalTokens,
            remainingTokenCount: remainingTokenCount
        };
    }

    return {
        responseModel: responseModel,
        promptTokenCount: promptTokens,
        completionTokenCount: completionTokens,
        totalTokenCount: totalTokens
    };
}