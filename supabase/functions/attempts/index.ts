import { createClient } from "npm:@supabase/supabase-js@2";
const origins=new Set(["http://localhost:8081","http://127.0.0.1:8081","http://localhost:8080","http://127.0.0.1:8080"]);
const uuid=/^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i;
const encoder=new TextEncoder();
const hash=async(text:string)=>Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256",encoder.encode(text))),b=>b.toString(16).padStart(2,"0")).join("");
const messages:Record<string,string>={CHILD_SESSION_EXPIRED:"A tua sessão terminou. Entra novamente com o PIN.",ATTEMPT_NOT_FOUND:"Esta ficha não está disponível para o teu perfil.",ASSIGNMENT_WITHDRAWN:"Esta ficha deixou de estar disponível. As respostas já guardadas foram preservadas.",ATTEMPT_READ_ONLY:"Esta tentativa já não permite alterar respostas.",QUESTION_NOT_FOUND:"Esta pergunta não pertence à ficha.",INVALID_ANSWER:"Verifica a resposta. O texto pode ter até 5000 caracteres.",ANSWER_REVISION_CONFLICT:"Esta resposta foi alterada noutro dispositivo. Escolhe a resposta que queres manter.",OPERATION_REUSED:"Não foi possível repetir este pedido. Atualiza a ficha antes de continuar.",INVALID_REQUEST:"O pedido é inválido.",STORAGE_UNAVAILABLE:"Não foi possível guardar o progresso. Tenta novamente.",ROUTE_NOT_FOUND:"Endereço não encontrado.",METHOD_NOT_ALLOWED:"Método não permitido.",ORIGIN_NOT_ALLOWED:"Origem não autorizada.",INTERNAL_ERROR:"Não foi possível concluir o pedido. Tenta novamente."};
Deno.serve(async(req:Request)=>{
 const requestId=crypto.randomUUID(),origin=req.headers.get("origin");
 const path=new URL(req.url).pathname.replace(/^\/functions\/v1(?=\/)/,"").replace(/^\/attempts(?=\/|$)/,"");
 const start=/^\/v1\/assignments\/([^/]+)\/attempts$/.exec(path);
 const get=/^\/v1\/attempts\/([^/]+)$/.exec(path);
 const answer=/^\/v1\/attempts\/([^/]+)\/answers\/([^/]+)$/.exec(path);
 const operation=start?"start":get?"get":answer?"answer":"unknown";
 const cors:Record<string,string>={"Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type","Access-Control-Allow-Methods":"GET, POST, PUT, OPTIONS","Access-Control-Expose-Headers":"X-Request-Id","Vary":"Origin"};
 if(origin&&origins.has(origin))cors["Access-Control-Allow-Origin"]=origin;
 const reply=(status:number,data:unknown,code?:string)=>{console.info(JSON.stringify({requestId,domain:"attempts",operation,status,...(code?{code}:{})}));return new Response(JSON.stringify(data),{status,headers:{...cors,"Content-Type":"application/json","Cache-Control":"no-store","X-Request-Id":requestId}});};
 const fail=(status:number,code:string,details?:Record<string,unknown>)=>reply(status,{error:{code,message:messages[code]??messages.INTERNAL_ERROR,requestId,...(details?{details}:{})}},code);
 if(origin&&!origins.has(origin))return fail(403,"ORIGIN_NOT_ALLOWED");
 if(req.method==="OPTIONS")return new Response(null,{status:204,headers:cors});
 if(operation==="unknown")return fail(404,"ROUTE_NOT_FOUND");
 if(req.method!==(operation==="start"?"POST":operation==="get"?"GET":"PUT"))return fail(405,"METHOD_NOT_ALLOWED");
 const targetId=start?.[1]??get?.[1]??answer?.[1];if(!targetId||!uuid.test(targetId))return fail(400,"INVALID_REQUEST");
 let questionId:string|undefined;
 if(answer){try{questionId=decodeURIComponent(answer[2]);}catch{return fail(400,"INVALID_REQUEST");}if(!questionId||questionId.length>2000)return fail(400,"INVALID_REQUEST");}
 try{
  const token=/^Bearer (chd_[0-9a-f]{64})$/.exec(req.headers.get("authorization")??"")?.[1];
  if(!token)return fail(401,"CHILD_SESSION_EXPIRED");
  const url=Deno.env.get("SUPABASE_URL"),key=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");if(!url||!key)return fail(503,"STORAGE_UNAVAILABLE");
  const admin=createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}});
  const tokenHash=await hash(token);
  let rpcName:string,params:Record<string,unknown>;
  if(operation==="get"){
   rpcName="get_child_attempt";params={p_token_hash:tokenHash,p_attempt_id:targetId};
  }else{
   if(!req.headers.get("content-type")?.includes("application/json"))return fail(400,"INVALID_REQUEST");
   const reader=req.body?.getReader();if(!reader)return fail(400,"INVALID_REQUEST");let size=0;const chunks:Uint8Array[]=[];
   while(true){const {done,value}=await reader.read();if(done)break;size+=value.length;if(size>32768){await reader.cancel();return fail(400,"INVALID_REQUEST");}chunks.push(value);}
   const bytes=new Uint8Array(size);let offset=0;for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.length;}
   let body;try{body=JSON.parse(new TextDecoder().decode(bytes));}catch{return fail(400,"INVALID_REQUEST");}
   if(!body||typeof body!=="object"||Array.isArray(body))return fail(400,"INVALID_REQUEST");
   if(operation==="start"){
    if(Object.keys(body).some(k=>k!=="clientRequestId")||typeof body.clientRequestId!=="string"||!uuid.test(body.clientRequestId))return fail(400,"INVALID_REQUEST");
    rpcName="start_child_attempt";params={p_token_hash:tokenHash,p_assignment_id:targetId,p_request_id:body.clientRequestId,p_request_hash:await hash(JSON.stringify(["start_attempt",targetId]))};
   }else{
    if(Object.keys(body).some(k=>!["operationId","baseRevision","answer"].includes(k))||typeof body.operationId!=="string"||!uuid.test(body.operationId)
      ||!Number.isInteger(body.baseRevision)||body.baseRevision<0||body.baseRevision>2147483646||!body.answer||typeof body.answer!=="object"||Array.isArray(body.answer))return fail(400,"INVALID_REQUEST");
    const a=body.answer;let normalized:Record<string,string>;
    if(a.mode==="unanswered"&&Object.keys(a).length===1)normalized={mode:"unanswered"};
    else if(a.mode==="paper"&&Object.keys(a).length===1)normalized={mode:"paper"};
    else if(a.mode==="multiple-choice"&&typeof a.selectedOptionId==="string"&&Object.keys(a).every(k=>k==="mode"||k==="selectedOptionId"))normalized={mode:"multiple-choice",selectedOptionId:a.selectedOptionId};
    else if(a.mode==="typed"&&typeof a.text==="string"&&[...a.text].length<=5000&&Object.keys(a).every(k=>k==="mode"||k==="text"))normalized={mode:"typed",text:a.text};
    else return fail(422,"INVALID_ANSWER");
    rpcName="save_child_answer";params={p_token_hash:tokenHash,p_attempt_id:targetId,p_question_id:questionId,p_operation_id:body.operationId,
      p_request_hash:await hash(JSON.stringify(["save_answer",targetId,questionId,body.baseRevision,normalized])),p_base_revision:body.baseRevision,p_answer:normalized};
   }
  }
  const {data,error}=await admin.rpc(rpcName,params);
  if(error?.code==="23505")return fail(409,"OPERATION_REUSED");
  if(error||!data)return fail(503,"STORAGE_UNAVAILABLE");
  if(data.error){const code=Object.hasOwn(messages,data.error)?data.error:"STORAGE_UNAVAILABLE";const status=code==="CHILD_SESSION_EXPIRED"?401:code==="ATTEMPT_NOT_FOUND"||code==="QUESTION_NOT_FOUND"?404:code==="INVALID_ANSWER"?422:code==="STORAGE_UNAVAILABLE"?503:409;
   return fail(status,code,typeof data.currentRevision==="number"?{currentRevision:data.currentRevision}:undefined);}
  return reply(operation==="start"?201:200,data);
 }catch{return fail(500,"INTERNAL_ERROR");}
});
