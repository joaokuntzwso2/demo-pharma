import ballerinax/ai;

// -----------------------------------------------------------------------------
// Global configuration for Pharma Brazil Agentic APIs
// -----------------------------------------------------------------------------

// OAuth2 / bearer token for calling MI/APIM (optional).
// In production, this should come from a secure vault / KMS.
public configurable string BACKEND_ACCESS_TOKEN = "";

// LLM configuration (never log this key).
public configurable string OPENAI_API_KEY = ?;
public  ai:OPEN_AI_MODEL_NAMES OPENAI_MODEL = ai:GPT_4O;

// HTTP listener for the Agentic API service.
public configurable int HTTP_LISTENER_PORT = 8293;

// Base URL of the integration layer (WSO2 MI / APIM), NOT the Node backend directly.
public configurable string BACKEND_BASE_URL = ?;

// Backend HTTP client resilience (towards MI/APIM).
public configurable decimal BACKEND_HTTP_TIMEOUT_SECONDS = 3.0;
public configurable int BACKEND_HTTP_MAX_RETRIES = 1;
public configurable decimal BACKEND_HTTP_RETRY_INTERVAL_SECONDS = 0.5;
public configurable float BACKEND_HTTP_RETRY_BACKOFF_FACTOR = 2.0;
public configurable decimal BACKEND_HTTP_RETRY_MAX_WAIT_SECONDS = 2.0;
public configurable int[] BACKEND_HTTP_RETRY_STATUS_CODES = [500, 502, 503, 504];

// Agent observability names & prompt versions.
public configurable string PHARMA_CARE_AGENT_NAME = "PharmaBrazilCareAgent";
public const string PHARMA_CARE_PROMPT_VERSION = "pharma-care-v1.0.0";

public configurable string PHARMA_OPS_AGENT_NAME = "PharmaBrazilOpsAgent";
public const string PHARMA_OPS_PROMPT_VERSION = "pharma-ops-v1.0.0";

public configurable string PHARMA_COMPLIANCE_AGENT_NAME = "PharmaBrazilComplianceAgent";
public const string PHARMA_COMPLIANCE_PROMPT_VERSION = "pharma-compliance-v1.0.0";

public configurable string PHARMA_FINANCE_AGENT_NAME = "PharmaBrazilFinanceAgent";
public const string PHARMA_FINANCE_PROMPT_VERSION = "pharma-finance-v1.0.0";

public configurable string PHARMA_OMNI_AGENT_NAME = "PharmaBrazilOmniAgent";
public const string PHARMA_OMNI_PROMPT_VERSION = "pharma-omni-v1.0.0";

public configurable string PHARMA_COMPLIANCE_OVERLAY_AGENT_NAME = "PharmaBrazilComplianceOverlayAgent";
public const string PHARMA_COMPLIANCE_OVERLAY_PROMPT_VERSION = "pharma-compliance-overlay-v1.0.0";
