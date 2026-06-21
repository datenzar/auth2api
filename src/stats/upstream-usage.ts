import { ProviderId, TokenData } from "../auth/types";

export interface UsageWindowInsight {
  window: "5-Hour" | "7-Day" | "Premium" | "Chat" | "N/A";
  usedPercent: number | null;
  timeLeft: string;
  resetsAt: string | null;
  remainingSeconds: number | null;
  windowSeconds: number | null;
}

export interface AccountUsageInsight {
  provider: ProviderId;
  email: string;
  planType?: string;
  status: "ok" | "unsupported" | "token_missing" | "request_failed";
  error?: string;
  windows: UsageWindowInsight[];
}

function unixSeconds(value: unknown): number | null {
  const n = typeof value === "number" ? value : Number(value);
  return Number.isFinite(n) && n > 0 ? Math.floor(n) : null;
}

function isoSeconds(value: unknown): number | null {
  if (typeof value !== "string" || !value) return null;
  const normalized = value.replace(/\.\d+/, "").replace(/\+00:00$/, "Z");
  const ms = Date.parse(normalized);
  return Number.isFinite(ms) ? Math.floor(ms / 1000) : null;
}

function fmtTimestamp(seconds: number | null): string | null {
  if (!seconds) return null;
  return new Date(seconds * 1000).toISOString();
}

function remaining(seconds: number | null, nowSeconds: number): number | null {
  if (!seconds) return null;
  return Math.max(0, seconds - nowSeconds);
}

function fmtRemaining(seconds: number | null): string {
  if (seconds == null) return "-";
  if (seconds <= 0) return "now";
  if (seconds < 3600) return `in ${Math.floor(seconds / 60)}m`;
  if (seconds < 86400) {
    return `in ${Math.floor(seconds / 3600)}h ${Math.floor((seconds % 3600) / 60)}m`;
  }
  return `in ${Math.floor(seconds / 86400)}d ${Math.floor((seconds % 86400) / 3600)}h`;
}

function percent(value: unknown): number | null {
  const n = typeof value === "number" ? value : Number(value);
  if (!Number.isFinite(n)) return null;
  return Math.max(0, Math.min(100, n));
}

async function fetchJson(url: string, init: RequestInit): Promise<any | null> {
  try {
    const response = await fetch(url, init);
    if (!response.ok) return null;
    return response.json();
  } catch {
    return null;
  }
}

function windowInsight(
  window: UsageWindowInsight["window"],
  usedPercent: unknown,
  resetSeconds: number | null,
  windowSeconds: number,
  nowSeconds: number,
): UsageWindowInsight {
  const left = remaining(resetSeconds, nowSeconds);
  return {
    window,
    usedPercent: percent(usedPercent),
    timeLeft: fmtRemaining(left),
    resetsAt: fmtTimestamp(resetSeconds),
    remainingSeconds: left,
    windowSeconds,
  };
}

async function getAnthropicUsage(
  token: TokenData,
): Promise<AccountUsageInsight> {
  if (!token.accessToken) {
    return {
      provider: "anthropic",
      email: token.email,
      status: "token_missing",
      windows: [],
    };
  }
  const now = Math.floor(Date.now() / 1000);
  const data = await fetchJson("https://api.anthropic.com/api/oauth/usage", {
    headers: {
      Accept: "application/json, text/plain, */*",
      "Content-Type": "application/json",
      "User-Agent": "claude-code/2.0.32",
      Authorization: `Bearer ${token.accessToken}`,
      "anthropic-beta": "oauth-2025-04-20",
    },
  });
  if (!data) {
    return {
      provider: "anthropic",
      email: token.email,
      status: "request_failed",
      error: "Usage request failed",
      windows: [],
    };
  }
  return {
    provider: "anthropic",
    email: token.email,
    status: "ok",
    windows: [
      windowInsight(
        "5-Hour",
        data.five_hour?.utilization ?? 0,
        isoSeconds(data.five_hour?.resets_at),
        18_000,
        now,
      ),
      windowInsight(
        "7-Day",
        data.seven_day?.utilization ?? 0,
        isoSeconds(data.seven_day?.resets_at),
        604_800,
        now,
      ),
    ],
  };
}

async function getCodexUsage(token: TokenData): Promise<AccountUsageInsight> {
  if (!token.accessToken) {
    return {
      provider: "codex",
      email: token.email,
      planType: token.planType,
      status: "token_missing",
      windows: [],
    };
  }
  const now = Math.floor(Date.now() / 1000);
  const data = await fetchJson("https://chatgpt.com/backend-api/wham/usage", {
    headers: { Authorization: `Bearer ${token.accessToken}` },
  });
  if (!data) {
    return {
      provider: "codex",
      email: token.email,
      planType: token.planType,
      status: "request_failed",
      error: "Usage request failed",
      windows: [],
    };
  }
  const primary = data.rate_limit?.primary_window;
  const secondary = data.rate_limit?.secondary_window;
  const windows = [
    windowInsight(
      "5-Hour",
      primary?.used_percent ?? 0,
      unixSeconds(primary?.reset_at),
      primary?.limit_window_seconds ?? 18_000,
      now,
    ),
  ];
  if (secondary) {
    windows.push(
      windowInsight(
        "7-Day",
        secondary.used_percent ?? 0,
        unixSeconds(secondary.reset_at),
        secondary.limit_window_seconds ?? 604_800,
        now,
      ),
    );
  } else {
    windows.push({
      window: "7-Day",
      usedPercent: null,
      timeLeft: "-",
      resetsAt: null,
      remainingSeconds: null,
      windowSeconds: null,
    });
  }
  return {
    provider: "codex",
    email: token.email,
    planType: token.planType,
    status: "ok",
    windows,
  };
}

export async function getAccountUsageInsight(
  token: TokenData,
): Promise<AccountUsageInsight> {
  if (token.provider === "anthropic" || !token.provider)
    return getAnthropicUsage(token);
  if (token.provider === "codex") return getCodexUsage(token);
  return {
    provider: "cursor",
    email: token.email,
    status: "unsupported",
    error: "Cursor does not expose a compatible quota usage endpoint yet.",
    windows: [],
  };
}
