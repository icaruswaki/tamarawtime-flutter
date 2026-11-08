import { createClient } from "npm:@supabase/supabase-js@2";
import { createRoutesHandler } from "./provider.mjs";

Deno.serve(createRoutesHandler({
  key: Deno.env.get("GOOGLE_ROUTES_API_KEY"),
  allowedOrigins: (Deno.env.get("ALLOWED_ORIGINS") ?? "").split(",").map((v) => v.trim()),
  authenticate: async (authorization: string) => {
    const client = createClient(Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_PUBLISHABLE_KEY") ?? Deno.env.get("SUPABASE_ANON_KEY")!, {
        global: { headers: { Authorization: authorization } },
        auth: { persistSession: false, autoRefreshToken: false },
      });
    const { data: { user }, error } = await client.auth.getUser(authorization.slice(7));
    return error || !user ? null : client;
  },
  consumeQuota: async (client: ReturnType<typeof createClient>) => {
    // This atomic counter stores counts only and works across Edge instances.
    const { data, error } = await client.rpc("consume_route_request");
    if (error) throw new Error("quota_unavailable");
    return data;
  },
}));