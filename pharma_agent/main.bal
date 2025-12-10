import ballerina/http;
import ballerina/log;
import ballerinax/ai;

listener http:Listener httpListener = new (HTTP_LISTENER_PORT);

// -----------------------------------------------------------------------------
// Helper response builders
// -----------------------------------------------------------------------------

function buildErrorResponse(int statusCode, ErrorBody body, string correlationId)
        returns http:Response {

    http:Response res = new;
    res.statusCode = statusCode;
    _ = res.setJsonPayload(body);

    if correlationId != "" {
        res.setHeader("X-Correlation-Id", correlationId);
    }
    return res;
}

function buildSuccessResponse(AgentResponse body, string correlationId)
        returns http:Response {

    http:Response res = new;
    res.statusCode = http:STATUS_OK;
    _ = res.setJsonPayload(body);

    if correlationId != "" {
        res.setHeader("X-Correlation-Id", correlationId);
    }
    return res;
}

// Extract or generate correlation id from header value.
function getOrGenerateCorrelationId(string? headerVal) returns string {
    if headerVal is string {
        string trimmed = headerVal.trim();
        if trimmed.length() > 0 {
            return trimmed;
        }
    }
    return generateCorrelationId();
}

// -----------------------------------------------------------------------------
// Generic single-agent handler (care / ops / compliance / finance)
// Demonstrates:
// - input validation
// - LLM transient-error retry (micro circuit breaker)
// - sticky sessions via sessionId
// -----------------------------------------------------------------------------

function handleAgentRequestSimple(
        ai:Agent agent,
        string agentName,
        string promptVersion,
        AgentRequest req,
        string correlationId,
        string endpointPath
) returns http:Response {

    if req.sessionId.trim().length() == 0 {
        ErrorBody badReqBody = {
            message: "Invalid request",
            details: "sessionId must not be empty"
        };
        log:printError("Agent request rejected: empty sessionId",
            'error = error("BAD_REQUEST"),
            'value = {
                "agentName": agentName,
                "endpointPath": endpointPath,
                "correlationId": correlationId
            });
        return buildErrorResponse(http:STATUS_BAD_REQUEST, badReqBody, correlationId);
    }

    if req.message.trim().length() == 0 {
        ErrorBody badReqBody = {
            message: "Agent execution failed.",
            details: "Message must not be empty."
        };

        log:printError("Agent request rejected: empty message",
            'error = error("BAD_REQUEST"),
            'value = {
                "agentName": agentName,
                "sessionId": req.sessionId,
                "endpointPath": endpointPath,
                "correlationId": correlationId
            });
        return buildErrorResponse(http:STATUS_BAD_REQUEST, badReqBody, correlationId);
    }

    string sessionId = req.sessionId;
    string message = req.message;

    log:printInfo("Pharma agent IN",
        'value = {
            "sessionId": sessionId,
            "userMessage": message,
            "agentName": agentName,
            "promptVersion": promptVersion,
            "endpointPath": endpointPath,
            "correlationId": correlationId
        }
    );

    // Sticky session via sessionId (LLM memory keyed per end-user / channel).
    string|ai:Error result = agent->run(message, sessionId = sessionId);

    // Optional single retry for transient LLM errors (rate limiting, overload, etc.).
    if result is ai:Error && isTransientLLMError(result) {
        log:printWarn("Transient LLM error detected, retrying once",
            'value = {
                "agentName": agentName,
                "sessionId": sessionId,
                "endpointPath": endpointPath,
                "correlationId": correlationId,
                "error": result.message()
            });
        result = agent->run(message, sessionId = sessionId);
    }

    if result is string {
        log:printInfo("Pharma agent OUT",
            'value = {
                "sessionId": sessionId,
                "agentName": agentName,
                "promptVersion": promptVersion,
                "endpointPath": endpointPath,
                "correlationId": correlationId,
                "httpStatus": http:STATUS_OK
            }
        );

        LlmUsage llmUsage = buildLlmUsage(
            OPENAI_MODEL.toString(),
            message,
            result
        );

        AgentResponse resp = {
            sessionId: sessionId,
            agentName: agentName,
            promptVersion: promptVersion,
            message: result,
            llm: llmUsage
        };
        return buildSuccessResponse(resp, correlationId);
    }



    // Error path from agent execution
    log:printError("Pharma agent execution failed",
        'error = result,
        'value = {
            "agentName": agentName,
            "sessionId": sessionId,
            "endpointPath": endpointPath,
            "correlationId": correlationId,
            "httpStatus": http:STATUS_INTERNAL_SERVER_ERROR
        });

    ErrorBody body = {
        message: "Agent execution failed",
        details: result.message()
    };

    return buildErrorResponse(http:STATUS_INTERNAL_SERVER_ERROR, body, correlationId);
}

