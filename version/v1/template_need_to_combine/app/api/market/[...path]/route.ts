import { NextRequest } from "next/server";

const API_BASE = "http://127.0.0.1:8765/api/market";

async function proxyMarketApi(request: NextRequest, context: { params: Promise<{ path: string[] }> }) {
  const { path } = await context.params;
  const target = new URL(`${API_BASE}/${path.join("/")}`);
  request.nextUrl.searchParams.forEach((value, key) => {
    target.searchParams.set(key, value);
  });

  let response: Response;
  try {
    response = await fetch(target, {
      method: request.method,
      headers: {
        accept: request.headers.get("accept") || "application/json",
      },
      cache: "no-store",
    });
  } catch {
    return Response.json(
      {
        error: "market production API unavailable",
        detail: "Start backend/market_model_v3_production_signal/run_server.py on http://127.0.0.1:8765.",
      },
      { status: 503 },
    );
  }

  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers: {
      "content-type": response.headers.get("content-type") || "application/json",
    },
  });
}

export const GET = proxyMarketApi;
