import { createClient } from "npm:@supabase/supabase-js@2";

const origins = new Set(["http://localhost:8081", "http://127.0.0.1:8081", "http://localhost:8080", "http://127.0.0.1:8080"]);
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const avatars = new Set(["fox", "owl", "bear", "lynx", "dolphin", "rabbit"]);
const encoder = new TextEncoder();
const hex = (bytes: Uint8Array) => Array.from(bytes, b => b.toString(16).padStart(2,"0")).join("");
const messages: Record<string, string> = {
  PARENT_LOCKED: "A área dos pais está bloqueada. Introduz o PIN parental.",
  AUTH_REQUIRED: "A tua sessão terminou. Entra novamente na conta.",
  EMAIL_NOT_CONFIRMED: "Confirma o teu e-mail antes de continuar.",
  ADULT_SETUP_REQUIRED: "Configura o PIN parental antes de adicionar crianças.",
  FAMILY_NOT_FOUND: "Esta família não está disponível para a tua conta.",
  INVALID_PROFILE: "Verifica a alcunha, o avatar, o ano escolar e o PIN de 4 dígitos.",
  INVALID_REQUEST: "O pedido é inválido.",
  REQUEST_CONFLICT: "Este pedido já foi usado com outros dados. Volta à lista de perfis antes de continuar.",
  SERVICE_NOT_CONFIGURED: "A criação de perfis está temporariamente indisponível.",
  STORAGE_UNAVAILABLE: "Não foi possível guardar ou consultar os perfis. Tenta novamente.",
  ORIGIN_NOT_ALLOWED: "Origem não autorizada.",
  ROUTE_NOT_FOUND: "Endereço não encontrado.",
  METHOD_NOT_ALLOWED: "Método não permitido.",
  REQUEST_TOO_LARGE: "O pedido excede o tamanho permitido.",
  INTERNAL_ERROR: "Não foi possível concluir o pedido. Tenta novamente.",
};

