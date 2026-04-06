const THUNDER_VERIFY_BANK_URL = "https://api.thunder.in.th/v2/verify/bank";

export interface ThunderVerifySlipRequest {
  url: string;
  remark?: string;
  matchAmount?: number;
  checkDuplicate?: boolean;
  matchAccount?: boolean;
}

export interface ThunderMatchedAccount {
  bank?: {
    nameTh?: string;
    nameEn?: string;
    code?: string;
    shortCode?: string;
  };
  nameTh?: string;
  nameEn?: string;
  type?: string;
  bankNumber?: string;
}

export interface ThunderRawSlip {
  transRef?: string;
  date?: string;
  amount?: number;
  sender?: Record<string, unknown> | null;
  receiver?: Record<string, unknown> | null;
  [key: string]: unknown;
}

export interface ThunderVerifyBankData {
  remark?: string;
  isDuplicate: boolean;
  matchedAccount: ThunderMatchedAccount | null;
  amountInOrder?: number;
  amountInSlip: number;
  isAmountMatched?: boolean;
  rawSlip: ThunderRawSlip;
  [key: string]: unknown;
}

interface ThunderVerifySuccessResponse {
  success: true;
  data: ThunderVerifyBankData;
  message?: string;
}

interface ThunderVerifyErrorResponse {
  success: false;
  error?: {
    code?: string;
    message?: string;
  };
  message?: string;
}

function asRecord(value: unknown): Record<string, unknown> {
  if (typeof value === "object" && value !== null) {
    return value as Record<string, unknown>;
  }
  return {};
}

function asTrimmedString(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function asOptionalNumber(value: unknown): number | undefined {
  return typeof value === "number" && Number.isFinite(value) ? value : undefined;
}

function asBoolean(value: unknown, fallback = false): boolean {
  return typeof value === "boolean" ? value : fallback;
}

function normalizeErrorCode(rawCode: unknown): string {
  const code = asTrimmedString(rawCode);
  return code.length > 0 ? code.toUpperCase() : "THUNDER_ERROR";
}

export class ThunderApiError extends Error {
  code: string;
  httpStatus: number;
  rawBody: unknown;

  constructor(code: string, message: string, httpStatus: number, rawBody: unknown) {
    super(message);
    this.name = "ThunderApiError";
    this.code = code;
    this.httpStatus = httpStatus;
    this.rawBody = rawBody;
  }
}

function parseVerifyBankData(raw: unknown): ThunderVerifyBankData {
  const record = asRecord(raw);
  return {
    remark: asTrimmedString(record["remark"]) || undefined,
    isDuplicate: asBoolean(record["isDuplicate"]),
    matchedAccount: (record["matchedAccount"] &&
      typeof record["matchedAccount"] === "object") ?
      (record["matchedAccount"] as ThunderMatchedAccount) :
      null,
    amountInOrder: asOptionalNumber(record["amountInOrder"]),
    amountInSlip: asOptionalNumber(record["amountInSlip"]) ?? 0,
    isAmountMatched: typeof record["isAmountMatched"] === "boolean" ?
      (record["isAmountMatched"] as boolean) :
      undefined,
    rawSlip: (record["rawSlip"] &&
      typeof record["rawSlip"] === "object") ?
      (record["rawSlip"] as ThunderRawSlip) :
      {},
    ...record,
  };
}

export async function verifySlipByUrl(
  apiKey: string,
  request: ThunderVerifySlipRequest
): Promise<ThunderVerifyBankData> {
  const response = await fetch(THUNDER_VERIFY_BANK_URL, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(request),
  });

  let body: unknown = null;
  try {
    body = await response.json();
  } catch {
    body = null;
  }

  if (!response.ok) {
    const errorRecord = asRecord(body);
    const errorBlock = asRecord(errorRecord["error"]);
    const code = normalizeErrorCode(errorBlock["code"] ?? errorRecord["code"]);
    const message =
      asTrimmedString(errorBlock["message"]) ||
      asTrimmedString(errorRecord["message"]) ||
      `Thunder API returned HTTP ${response.status}.`;
    throw new ThunderApiError(code, message, response.status, body);
  }

  const payload = asRecord(body);

  if (payload["success"] !== true) {
    const errorBlock = asRecord(payload["error"]);
    const code = normalizeErrorCode(errorBlock["code"] ?? payload["message"]);
    const message =
      asTrimmedString(errorBlock["message"]) ||
      asTrimmedString(payload["message"]) ||
      "Thunder API did not confirm the slip.";
    throw new ThunderApiError(code, message, response.status, body);
  }

  return parseVerifyBankData(payload["data"]);
}
