import { createClient } from "npm:@supabase/supabase-js@2";
const origins=new Set(["http://localhost:8081","http://127.0.0.1:8081","http://localhost:8080","http://127.0.0.1:8080"]);
const uuid=/^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i;
const encoder=new TextEncoder();
const hash=async(value:string)=>Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256",encoder.encode(value))),b=>b.toString(16).padStart(2,"0")).join("");
const messages:Record<string,string>={AUTH_REQUIRED:"A tua sessão terminou. Entra novamente na conta.",PARENT_LOCKED:"Desbloqueia a área dos pais para continuar.",EMAIL_NOT_CONFIRMED:"Confirma o teu e-mail antes de continuar.",CHILD_NOT_FOUND:"Este perfil não está disponível.",CHILD_SESSION_EXPIRED:"A tua sessão terminou. Entra novamente com o PIN.",WORKSHEET_NOT_FOUND:"Esta ficha já não está disponível no catálogo.",SCHOOL_YEAR_MISMATCH:"A ficha não corresponde ao ano escolar da criança.",ASSIGNMENT_ALREADY_ACTIVE:"Esta ficha já está disponível para esta criança.",REQUEST_CONFLICT:"Este pedido já foi usado para outra atribuição. Volta à proposta antes de continuar.",INVALID_REQUEST:"Verifica os dados do pedido.",STORAGE_UNAVAILABLE:"Não foi possível aceder às fichas. Tenta novamente.",ORIGIN_NOT_ALLOWED:"Origem não autorizada.",ROUTE_NOT_FOUND:"Endereço não encontrado.",METHOD_NOT_ALLOWED:"Método não permitido.",INTERNAL_ERROR:"Não foi possível concluir o pedido. Tenta novamente."};
const meta=(row:any)=>({id:row.worksheet_id,versionId:row.version_id,title:row.title,subjectId:row.subject_id,subjectName:row.subject_name,schoolYear:row.school_year,questionCount:row.question_count,choiceCount:row.choice_count,writtenCount:row.written_count,topicIds:row.topic_ids,topicNames:row.topic_names,isSample:row.is_sample,versionNumber:row.version_number});
Deno.serve(async(req:Request)=>{
 const requestId=crypto.randomUUID(),origin=req.headers.get("origin"),url=new URL(req.url);
 const path=url.pathname.replace(/^\/functions\/v1(?=\/)/,"").replace(/^\/worksheets(?=\/|$)/,"");
 const assignmentRoute=/^\/v1\/children\/([^/]+)\/assignments$/.exec(path);
 const detailRoute=/^\/v1\/worksheets\/([^/]+)$/.exec(path);
 const operation=assignmentRoute?"assignments":detailRoute?"detail":path==="/v1/subjects"?"subjects":path==="/v1/topics"?"topics":path==="/v1/worksheets"?"catalogue":"unknown";
 const cors:Record<string,string>={"Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type, x-parent-unlock","Access-Control-Allow-Methods":"GET, POST, OPTIONS","Access-Control-Expose-Headers":"X-Request-Id","Vary":"Origin"};
 if(origin&&origins.has(origin))cors["Access-Control-Allow-Origin"]=origin;
 const reply=(status:number,body:unknown,code?:string)=>{console.info(JSON.stringify({requestId,domain:"worksheets",operation,status,...(code?{code}:{})}));return new Response(JSON.stringify(body),{status,headers:{...cors,"Content-Type":"application/json","Cache-Control":"no-store","X-Request-Id":requestId}});};
 const fail=(status:number,code:string)=>reply(status,{error:{code,message:messages[code]??messages.INTERNAL_ERROR,requestId}},code);
 if(origin&&!origins.has(origin))return fail(403,"ORIGIN_NOT_ALLOWED");
 if(req.method==="OPTIONS")return new Response(null,{status:204,headers:cors});
 if(operation==="unknown")return fail(404,"ROUTE_NOT_FOUND");
 if(req.method!=="GET"&&!(operation==="assignments"&&req.method==="POST"))return fail(405,"METHOD_NOT_ALLOWED");
 const cursor=url.searchParams.get("cursor"),subjectId=url.searchParams.get("subjectId"),versionId=url.searchParams.get("versionId");
 const yearRaw=url.searchParams.get("schoolYear"),year=yearRaw===null?null:Number(yearRaw);
 const topicIds=[...new Set((url.searchParams.get("topicIds")??"").split(",").filter(Boolean))];
 if([cursor,subjectId,versionId,assignmentRoute?.[1],detailRoute?.[1]].some(v=>v!=null&&!uuid.test(v))
   ||(year!==null&&(!Number.isInteger(year)||year<1||year>4))||topicIds.length>20||topicIds.some(id=>!uuid.test(id)))return fail(400,"INVALID_REQUEST");
 try{
  const projectUrl=Deno.env.get("SUPABASE_URL"),serverKey=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if(!projectUrl||!serverKey)return fail(503,"STORAGE_UNAVAILABLE");
  const token=/^Bearer (\S+)$/i.exec(req.headers.get("authorization")??"")?.[1];
  if(!token)return fail(401,"AUTH_REQUIRED");
  const admin=createClient(projectUrl,serverKey,{auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}});
  let actorId:string|undefined,authSessionId:string|undefined,unlockHash:string|undefined;
  const childId=assignmentRoute?.[1];
  if(token.startsWith("chd_")){
   if(operation!=="assignments"||req.method!=="GET"||!/^chd_[0-9a-f]{64}$/.test(token))return fail(401,"CHILD_SESSION_EXPIRED");
   const {data:session,error}=await admin.rpc("use_child_session",{p_token_hash:await hash(token),p_revoke:false});
   if(error)return fail(503,"STORAGE_UNAVAILABLE");
   if(!session||session.error)return fail(401,"CHILD_SESSION_EXPIRED");
   if(session.child.id!==childId)return fail(404,"CHILD_NOT_FOUND");
  }else{
   const {data:{user},error}=await admin.auth.getUser(token);
   if(error||!user)return fail(401,"AUTH_REQUIRED");
   if(!user.email_confirmed_at)return fail(403,"EMAIL_NOT_CONFIRMED");
   actorId=user.id;
   const unlock=req.headers.get("x-parent-unlock")??"";
   if(!/^par_[0-9a-f]{64}$/.test(unlock))return fail(403,"PARENT_LOCKED");
   try{const encoded=token.split(".")[1].replace(/-/g,"+").replace(/_/g,"/");const claims=JSON.parse(atob(encoded.padEnd(Math.ceil(encoded.length/4)*4,"=")));if(claims.sub===user.id&&typeof claims.session_id==="string"&&uuid.test(claims.session_id))authSessionId=claims.session_id;}catch{}
   if(!authSessionId)return fail(401,"AUTH_REQUIRED");
   unlockHash=await hash(unlock);
   const {data:authorization,error:authzError}=await admin.rpc("use_parent_unlock",{p_actor_id:actorId,p_auth_session_id:authSessionId,p_token_hash:unlockHash,p_touch:true,p_revoke:false});
   if(authzError)return fail(503,"STORAGE_UNAVAILABLE");
   if(!authorization||authorization.error)return fail(403,"PARENT_LOCKED");
   if(childId){
    const {data:child,error:childError}=await admin.from("children").select("family_id").eq("id",childId).maybeSingle();
    if(childError)return fail(503,"STORAGE_UNAVAILABLE");
    if(!child)return fail(404,"CHILD_NOT_FOUND");
    const {data:member,error:memberError}=await admin.from("family_members").select("id,families!inner(status)").eq("family_id",child.family_id).eq("adult_user_id",actorId).eq("status","active").eq("families.status","active").maybeSingle();
    if(memberError)return fail(503,"STORAGE_UNAVAILABLE");
    if(!member)return fail(404,"CHILD_NOT_FOUND");
   }
  }
  if(operation==="assignments"){
   if(req.method==="POST"){
    if(!req.headers.get("content-type")?.includes("application/json"))return fail(400,"INVALID_REQUEST");
    const reader=req.body?.getReader();if(!reader)return fail(400,"INVALID_REQUEST");
    let size=0;const chunks:Uint8Array[]=[];
    while(true){const {done,value}=await reader.read();if(done)break;size+=value.length;if(size>1024){await reader.cancel();return fail(400,"INVALID_REQUEST");}chunks.push(value);}
    const bytes=new Uint8Array(size);let offset=0;for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.length;}
    let body;try{body=JSON.parse(new TextDecoder().decode(bytes));}catch{return fail(400,"INVALID_REQUEST");}
    if(!body||typeof body!=="object"||Array.isArray(body)||Object.keys(body).some(k=>k!=="clientRequestId"&&k!=="worksheetVersionId")
      ||typeof body.clientRequestId!=="string"||!uuid.test(body.clientRequestId)||typeof body.worksheetVersionId!=="string"||!uuid.test(body.worksheetVersionId))return fail(400,"INVALID_REQUEST");
    const {data,error}=await admin.rpc("assign_worksheet_to_child",{p_actor_id:actorId,p_auth_session_id:authSessionId,p_unlock_hash:unlockHash,p_child_id:childId,p_version_id:body.worksheetVersionId,p_request_id:body.clientRequestId});
    if(error?.code==="23505")return fail(409,"REQUEST_CONFLICT");
    if(error||!data)return fail(503,"STORAGE_UNAVAILABLE");
    if(data.error){const code=Object.hasOwn(messages,data.error)?data.error:"STORAGE_UNAVAILABLE";return fail(code==="PARENT_LOCKED"?403:code==="CHILD_NOT_FOUND"||code==="WORKSHEET_NOT_FOUND"?404:code==="SCHOOL_YEAR_MISMATCH"?422:code==="REQUEST_CONFLICT"||code==="ASSIGNMENT_ALREADY_ACTIVE"?409:503,code);}
    return reply(201,data);
   }
   let query=admin.from("worksheet_assignments").select("id,child_id,worksheet_version_id,assigned_at,status").eq("child_id",childId!).eq("status","active").order("id").limit(51);
   if(cursor)query=query.gt("id",cursor);
   const {data,error}=await query;if(error)return fail(503,"STORAGE_UNAVAILABLE");
   const rows=(data??[]).slice(0,50);if(!rows.length)return reply(200,{items:[],nextCursor:null});
   const {data:catalogue,error:catalogueError}=await admin.from("worksheet_catalogue").select("*").in("version_id",[...new Set(rows.map(r=>r.worksheet_version_id))]);
   if(catalogueError)return fail(503,"STORAGE_UNAVAILABLE");
   const byVersion=new Map((catalogue??[]).map(v=>[v.version_id,v]));
   if(rows.some(r=>!byVersion.has(r.worksheet_version_id)))return fail(503,"STORAGE_UNAVAILABLE");
   return reply(200,{items:rows.map(r=>({id:r.id,childId:r.child_id,worksheetVersionId:r.worksheet_version_id,assignedAt:r.assigned_at,status:r.status,worksheet:meta(byVersion.get(r.worksheet_version_id))})),nextCursor:(data?.length??0)>50?rows[49].id:null});
  }
  if(operation==="detail"){
   let query=admin.from("worksheet_catalogue").select("*").eq("worksheet_id",detailRoute![1]);
   query=versionId?query.eq("version_id",versionId):query.eq("is_latest",true);
   const {data:entry,error}=await query.maybeSingle();if(error)return fail(503,"STORAGE_UNAVAILABLE");if(!entry)return fail(404,"WORKSHEET_NOT_FOUND");
   const {data:version,error:versionError}=await admin.from("worksheet_versions").select("content_json").eq("id",entry.version_id).maybeSingle();
   if(versionError||!version)return fail(503,"STORAGE_UNAVAILABLE");
   return reply(200,{...meta(entry),content:version.content_json});
  }
  if(operation==="subjects"){
   let query=admin.from("subjects").select("id,name").order("id").limit(51);if(cursor)query=query.gt("id",cursor);
   const {data,error}=await query;if(error)return fail(503,"STORAGE_UNAVAILABLE");const rows=(data??[]).slice(0,50);
   return reply(200,{items:rows,nextCursor:(data?.length??0)>50?rows[49].id:null});
  }
  if(operation==="topics"){
   if(!subjectId||year===null)return fail(400,"INVALID_REQUEST");
   let query=admin.from("topics").select("id,name,subject_id,school_year").eq("subject_id",subjectId).eq("school_year",year).order("id").limit(51);if(cursor)query=query.gt("id",cursor);
   const {data,error}=await query;if(error)return fail(503,"STORAGE_UNAVAILABLE");const rows=(data??[]).slice(0,50);
   return reply(200,{items:rows.map(t=>({id:t.id,name:t.name,subjectId:t.subject_id,schoolYear:t.school_year})),nextCursor:(data?.length??0)>50?rows[49].id:null});
  }
  let query=admin.from("worksheet_catalogue").select("*").eq("worksheet_status","published").eq("is_latest",true).order("version_id").limit(51);
  if(subjectId)query=query.eq("subject_id",subjectId);if(year!==null)query=query.eq("school_year",year);
  if(topicIds.length)query=query.contains("topic_ids",topicIds).containedBy("topic_ids",topicIds);
  if(cursor)query=query.gt("version_id",cursor);
  const {data,error}=await query;if(error)return fail(503,"STORAGE_UNAVAILABLE");const rows=(data??[]).slice(0,50);
  return reply(200,{items:rows.map(meta),nextCursor:(data?.length??0)>50?rows[49].version_id:null});
 }catch{return fail(500,"INTERNAL_ERROR");}
});
