// Explicitly read-only smoke: no login, claim, submission, admin or SQL writes.
// Uses eight unclaimed student readers and eight public revision subscriptions.
import https from 'node:https';
import {performance} from 'node:perf_hooks';
import {randomBytes} from 'node:crypto';
import {writeFile} from 'node:fs/promises';
import {HttpsProxyAgent} from 'https-proxy-agent';
import WebSocket from 'ws';
import {SUPABASE_URL,SUPABASE_KEY} from '../src/config.js';
const proxy=process.env.HTTPS_PROXY||process.env.https_proxy;
const agent=proxy?new HttpsProxyAgent(proxy):undefined;
const request=(url,body)=>new Promise((resolve,reject)=>{
 const start=performance.now();const req=https.request(url,{method:body?'POST':'GET',agent,signal:AbortSignal.timeout(15000),headers:body?{'content-type':'application/json',apikey:SUPABASE_KEY}:{}},res=>{
  const chunks=[];res.on('data',c=>chunks.push(c));res.on('end',()=>resolve({status:res.statusCode,body:Buffer.concat(chunks).toString(),ms:Math.round(performance.now()-start)}));
 });req.on('error',reject);req.setTimeout(12000,()=>req.destroy(Error('request timeout')));req.end(body);
});
const output={at:new Date().toISOString(),scope:'production read-only; no claims or investments',routes:[],polls:[],websockets:[]};
for(const route of ['/s','/admin','/board']){const r=await request('https://ourstory-invest.vercel.app'+route);output.routes.push({route,status:r.status,ms:r.ms,hasApp:r.body.includes('id="app"')})}
const devices=Array.from({length:8},()=>randomBytes(32).toString('hex'));
for(let wave=0;wave<4;wave++){
 const results=await Promise.all(devices.map(async token=>{
  const r=await request(SUPABASE_URL+'/functions/v1/idea-market',JSON.stringify({action:'student',token,data:{}}));const b=JSON.parse(r.body);
  return {status:r.status,ms:r.ms,success:!b.error&&b.mine===null&&b.teams?.length===0,private:!('entryCodes'in b)&&!('investments'in b)};
 }));output.polls.push(...results);
 if(wave<3)await new Promise(resolve=>setTimeout(resolve,3000));
}
const sockets=[];
try{
 output.websockets=await Promise.all(devices.map((_,i)=>new Promise(resolve=>{
  const start=performance.now();let settled=false;
  const ws=new WebSocket(SUPABASE_URL.replace('https:','wss:')+'/realtime/v1/websocket?apikey='+encodeURIComponent(SUPABASE_KEY)+'&vsn=1.0.0',{agent});sockets.push(ws);
  const finish=result=>{if(settled)return;settled=true;clearTimeout(timer);resolve({client:i+1,ms:Math.round(performance.now()-start),...result})};
  const timer=setTimeout(()=>finish({joined:false,error:'timeout'}),12000);
  ws.on('open',()=>ws.send(JSON.stringify({topic:'realtime:readonly-check-'+randomBytes(8).toString('hex'),event:'phx_join',payload:{config:{broadcast:{self:false},presence:{key:''},postgres_changes:[{event:'*',schema:'public',table:'idea_market_signal'}]}},ref:'1',join_ref:'1'})));
  ws.on('message',raw=>{try{const m=JSON.parse(raw.toString());if(m.event==='phx_reply'&&m.ref==='1')finish({joined:m.payload?.status==='ok'});}catch{finish({joined:false,error:'invalid response'})}});
  ws.on('error',()=>finish({joined:false,error:'connection error'}));
 })));
 await new Promise(resolve=>setTimeout(resolve,3000));output.websocketStillOpen=sockets.filter(s=>s.readyState===WebSocket.OPEN).length;
}finally{for(const ws of sockets)ws.close()}
const latencies=output.polls.map(p=>p.ms).sort((a,b)=>a-b);
output.summary={requests:latencies.length,errors:output.polls.filter(p=>!p.success||!p.private||p.status!==200).length,p95Ms:latencies[Math.ceil(latencies.length*.95)-1],maxMs:latencies.at(-1),joined:output.websockets.filter(s=>s.joined).length};
await writeFile(new URL('../test-results/production-readonly.json',import.meta.url),JSON.stringify(output,null,2));
console.log(JSON.stringify(output,null,2));
if(output.summary.errors||output.summary.joined!==8||output.websocketStillOpen!==8||output.routes.some(r=>r.status!==200||!r.hasApp))process.exitCode=1;