Deno.serve(async (req: Request) => {
  const requestId = crypto.randomUUID();
  const origin = req.headers.get("origin");
  const cors: Record<string,string> = {
    "Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type, x-parent-unlock",
    "Access-Control-Allow-Methods":"GET, POST, OPTIONS",
    "Access-Control-Expose-Headers":"X-Request-Id", "Vary":"Origin",
  };
  if (origin && origins.has(origin)) cors["Access-Control-Allow-Origin"] = origin;
  const url = new URL(req.url);
  const path = url.pathname.replace(/^\/functions\/v1(?=\/)/, "").replace(/^\/families(?=\/|$)/, "");
  const childRoute = /^\/v1\/families\/([^/]+)\/children$/.exec(path);
  const isFamilies = path === "/v1/families";
  const operation = isFamilies ? "families" : childRoute ? "children" : "unknown";
  const reply = (status: number, data: unknown, code?: string) => {
    console.info(JSON.stringify({requestId,domain:"families",operation,status,...(code ? {code} : {})}));
    return new Response(JSON.stringify(data),{status,headers:{...cors,"Content-Type":"application/json","Cache-Control":"no-store","X-Request-Id":requestId}});
  };
  const fail = (status:number, code:string) => reply(status,{error:{code,message:messages[code] ?? messages.INTERNAL_ERROR,requestId}},code);
  if (origin && !origins.has(origin)) return fail(403,"ORIGIN_NOT_ALLOWED");
  if (req.method === "OPTIONS") return new Response(null,{status:204,headers:cors});
  if (operation === "unknown") return fail(404,"ROUTE_NOT_FOUND");
  if (req.method !== "GET" && req.method !== "POST") return fail(405,"METHOD_NOT_ALLOWED");
  const familyId = childRoute?.[1];
  if (familyId && !uuid.test(familyId)) return fail(400,"INVALID_REQUEST");
  const cursor = url.searchParams.get("cursor");
  if (cursor && !uuid.test(cursor)) return fail(400,"INVALID_REQUEST");

  try {
    const projectUrl = Deno.env.get("SUPABASE_URL");
    const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!projectUrl || !key) return fail(503,"SERVICE_NOT_CONFIGURED");
    const token = /^Bearer (\S+)$/i.exec(req.headers.get("authorization") ?? "")?.[1];
    if (!token) return fail(401,"AUTH_REQUIRED");
    const admin = createClient(projectUrl,key,{auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}});
    const {data:{user},error:authError} = await admin.auth.getUser(token);
    if (authError || !user) return fail(401,"AUTH_REQUIRED");
    if (!user.email_confirmed_at) return fail(403,"EMAIL_NOT_CONFIRMED");
    if (req.method === "POST") {
      const unlockToken = req.headers.get("x-parent-unlock") ?? "";
      if (!/^par_[0-9a-f]{64}$/.test(unlockToken)) return fail(403,"PARENT_LOCKED");
      let sessionId: string | undefined;
      try {
        const encoded = token.split(".")[1].replace(/-/g,"+").replace(/_/g,"/");
        const claims = JSON.parse(atob(encoded.padEnd(Math.ceil(encoded.length/4)*4,"=")));
        if (claims.sub === user.id && typeof claims.session_id === "string"
          && /^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(claims.session_id)) sessionId = claims.session_id;
      } catch { /* Auth already validated the JWT; reject missing session binding. */ }
      if (!sessionId) return fail(401,"AUTH_REQUIRED");
      const tokenHash = hex(new Uint8Array(await crypto.subtle.digest("SHA-256",encoder.encode(unlockToken))));
      const {data:authorization,error:unlockError} = await admin.rpc("use_parent_unlock",{
        p_actor_id:user.id,p_auth_session_id:sessionId,p_token_hash:tokenHash,p_touch:true,p_revoke:false,
      });
      if (unlockError || !authorization) return fail(503,"STORAGE_UNAVAILABLE");
      if (authorization.error) return fail(403,"PARENT_LOCKED");
    }
    if (familyId) {
      const {data:membership,error} = await admin.from("family_members")
        .select("id, families!inner(status)").eq("family_id",familyId)
        .eq("adult_user_id",user.id).eq("status","active").eq("families.status","active").maybeSingle();
      if (error) return fail(503,"STORAGE_UNAVAILABLE");
      if (!membership) return fail(404,"FAMILY_NOT_FOUND");
    }
    if (req.method === "GET") {
      if (isFamilies) {
        let query = admin.from("families").select("id,status,created_at,family_members!inner(adult_user_id,status)")
          .eq("status","active").eq("family_members.adult_user_id",user.id).eq("family_members.status","active")
          .order("id").limit(51);
        if (cursor) query = query.gt("id",cursor);
        const {data,error} = await query;
        if (error) return fail(503,"STORAGE_UNAVAILABLE");
        const rows = (data ?? []).slice(0,50);
        return reply(200,{items:rows.map(f=>({id:f.id,status:f.status,createdAt:f.created_at})),nextCursor:(data?.length ?? 0)>50 ? rows[49].id : null});
      }
      let query = admin.from("children").select("id,family_id,display_name,school_year,avatar_id,created_at")
        .eq("family_id",familyId!).order("id").limit(51);
      if (cursor) query = query.gt("id",cursor);
      const {data,error} = await query;
      if (error) return fail(503,"STORAGE_UNAVAILABLE");
      const rows = (data ?? []).slice(0,50);
      return reply(200,{items:rows.map(c=>({id:c.id,familyId:c.family_id,displayName:c.display_name,schoolYear:c.school_year,avatarId:c.avatar_id,createdAt:c.created_at})),nextCursor:(data?.length ?? 0)>50 ? rows[49].id : null});
    }
    if (!req.headers.get("content-type")?.includes("application/json")) return fail(400,"INVALID_REQUEST");
    const reader = req.body?.getReader();
    if (!reader) return fail(400,"INVALID_REQUEST");
    const chunks: Uint8Array[] = []; let size = 0;
    while (true) {
      const {done,value} = await reader.read(); if (done) break;
      size += value.length;
      if (size>2048) {await reader.cancel(); return fail(413,"REQUEST_TOO_LARGE");}
      chunks.push(value);
    }
    const bytes = new Uint8Array(size); let offset = 0;
    for (const chunk of chunks) {bytes.set(chunk,offset); offset += chunk.length;}
    let body;
    try {body = JSON.parse(new TextDecoder().decode(bytes));} catch {return fail(400,"INVALID_REQUEST");}
    if (!body || typeof body !== "object" || Array.isArray(body) || typeof body.clientRequestId !== "string" || !uuid.test(body.clientRequestId)) return fail(400,"INVALID_REQUEST");
    const expected = isFamilies ? ["clientRequestId"] : ["clientRequestId","displayName","schoolYear","avatarId","pin"];
    if (Object.keys(body).some(k=>!expected.includes(k))) return fail(400,"INVALID_REQUEST");
    const handleRpcError = (error:{message:string}) => {
      const code = Object.hasOwn(messages,error.message) ? error.message : "STORAGE_UNAVAILABLE";
      return fail(code === "FAMILY_NOT_FOUND" ? 404 : code === "ADULT_SETUP_REQUIRED" ? 403 : code === "REQUEST_CONFLICT" ? 409 : 503,code);
    };
    if (isFamilies) {
      const {data,error} = await admin.rpc("create_family_for_adult",{p_actor_id:user.id,p_request_id:body.clientRequestId});
      if (error) return handleRpcError(error);
      return reply(201,data);
    }
    if (typeof body.displayName !== "string" || [...body.displayName.trim()].length<1 || [...body.displayName.trim()].length>40
      || !Number.isInteger(body.schoolYear) || body.schoolYear<1 || body.schoolYear>4
      || !avatars.has(body.avatarId) || typeof body.pin !== "string" || !/^[0-9]{4}$/.test(body.pin)) return fail(422,"INVALID_PROFILE");
    const pepper = Deno.env.get("CHILD_PIN_PEPPER");
    if (!pepper || pepper.length<32) return fail(503,"SERVICE_NOT_CONFIGURED");
    const pepperKey = await crypto.subtle.importKey("raw",encoder.encode(pepper),{name:"HMAC",hash:"SHA-256"},false,["sign"]);
    const sign = (value:string) => crypto.subtle.sign("HMAC",pepperKey,encoder.encode(value));
    const prehash = await sign(`child-pin-v1:${familyId}:${body.clientRequestId}:${body.pin}`);
    const material = await crypto.subtle.importKey("raw",prehash,"PBKDF2",false,["deriveBits"]);
    const salt = crypto.getRandomValues(new Uint8Array(16));
    const hash = await crypto.subtle.deriveBits({name:"PBKDF2",hash:"SHA-256",salt,iterations:600000},material,256);
    const fingerprint = await sign(JSON.stringify(["child-create-v1",user.id,familyId,body.clientRequestId,body.displayName.trim(),body.schoolYear,body.avatarId,body.pin]));
    const {data,error} = await admin.rpc("create_child_with_pin",{
      p_actor_id:user.id,p_family_id:familyId,p_child_id:body.clientRequestId,
      p_display_name:body.displayName.trim(),p_school_year:body.schoolYear,p_avatar_id:body.avatarId,
      p_pin_hash:hex(new Uint8Array(hash)),p_salt:hex(salt),p_fingerprint:hex(new Uint8Array(fingerprint)),
    });
    if (error) return handleRpcError(error);
    return reply(201,data);
  } catch {return fail(500,"INTERNAL_ERROR");}
});
