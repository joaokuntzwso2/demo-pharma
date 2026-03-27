import ballerina/http;
import ballerinax/ai;

// -----------------------------------------------------------------------------
// HTTP client to MI/APIM (integration layer)
//
// - Timeouts + retries are configured via config.bal
// - Circuit breaking / suspension is implemented in MI endpoints.
// - We also send correlation headers for full traceability.
// -----------------------------------------------------------------------------

final http:Client backendClient = checkpanic new (BACKEND_BASE_URL, {
    timeout: BACKEND_HTTP_TIMEOUT_SECONDS,
    retryConfig: {
        count: BACKEND_HTTP_MAX_RETRIES,
        interval: BACKEND_HTTP_RETRY_INTERVAL_SECONDS,
        backOffFactor: BACKEND_HTTP_RETRY_BACKOFF_FACTOR,
        maxWaitInterval: BACKEND_HTTP_RETRY_MAX_WAIT_SECONDS,
        statusCodes: BACKEND_HTTP_RETRY_STATUS_CODES
    },
    secureSocket: {
        enable: false
    }
});

// -----------------------------------------------------------------------------
// Standardized envelope builder for tools
// -----------------------------------------------------------------------------

isolated function buildBackendSuccessEnvelope(
    string toolName,
    int httpStatus,
    json result,
    string correlationId
) returns json {
    return {
        tool: toolName,
        status: "SUCCESS",
        errorCode: "",
        httpStatus: httpStatus,
        safeToRetry: false,
        message: "",
        result: result,
        correlationId: correlationId
    };
}

isolated function buildBackendErrorEnvelope(
    string toolName,
    string errorCode,
    int httpStatus,
    string message,
    boolean safeToRetry,
    string correlationId
) returns json {
    return {
        tool: toolName,
        status: "ERROR",
        errorCode: errorCode,
        httpStatus: httpStatus,
        safeToRetry: safeToRetry,
        message: message,
        result: (),
        correlationId: correlationId
    };
}

// Client-side failures (network, parse, etc.) are normalized for the LLM.
public isolated function buildClientErrorEnvelope(
    string toolName,
    error err,
    string correlationId
) returns json {
    return buildBackendErrorEnvelope(
        toolName,
        "BACKEND_CLIENT_ERROR",
        500,
        err.message(),
        false,
        correlationId
    );
}

// Build headers towards MI/APIM, including correlation, agent identity,
// interception metadata, and optional OAuth2.
isolated function buildBackendHeaders(
    string corrId,
    string agentName,
    string agentDomain,
    string agentTool
) returns map<string|string[]> {
    map<string|string[]> headers = {
        "X-Correlation-Id": corrId,
        "x-fapi-interaction-id": corrId,
        "X-Agent-Name": agentName,
        "X-Agent-Domain": agentDomain,
        "X-Agent-Tool": agentTool,
        "X-Agent-Intercepted": "true"
    };

    if BACKEND_ACCESS_TOKEN != "" {
        headers["Authorization"] = string `Bearer ${BACKEND_ACCESS_TOKEN}`;
    }
    return headers;
}

// Decide if an HTTP status is transient (safe for LLM to retry once).
isolated function isRetryableStatusCode(int statusCode) returns boolean {
    return statusCode == 502 || statusCode == 503 || statusCode == 504;
}

// Best-effort JSON extraction:
// - If there is no payload / empty payload, return ()
isolated function tryGetJson(http:Response resp) returns json? {
    json|error payloadOrErr = resp.getJsonPayload();
    if payloadOrErr is error {
        return ();
    }
    return payloadOrErr;
}

// Normalize backend HTTP error codes for the LLM envelope.
isolated function classifyHttpErrorCode(int statusCode) returns string {
    if isRetryableStatusCode(statusCode) {
        return "BACKEND_UNAVAILABLE";
    }
    if statusCode == 404 {
        return "NOT_FOUND";
    }
    return "BACKEND_HTTP_ERROR";
}

