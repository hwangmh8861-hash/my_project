import { createClient } from 'npm:@supabase/supabase-js@2.118.0';
const db=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false}});
const headers={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'content-type,apikey,authorization','Access-Control-Allow-Methods':'POST,OPTIONS','Content-Type':'application/json','Cache-Control':'no-store'};
const hash=async(s:string)=>Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(s)))).map(v=>v.toString(16).padStart(2,'0')).join('');
Deno.serve(async(req)=>{
 if(req.method==='OPTIONS')return new Response('ok',{headers});
 if(req.method!=='POST')return new Response(JSON.stringify({error:'POST 요청만 가능합니다.'}),{status:405,headers});
 try{
  const raw=await req.text();if(raw.length>16000)return new Response(JSON.stringify({error:'요청이 너무 큽니다.'}),{status:413,headers});
  const b=JSON.parse(raw);if(typeof b.action!=='string'||typeof b.token!=='string'||b.token.length>128)throw new Error('input');
  const {data,error}=await db.rpc('idea_market_rpc',{p_action:b.action,p_token:b.token?await hash(b.token):'',p_data:b.data||{},p_ip:await hash(req.headers.get('x-forwarded-for')?.split(',')[0]?.trim()||req.headers.get('x-real-ip')||'unknown')});
  if(error){console.error('RPC',error.code,error.message);return new Response(JSON.stringify({error:'요청을 처리하지 못했습니다. 입력을 확인하고 다시 시도해 주세요.'}),{status:400,headers});}
  return new Response(JSON.stringify(data),{headers,status:data?.code==='UNAUTHORIZED'?401:data?.code==='RATE_LIMIT'?429:200});
 }catch{return new Response(JSON.stringify({error:'요청 형식이 올바르지 않습니다.'}),{status:400,headers});}
});
