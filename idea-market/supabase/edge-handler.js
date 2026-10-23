// No IP headers are trusted as an identity. Each browser supplies its random device token.
const headers={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'content-type,apikey,authorization','Access-Control-Allow-Methods':'POST,OPTIONS','Content-Type':'application/json','Cache-Control':'no-store'};
const hash=async s=>Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(s)))).map(v=>v.toString(16).padStart(2,'0')).join('');
export function createHandler(rpc){return async req=>{
 if(req.method==='OPTIONS')return new Response('ok',{headers});
 if(req.method!=='POST')return new Response(JSON.stringify({error:'잘못된 요청 방식이에요.'}),{status:405,headers});
 try{
  const raw=await req.text();if(raw.length>16000)return new Response(JSON.stringify({error:'요청이 너무 커요.'}),{status:413,headers});
  const b=JSON.parse(raw);if(typeof b.action!=='string'||typeof b.token!=='string'||b.token.length>128||!b.data||typeof b.data!=='object'||Array.isArray(b.data))throw new Error('input');
  if(b.action==='login'&&!/^[0-9a-f]{64}$/.test(b.token))return new Response(JSON.stringify({error:'로그인 화면을 새로고침해 주세요.','code':'DEVICE_REQUIRED'}),{status:400,headers});
  const {data,error}=await rpc({p_action:b.action,p_token:b.token?await hash(b.token):'',p_data:b.data,p_ip:''});
  if(error){console.error('RPC',error.code);return new Response(JSON.stringify({error:'처리하지 못했어요. 입력을 확인하고 다시 시도해 주세요.'}),{status:400,headers});}
  const waiting=['LOGIN_WAIT','CODE_WAIT'].includes(data?.code);
  return new Response(JSON.stringify(data),{headers:{...headers,...(waiting?{'Retry-After':String(data.retryAfter)}:{})},status:data?.code==='UNAUTHORIZED'?401:waiting?429:200});
 }catch{return new Response(JSON.stringify({error:'요청 형식을 확인해 주세요.'}),{status:400,headers});}
};}