isolated function buildHttpErrorEnvelope(
    string toolName,
    int statusCode,
    string correlationId,
    json? payload = ()
) returns json {

    boolean safeToRetry = isRetryableStatusCode(statusCode);
    string msg = "Backend returned HTTP status " + statusCode.toString();

    if payload is map<anydata> {
        anydata? maybeMsg = payload["message"];
        if maybeMsg is string {
            string trimmed = maybeMsg.trim();
            if trimmed.length() > 0 {
                msg = trimmed;
            }
        }
    }

    return buildBackendErrorEnvelope(
        toolName,
        classifyHttpErrorCode(statusCode),
        statusCode,
        msg,
        safeToRetry,
        correlationId
    );
}

// -----------------------------------------------------------------------------
// Shared backend execution helpers
// -----------------------------------------------------------------------------

isolated function executeBackendGet(
    string toolName,
    string agentName,
    string agentDomain,
    string path,
    string corrId
) returns json {
    map<string|string[]> headers = buildBackendHeaders(corrId, agentName, agentDomain, toolName);

    http:Response|error respOrErr = backendClient->get(path, headers);
    if respOrErr is error {
        return buildClientErrorEnvelope(toolName, respOrErr, corrId);
    }

    http:Response resp = respOrErr;

    if resp.statusCode < 200 || resp.statusCode >= 300 {
        json? errPayload = tryGetJson(resp);
        return buildHttpErrorEnvelope(toolName, resp.statusCode, corrId, errPayload);
    }

    json? payload = tryGetJson(resp);
    if payload is () {
        return buildClientErrorEnvelope(toolName, error("EMPTY_JSON_PAYLOAD"), corrId);
    }

    return buildBackendSuccessEnvelope(toolName, resp.statusCode, payload, corrId);
}

isolated function executeBackendPost(
    string toolName,
    string agentName,
    string agentDomain,
    string path,
    json body,
    string corrId
) returns json {
    map<string|string[]> headers = buildBackendHeaders(corrId, agentName, agentDomain, toolName);

    http:Response|error respOrErr = backendClient->post(path, body, headers);
    if respOrErr is error {
        return buildClientErrorEnvelope(toolName, respOrErr, corrId);
    }

    http:Response resp = respOrErr;

    if resp.statusCode < 200 || resp.statusCode >= 300 {
        json? errPayload = tryGetJson(resp);
        return buildHttpErrorEnvelope(toolName, resp.statusCode, corrId, errPayload);
    }

    json? payload = tryGetJson(resp);
    if payload is () {
        return buildClientErrorEnvelope(toolName, error("EMPTY_JSON_PAYLOAD"), corrId);
    }

    return buildBackendSuccessEnvelope(toolName, resp.statusCode, payload, corrId);
}

// -----------------------------------------------------------------------------
// Agent-specific tools (LLM-visible functions)
// -----------------------------------------------------------------------------

@ai:AgentTool {
    name: "CareGetPatientProfileTool",
    description: "Fetch patient profile and active prescriptions for a given patient id."
}
public isolated function careGetPatientProfileTool(PatientProfileInput input) returns json {
    string corrId = generateCorrelationIdForTool("CareGetPatientProfile");
    string path = string `/customers/1.0.0/patient/${input.patientId}`;
    return executeBackendGet(
        "CareGetPatientProfileTool",
        PHARMA_CARE_AGENT_NAME,
        "CARE",
        path,
        corrId
    );
}

@ai:AgentTool {
    name: "CareGetStoreInventoryTool",
    description: "Get inventory for a given store and SKU."
}
public isolated function careGetStoreInventoryTool(StoreInventoryInput input) returns json {
    string corrId = generateCorrelationIdForTool("CareGetStoreInventory");
    string path = string `/inventory/1.0.0/stores/${input.storeId}/items/${input.sku}`;
    return executeBackendGet(
        "CareGetStoreInventoryTool",
        PHARMA_CARE_AGENT_NAME,
        "CARE",
        path,
        corrId
    );
}

@ai:AgentTool {
    name: "OpsGetStoreInventoryTool",
    description: "Get inventory for a given store and SKU."
}
public isolated function opsGetStoreInventoryTool(StoreInventoryInput input) returns json {
    string corrId = generateCorrelationIdForTool("OpsGetStoreInventory");
    string path = string `/inventory/1.0.0/stores/${input.storeId}/items/${input.sku}`;
    return executeBackendGet(
        "OpsGetStoreInventoryTool",
        PHARMA_OPS_AGENT_NAME,
        "OPS",
        path,
        corrId
    );
}

