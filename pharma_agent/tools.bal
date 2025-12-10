import ballerina/http;
import ballerina/log;
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
    // In production this MUST use proper TLS / mTLS.
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

// Build headers towards MI/APIM, including correlation and optional OAuth2.
isolated function buildBackendHeaders(string corrId) returns map<string|string[]> {
    map<string|string[]> headers = {
        "X-Correlation-Id": corrId,
        "x-fapi-interaction-id": corrId
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

// -----------------------------------------------------------------------------
// Agent tools (LLM-visible functions)
// -----------------------------------------------------------------------------

@ai:AgentTool {
    name: "GetPatientProfileTool",
    description: "Fetch patient profile and active prescriptions for a given patient id."
}
public isolated function getPatientProfileTool(PatientProfileInput input) returns json {
    string corrId = generateCorrelationIdForTool("GetPatientProfile");

    log:printInfo("GetPatientProfileTool starting",
        'value = {
            "correlationId": corrId,
            "patientIdMasked": maskPatientId(input.patientId)
        });

    string path = string `/customers/1.0.0/patient/${input.patientId}`;
    map<string|string[]> headers = buildBackendHeaders(corrId);

    http:Response|error respOrErr = backendClient->get(path, headers);
    if respOrErr is error {
        log:printError("GetPatientProfileTool HTTP call failed",
            'error = respOrErr,
            'value = { "correlationId": corrId });
        return buildClientErrorEnvelope("GetPatientProfileTool", respOrErr, corrId);
    }

    http:Response resp = respOrErr;

    json|error payloadOrErr = resp.getJsonPayload();
    if payloadOrErr is error {
        log:printError("GetPatientProfileTool invalid JSON payload",
            'error = payloadOrErr,
            'value = {
                "statusCode": resp.statusCode,
                "correlationId": corrId
            });
        return buildClientErrorEnvelope("GetPatientProfileTool", payloadOrErr, corrId);
    }

    json payload = payloadOrErr;

    log:printInfo("GetPatientProfileTool HTTP call completed",
        'value = {
            "statusCode": resp.statusCode,
            "correlationId": corrId
        });

    if resp.statusCode >= 200 && resp.statusCode < 300 {
        return buildBackendSuccessEnvelope("GetPatientProfileTool", resp.statusCode, payload, corrId);
    }

    boolean safeToRetry = isRetryableStatusCode(resp.statusCode);
    return buildBackendErrorEnvelope(
        "GetPatientProfileTool",
        safeToRetry ? "BACKEND_UNAVAILABLE" : "BACKEND_HTTP_ERROR",
        resp.statusCode,
        "Backend returned HTTP status " + resp.statusCode.toString(),
        safeToRetry,
        corrId
    );
}

@ai:AgentTool {
    name: "GetStoreInventoryTool",
    description: "Get inventory for a given store and SKU."
}
public isolated function getStoreInventoryTool(StoreInventoryInput input) returns json {
    string corrId = generateCorrelationIdForTool("GetStoreInventory");

    log:printInfo("GetStoreInventoryTool starting",
        'value = {
            "correlationId": corrId,
            "storeIdMasked": maskStoreId(input.storeId),
            "sku": input.sku
        });

    string path = string `/inventory/1.0.0/stores/${input.storeId}/items/${input.sku}`;
    map<string|string[]> headers = buildBackendHeaders(corrId);

    http:Response|error respOrErr = backendClient->get(path, headers);
    if respOrErr is error {
        log:printError("GetStoreInventoryTool HTTP call failed",
            'error = respOrErr,
            'value = { "correlationId": corrId });
        return buildClientErrorEnvelope("GetStoreInventoryTool", respOrErr, corrId);
    }

    http:Response resp = respOrErr;

    json|error payloadOrErr = resp.getJsonPayload();
    if payloadOrErr is error {
        log:printError("GetStoreInventoryTool invalid JSON payload",
            'error = payloadOrErr,
            'value = {
                "statusCode": resp.statusCode,
                "correlationId": corrId
            });
        return buildClientErrorEnvelope("GetStoreInventoryTool", payloadOrErr, corrId);
    }

    json payload = payloadOrErr;

    log:printInfo("GetStoreInventoryTool HTTP call completed",
        'value = {
            "statusCode": resp.statusCode,
            "correlationId": corrId
        });

    if resp.statusCode >= 200 && resp.statusCode < 300 {
        return buildBackendSuccessEnvelope("GetStoreInventoryTool", resp.statusCode, payload, corrId);
    }

    boolean safeToRetry = isRetryableStatusCode(resp.statusCode);
    return buildBackendErrorEnvelope(
        "GetStoreInventoryTool",
        safeToRetry ? "BACKEND_UNAVAILABLE" : "BACKEND_HTTP_ERROR",
        resp.statusCode,
        "Backend returned HTTP status " + resp.statusCode.toString(),
        safeToRetry,
        corrId
    );
}