// -----------------------------------------------------------------------------
// Omni agent orchestration + compliance overlay
// Patterns:
// - Domain routing via keywords
// - Parallel fan-out to specialized agents
// - Synthesis via omniAgent
// - Post-processing overlay for compliance hardening
// -----------------------------------------------------------------------------

function materializeSubAgentAnswer(
        string subAgentName,
        string|ai:Error result
) returns string {

    if result is string {
        return result;
    }

    log:printError("Sub-agent execution failed inside omni orchestration",
        'error = result,
        'value = {
            "subAgent": subAgentName
        });

    // Neutral placeholder in PT-BR.
    return string `O sub-agente ${subAgentName} teve um problema técnico ao responder.`;
}

function handleOmniRequest(
        AgentRequest req,
        string correlationId
) returns http:Response {

    if req.sessionId.trim().length() == 0 {
        ErrorBody badReqBody = {
            message: "Invalid request",
            details: "sessionId must not be empty"
        };
        log:printError("Omni agent request rejected: empty sessionId",
            'error = error("BAD_REQUEST"),
            'value = {
                "endpointPath": "/v1/omni/chat",
                "correlationId": correlationId
            });
        return buildErrorResponse(http:STATUS_BAD_REQUEST, badReqBody, correlationId);
    }

    if req.message.trim().length() == 0 {
        ErrorBody badReqBody = {
            message: "Agent execution failed.",
            details: "Message must not be empty."
        };

        log:printError("Omni agent request rejected: empty message",
            'error = error("BAD_REQUEST"),
            'value = {
                "sessionId": req.sessionId,
                "endpointPath": "/v1/omni/chat",
                "correlationId": correlationId
            });
        return buildErrorResponse(http:STATUS_BAD_REQUEST, badReqBody, correlationId);
    }

    string sessionId = req.sessionId;
    string userMessage = req.message;

    log:printInfo("Pharma omni agent IN",
        'value = {
            "sessionId": sessionId,
            "userMessage": userMessage,
            "endpointPath": "/v1/omni/chat",
            "correlationId": correlationId
        }
    );

    // 1) Detect relevant domains from the message.
    PharmaDomain[] domains = detectPharmaDomains(userMessage);

    boolean needsCare = false;
    boolean needsOps = false;
    boolean needsCompliance = false;
    boolean needsFinance = false;

    foreach PharmaDomain d in domains {
        if d == "CARE" {
            needsCare = true;
        } else if d == "OPS" {
            needsOps = true;
        } else if d == "COMPLIANCE" {
            needsCompliance = true;
        } else if d == "FINANCE" {
            needsFinance = true;
        }
    }

    // 2) Invoke selected sub-agents in parallel using futures.
    future<string|ai:Error>? careFuture = ();
    future<string|ai:Error>? opsFuture = ();
    future<string|ai:Error>? complianceFuture = ();
    future<string|ai:Error>? financeFuture = ();

    if needsCare {
        careFuture = start careAgent->run(userMessage, sessionId = sessionId);
    }
    if needsOps {
        opsFuture = start opsAgent->run(userMessage, sessionId = sessionId);
    }
    if needsCompliance {
        complianceFuture = start complianceAgent->run(userMessage, sessionId = sessionId);
    }
    if needsFinance {
        financeFuture = start financeAgent->run(userMessage, sessionId = sessionId);
    }

    string? careAnswer = ();
    string? opsAnswer = ();
    string? complianceAnswer = ();
    string? financeAnswer = ();

    if careFuture is future<string|ai:Error> {
        string|ai:Error careResult = wait careFuture;
        if careResult is ai:Error && isTransientLLMError(careResult) {
            log:printWarn("Transient LLM error in careAgent (omni), retrying once",
                'value = {
                    "agentName": PHARMA_CARE_AGENT_NAME,
                    "sessionId": sessionId,
                    "endpointPath": "/v1/omni/chat",
                    "correlationId": correlationId,
                    "error": careResult.message()
                });
            careResult = careAgent->run(userMessage, sessionId = sessionId);
        }
        careAnswer = materializeSubAgentAnswer("careAgent", careResult);
    }

    if opsFuture is future<string|ai:Error> {
        string|ai:Error opsResult = wait opsFuture;
        if opsResult is ai:Error && isTransientLLMError(opsResult) {
            log:printWarn("Transient LLM error in opsAgent (omni), retrying once",
                'value = {
                    "agentName": PHARMA_OPS_AGENT_NAME,
                    "sessionId": sessionId,
                    "endpointPath": "/v1/omni/chat",
                    "correlationId": correlationId,
                    "error": opsResult.message()
                });
            opsResult = opsAgent->run(userMessage, sessionId = sessionId);
        }
        opsAnswer = materializeSubAgentAnswer("opsAgent", opsResult);
    }

    if complianceFuture is future<string|ai:Error> {
        string|ai:Error complianceResult = wait complianceFuture;
        if complianceResult is ai:Error && isTransientLLMError(complianceResult) {
            log:printWarn("Transient LLM error in complianceAgent (omni), retrying once",
                'value = {
                    "agentName": PHARMA_COMPLIANCE_AGENT_NAME,
                    "sessionId": sessionId,
                    "endpointPath": "/v1/omni/chat",
                    "correlationId": correlationId,
                    "error": complianceResult.message()
                });
            complianceResult = complianceAgent->run(userMessage, sessionId = sessionId);
        }
        complianceAnswer = materializeSubAgentAnswer("complianceAgent", complianceResult);
    }

    if financeFuture is future<string|ai:Error> {
        string|ai:Error financeResult = wait financeFuture;
        if financeResult is ai:Error && isTransientLLMError(financeResult) {
            log:printWarn("Transient LLM error in financeAgent (omni), retrying once",
                'value = {
                    "agentName": PHARMA_FINANCE_AGENT_NAME,
                    "sessionId": sessionId,
                    "endpointPath": "/v1/omni/chat",
                    "correlationId": correlationId,
                    "error": financeResult.message()
                });
            financeResult = financeAgent->run(userMessage, sessionId = sessionId);
        }
        financeAnswer = materializeSubAgentAnswer("financeAgent", financeResult);
    }

    // Count how many domains we actually used.
    int usedDomainsCount = 0;
    if needsCare {
        usedDomainsCount += 1;
    }
    if needsOps {
        usedDomainsCount += 1;
    }
    if needsCompliance {
        usedDomainsCount += 1;
    }
    if needsFinance {
        usedDomainsCount += 1;
    }

    string omniInput = string `
Pergunta original do usuário:

${userMessage}
`;

    // For both single- and multi-domain cases we build the structured “multi-view” input,
    // with some sections possibly empty. This keeps the pattern uniform for the talk.
    if careAnswer is string && needsCare {
        omniInput = omniInput + string `

=== Resposta do agente de cuidado ao paciente (care) ===

${careAnswer}
`;
    }
    if opsAnswer is string && needsOps {
        omniInput = omniInput + string `

=== Resposta do agente de operações (ops) ===

${opsAnswer}
`;
    }
    if complianceAnswer is string && needsCompliance {
        omniInput = omniInput + string `

=== Resposta do agente de compliance (compliance) ===

${complianceAnswer}
`;
    }
    if financeAnswer is string && needsFinance {
        omniInput = omniInput + string `

=== Resposta do agente financeiro (finance) ===

${financeAnswer}
`;
    }

    // 3) Call omniAgent to synthesize a single answer.
    string|ai:Error omniResult = omniAgent->run(omniInput, sessionId = sessionId);

    if omniResult is ai:Error && isTransientLLMError(omniResult) {
        log:printWarn("Transient LLM error detected in omniAgent, retrying once",
            'value = {
                "agentName": PHARMA_OMNI_AGENT_NAME,
                "sessionId": sessionId,
                "endpointPath": "/v1/omni/chat",
                "correlationId": correlationId,
                "error": omniResult.message()
            });
        omniResult = omniAgent->run(omniInput, sessionId = sessionId);
    }

    string synthesizedAnswer;

    if omniResult is string {
        synthesizedAnswer = omniResult;
    } else {
        log:printError("Omni agent execution failed, falling back to combined raw view",
            'error = omniResult,
            'value = {
                "sessionId": sessionId,
                "endpointPath": "/v1/omni/chat",
                "correlationId": correlationId
            });

        synthesizedAnswer = string `
A seguir, trago a visão combinada dos sub-agentes:

=== Visão de cuidado ao paciente (care) ===

${careAnswer is string ? careAnswer : ""}

=== Visão de operações (ops) ===

${opsAnswer is string ? opsAnswer : ""}

=== Visão de compliance ===

${complianceAnswer is string ? complianceAnswer : ""}

=== Visão financeira ===

${financeAnswer is string ? financeAnswer : ""}
`;
    }

    // 4) Pass through compliance overlay agent to scrub advice / over-promises.
    string|ai:Error overlayResult = complianceOverlayAgent->run(
        synthesizedAnswer,
        sessionId = sessionId
    );

    if overlayResult is ai:Error && isTransientLLMError(overlayResult) {
        log:printWarn("Transient LLM error detected in complianceOverlayAgent, retrying once",
            'value = {
                "agentName": PHARMA_COMPLIANCE_OVERLAY_AGENT_NAME,
                "sessionId": sessionId,
                "endpointPath": "/v1/omni/chat",
                "correlationId": correlationId,
                "error": overlayResult.message()
            });
        overlayResult = complianceOverlayAgent->run(synthesizedAnswer, sessionId = sessionId);
    }

    string finalMessage;

    if overlayResult is string {
        finalMessage = overlayResult;
    } else {
        log:printError("Compliance overlay agent failed, returning synthesized answer without overlay",
            'error = overlayResult,
            'value = {
                "sessionId": sessionId,
                "endpointPath": "/v1/omni/chat",
                "correlationId": correlationId
            });
        finalMessage = synthesizedAnswer;
    }

    log:printInfo("Pharma omni agent OUT",
        'value = {
            "sessionId": sessionId,
            "endpointPath": "/v1/omni/chat",
            "correlationId": correlationId,
            "httpStatus": http:STATUS_OK,
            "domains": domains
        }
    );

    LlmUsage llmUsage = buildLlmUsage(
        OPENAI_MODEL.toString(),
        userMessage,
        finalMessage
    );

    AgentResponse resp = {
        sessionId: sessionId,
        agentName: PHARMA_OMNI_AGENT_NAME,
        promptVersion: PHARMA_OMNI_PROMPT_VERSION,
        message: finalMessage,
        llm: llmUsage
    };

    return buildSuccessResponse(resp, correlationId);
}