@ai:AgentTool {
    name: "OpsGetOrderStatusTool",
    description: "Get prescription order status for a given order id."
}
public isolated function opsGetOrderStatusTool(OrderStatusInput input) returns json {
    string corrId = generateCorrelationIdForTool("OpsGetOrderStatus");
    string path = string `/orders/1.0.0?orderId=${input.orderId}`;
    return executeBackendGet(
        "OpsGetOrderStatusTool",
        PHARMA_OPS_AGENT_NAME,
        "OPS",
        path,
        corrId
    );
}

@ai:AgentTool {
    name: "OpsGetShipmentStatusTool",
    description: "Get shipment status for a given shipment id."
}
public isolated function opsGetShipmentStatusTool(ShipmentStatusInput input) returns json {
    string corrId = generateCorrelationIdForTool("OpsGetShipmentStatus");
    string path = string `/shipments/1.0.0?shipmentId=${input.shipmentId}`;
    return executeBackendGet(
        "OpsGetShipmentStatusTool",
        PHARMA_OPS_AGENT_NAME,
        "OPS",
        path,
        corrId
    );
}

@ai:AgentTool {
    name: "ComplianceGetPatientProfileTool",
    description: "Fetch patient profile and active prescriptions for a given patient id."
}
public isolated function complianceGetPatientProfileTool(PatientProfileInput input) returns json {
    string corrId = generateCorrelationIdForTool("ComplianceGetPatientProfile");
    string path = string `/customers/1.0.0/patient/${input.patientId}`;
    return executeBackendGet(
        "ComplianceGetPatientProfileTool",
        PHARMA_COMPLIANCE_AGENT_NAME,
        "COMPLIANCE",
        path,
        corrId
    );
}

@ai:AgentTool {
    name: "ComplianceGetStoreInventoryTool",
    description: "Get inventory for a given store and SKU."
}
public isolated function complianceGetStoreInventoryTool(StoreInventoryInput input) returns json {
    string corrId = generateCorrelationIdForTool("ComplianceGetStoreInventory");
    string path = string `/inventory/1.0.0/stores/${input.storeId}/items/${input.sku}`;
    return executeBackendGet(
        "ComplianceGetStoreInventoryTool",
        PHARMA_COMPLIANCE_AGENT_NAME,
        "COMPLIANCE",
        path,
        corrId
    );
}

@ai:AgentTool {
    name: "ComplianceGetOrderStatusTool",
    description: "Get prescription order status for a given order id."
}
public isolated function complianceGetOrderStatusTool(OrderStatusInput input) returns json {
    string corrId = generateCorrelationIdForTool("ComplianceGetOrderStatus");
    string path = string `/orders/1.0.0?orderId=${input.orderId}`;
    return executeBackendGet(
        "ComplianceGetOrderStatusTool",
        PHARMA_COMPLIANCE_AGENT_NAME,
        "COMPLIANCE",
        path,
        corrId
    );
}

@ai:AgentTool {
    name: "ComplianceGetShipmentStatusTool",
    description: "Get shipment status for a given shipment id."
}
public isolated function complianceGetShipmentStatusTool(ShipmentStatusInput input) returns json {
    string corrId = generateCorrelationIdForTool("ComplianceGetShipmentStatus");
    string path = string `/shipments/1.0.0?shipmentId=${input.shipmentId}`;
    return executeBackendGet(
        "ComplianceGetShipmentStatusTool",
        PHARMA_COMPLIANCE_AGENT_NAME,
        "COMPLIANCE",
        path,
        corrId
    );
}

@ai:AgentTool {
    name: "FinanceSubmitTaxReportTool",
    description: "Submit a tax report asynchronously (MI will queue to TaxReportStore)."
}
public isolated function financeSubmitTaxReportTool(TaxReportInput input) returns json {
    string corrId = generateCorrelationIdForTool("FinanceSubmitTaxReport");

    json body = {
        storeId: input.storeId,
        amountBr: input.amountBr
    };

    return executeBackendPost(
        "FinanceSubmitTaxReportTool",
        PHARMA_FINANCE_AGENT_NAME,
        "FINANCE",
        "/finance/1.0.0/tax-report/async",
        body,
        corrId
    );
}