@ai:AgentTool {
    name: "GetOrderStatusTool",
    description: "Get prescription order status for a given order id."
}
public isolated function getOrderStatusTool(OrderStatusInput input) returns json {
    string corrId = generateCorrelationIdForTool("GetOrderStatus");

    log:printInfo("GetOrderStatusTool starting",
        'value = {
            "correlationId": corrId,
            "orderIdMasked": maskOrderId(input.orderId)
        });

    string path = string `/orders/1.0.0/${input.orderId}`;
    map<string|string[]> headers = buildBackendHeaders(corrId);

    http:Response|error respOrErr = backendClient->get(path, headers);
    if respOrErr is error {
        log:printError("GetOrderStatusTool HTTP call failed",
            'error = respOrErr,
            'value = { "correlationId": corrId });
        return buildClientErrorEnvelope("GetOrderStatusTool", respOrErr, corrId);
    }

    http:Response resp = respOrErr;

    log:printInfo("GetOrderStatusTool HTTP call completed",
        'value = {
            "statusCode": resp.statusCode,
            "correlationId": corrId
        });

    if resp.statusCode < 200 || resp.statusCode >= 300 {
        boolean safeToRetry = isRetryableStatusCode(resp.statusCode);

        return buildBackendErrorEnvelope(
            "GetOrderStatusTool",
            safeToRetry ? "BACKEND_UNAVAILABLE" : "BACKEND_HTTP_ERROR",
            resp.statusCode,
            "Backend returned HTTP status " + resp.statusCode.toString(),
            safeToRetry,
            corrId
        );
    }

    // 2xx → agora sim parseia JSON
    json|error payloadOrErr = resp.getJsonPayload();
    if payloadOrErr is error {
        log:printError("GetOrderStatusTool invalid JSON payload",
            'error = payloadOrErr,
            'value = {
                "statusCode": resp.statusCode,
                "correlationId": corrId
            });
        return buildClientErrorEnvelope("GetOrderStatusTool", payloadOrErr, corrId);
    }

    json payload = payloadOrErr;

    return buildBackendSuccessEnvelope("GetOrderStatusTool", resp.statusCode, payload, corrId);
}


@ai:AgentTool {
    name: "GetShipmentStatusTool",
    description: "Get shipment status for a given shipment id."
}
public isolated function getShipmentStatusTool(ShipmentStatusInput input) returns json {
    string corrId = generateCorrelationIdForTool("GetShipmentStatus");

    log:printInfo("GetShipmentStatusTool starting",
        'value = {
            "correlationId": corrId,
            "shipmentIdMasked": maskShipmentId(input.shipmentId)
        });

    string path = string `/shipments/1.0.0/${input.shipmentId}`;
    map<string|string[]> headers = buildBackendHeaders(corrId);

    http:Response|error respOrErr = backendClient->get(path, headers);
    if respOrErr is error {
        log:printError("GetShipmentStatusTool HTTP call failed",
            'error = respOrErr,
            'value = { "correlationId": corrId });
        return buildClientErrorEnvelope("GetShipmentStatusTool", respOrErr, corrId);
    }

    http:Response resp = respOrErr;

    json|error payloadOrErr = resp.getJsonPayload();
    if payloadOrErr is error {
        log:printError("GetShipmentStatusTool invalid JSON payload",
            'error = payloadOrErr,
            'value = {
                "statusCode": resp.statusCode,
                "correlationId": corrId
            });
        return buildClientErrorEnvelope("GetShipmentStatusTool", payloadOrErr, corrId);
    }

    json payload = payloadOrErr;

    log:printInfo("GetShipmentStatusTool HTTP call completed",
        'value = {
            "statusCode": resp.statusCode,
            "correlationId": corrId
        });

    if resp.statusCode >= 200 && resp.statusCode < 300 {
        return buildBackendSuccessEnvelope("GetShipmentStatusTool", resp.statusCode, payload, corrId);
    }

    boolean safeToRetry = isRetryableStatusCode(resp.statusCode);
    return buildBackendErrorEnvelope(
        "GetShipmentStatusTool",
        safeToRetry ? "BACKEND_UNAVAILABLE" : "BACKEND_HTTP_ERROR",
        resp.statusCode,
        "Backend returned HTTP status " + resp.statusCode.toString(),
        safeToRetry,
        corrId
    );
}

@ai:AgentTool {
    name: "SubmitTaxReportTool",
    description: "Submit a tax report asynchronously (MI will queue to TaxReportStore)."
}
public isolated function submitTaxReportTool(TaxReportInput input) returns json {
    string corrId = generateCorrelationIdForTool("SubmitTaxReport");

    log:printInfo("SubmitTaxReportTool starting",
        'value = {
            "correlationId": corrId,
            "storeIdMasked": maskStoreId(input.storeId),
            "amountBr": input.amountBr.toString()
        });

    string path = "/finance/1.0.0/tax-report/async";
    map<string|string[]> headers = buildBackendHeaders(corrId);

    json body = {
        storeId: input.storeId,
        amountBr: input.amountBr
    };

    http:Response|error respOrErr = backendClient->post(path, body, headers);
    if respOrErr is error {
        log:printError("SubmitTaxReportTool HTTP call failed",
            'error = respOrErr,
            'value = { "correlationId": corrId });
        return buildClientErrorEnvelope("SubmitTaxReportTool", respOrErr, corrId);
    }

    http:Response resp = respOrErr;

    json|error payloadOrErr = resp.getJsonPayload();
    if payloadOrErr is error {
        log:printError("SubmitTaxReportTool invalid JSON payload",
            'error = payloadOrErr,
            'value = {
                "statusCode": resp.statusCode,
                "correlationId": corrId
            });
        return buildClientErrorEnvelope("SubmitTaxReportTool", payloadOrErr, corrId);
    }

    json payload = payloadOrErr;

    log:printInfo("SubmitTaxReportTool HTTP call completed",
        'value = {
            "statusCode": resp.statusCode,
            "correlationId": corrId
        });

    if resp.statusCode >= 200 && resp.statusCode < 300 {
        return buildBackendSuccessEnvelope("SubmitTaxReportTool", resp.statusCode, payload, corrId);
    }

    boolean safeToRetry = isRetryableStatusCode(resp.statusCode);
    return buildBackendErrorEnvelope(
        "SubmitTaxReportTool",
        safeToRetry ? "BACKEND_UNAVAILABLE" : "BACKEND_HTTP_ERROR",
        resp.statusCode,
        "Backend returned HTTP status " + resp.statusCode.toString(),
        safeToRetry,
        corrId
    );
}