// -----------------------------------------------------------------------------
// Service endpoints
// -----------------------------------------------------------------------------

@http:ServiceConfig {
    // For the conference demo UI; in production, tighten this list.
    cors: {
        allowOrigins: ["*"],
        allowHeaders: ["content-type", "x-correlation-id"],
        allowMethods: ["POST", "GET", "OPTIONS"]
    }
}
service /v1 on httpListener {

    // Care agent: patient-care questions, prescriptions, availability at store.
    resource function post care/chat(
        @http:Payload AgentRequest req,
        @http:Header {name: "X-Correlation-Id"} string? correlationIdHeader
    ) returns http:Response {

        string correlationId = getOrGenerateCorrelationId(correlationIdHeader);
        return handleAgentRequestSimple(
            careAgent,
            PHARMA_CARE_AGENT_NAME,
            PHARMA_CARE_PROMPT_VERSION,
            req,
            correlationId,
            "/v1/care/chat"
        );
    }

    // Ops agent: inventory, orders, shipments.
    resource function post ops/chat(
        @http:Payload AgentRequest req,
        @http:Header {name: "X-Correlation-Id"} string? correlationIdHeader
    ) returns http:Response {

        string correlationId = getOrGenerateCorrelationId(correlationIdHeader);
        return handleAgentRequestSimple(
            opsAgent,
            PHARMA_OPS_AGENT_NAME,
            PHARMA_OPS_PROMPT_VERSION,
            req,
            correlationId,
            "/v1/ops/chat"
        );
    }

    // Compliance agent: regulatory / controlled-drug aspects from data.
    resource function post compliance/chat(
        @http:Payload AgentRequest req,
        @http:Header {name: "X-Correlation-Id"} string? correlationIdHeader
    ) returns http:Response {

        string correlationId = getOrGenerateCorrelationId(correlationIdHeader);
        return handleAgentRequestSimple(
            complianceAgent,
            PHARMA_COMPLIANCE_AGENT_NAME,
            PHARMA_COMPLIANCE_PROMPT_VERSION,
            req,
            correlationId,
            "/v1/compliance/chat"
        );
    }

    // Finance agent: tax async submissions explanations.
    resource function post finance/chat(
        @http:Payload AgentRequest req,
        @http:Header {name: "X-Correlation-Id"} string? correlationIdHeader
    ) returns http:Response {

        string correlationId = getOrGenerateCorrelationId(correlationIdHeader);
        return handleAgentRequestSimple(
            financeAgent,
            PHARMA_FINANCE_AGENT_NAME,
            PHARMA_FINANCE_PROMPT_VERSION,
            req,
            correlationId,
            "/v1/finance/chat"
        );
    }

    // Omni entry point: orchestrates care + ops + compliance + finance + overlay.
    resource function post omni/chat(
        @http:Payload AgentRequest req,
        @http:Header {name: "X-Correlation-Id"} string? correlationIdHeader
    ) returns http:Response {

        string correlationId = getOrGenerateCorrelationId(correlationIdHeader);
        return handleOmniRequest(req, correlationId);
    }

    // Liveness
    resource function get health() returns http:Response {
        http:Response res = new;
        res.statusCode = http:STATUS_OK;
        _ = res.setJsonPayload({ status: "UP", component: "Pharma-BI-Agents" });
        return res;
    }

    // Readiness
    resource function get health/ready() returns http:Response {
        http:Response res = new;
        _ = res.setJsonPayload({
            status: "UP",
            component: "Pharma-BI-Agents",
            dependencies: ["OpenAI", "MI/APIM-Backend"]
        });
        res.statusCode = http:STATUS_OK;
        return res;
    }
}
