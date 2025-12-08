// -----------------------------------------------------------------------------
// Domain primitives
// -----------------------------------------------------------------------------

public type PatientId string;
public type StoreId string;
public type OrderId string;
public type ShipmentId string;

// Domains for omni routing
public type PharmaDomain "CARE"|"OPS"|"COMPLIANCE"|"FINANCE";

// -----------------------------------------------------------------------------
// HTTP request/response shapes
// -----------------------------------------------------------------------------

public type AgentRequest record {|
    // Session id is the "sticky key" for LLM memory.
    string sessionId;
    string message;
|};

public type AgentResponse record {|
    string sessionId;
    string agentName;
    string promptVersion;
    string message;
|};

public type ErrorBody record {|
    string message;
    string? details?;
|};

// -----------------------------------------------------------------------------
// Tool inputs
// -----------------------------------------------------------------------------

public type PatientProfileInput record {|
    PatientId patientId;
|};

public type StoreInventoryInput record {|
    StoreId storeId;
    string sku;
|};

public type OrderStatusInput record {|
    OrderId orderId;
|};

public type ShipmentStatusInput record {|
    ShipmentId shipmentId;
|};

public type TaxReportInput record {|
    StoreId storeId;
    decimal amountBr;
|};
