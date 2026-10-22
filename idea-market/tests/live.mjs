// Destructive acceptance tests: run only in a newly provisioned empty classroom.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import WebSocket from 'ws';
import {HttpsProxyAgent} from 'https-proxy-agent';
const proxy=process.env.WSS_PROXY||process.env.HTTPS_PROXY;
class TestSocket extends WebSocket{constructor(url,protocols){super(url,protocols,{agent:proxy?new HttpsProxyAgent(proxy):undefined})}}
process.on('uncaughtException',e=>{console.error(e.message);process.exit(1)});
setTimeout(()=>{console.error('Live test exceeded 90 seconds');process.exit(1)},90000).unref();
import {createClient} from '@supabase/supabase-js';
import {SUPABASE_URL,SUPABASE_KEY} from '../src/config.js';
import {randomBytes} from 'node:crypto';
if(process.env.TEST_ALLOW_DESTRUCTIVE!=='yes')throw Error('Run only on a dedicated empty test classroom with TEST_ALLOW_DESTRUCTIVE=yes');
const pin=process.env.TEST_PIN;if(!pin)throw Error('TEST_PIN required');
const device=()=>randomBytes(32).toString('hex');
async function request(action,token='',data={}){const r=await fetch(SUPABASE_URL+'/functions/v1/idea-market',{method:'POST',headers:{'Content-Type':'application/json',apikey:SUPABASE_KEY},body:JSON.stringify({action,token,data}),signal:AbortSignal.timeout(15000)});return r.json()}
async function ok(action,token='',data={}){const r=await request(action,token,data);assert(!r.error,`${action}: ${r.error}`);return r}
const login=await ok('login','',{pin}),admin=login.token;let s=await ok('admin',admin);assert.equal(s.status,'ready');assert.equal(s.investments.length,0);
console.log('PASS: teacher login and empty classroom');
const board=s.boardKey;const denied=await request('admin',device());assert(denied.error);const deniedBoard=await request('board',device());assert(deniedBoard.error);
const publicState=await ok('student');assert(!('investments' in publicState));assert(!('boardKey' in publicState));assert(!('total' in publicState.teams[0]));
console.log('PASS: student cannot access admin, board, or totals');
const a=device(),b=device(),c=device(),d=device();let epoch=s.epoch;
const race=await Promise.all([request('claim',a,{epoch,company:1}),request('claim',b,{epoch,company:1})]);assert.equal(race.filter(r=>r.mine?.id===1).length,1);assert.equal(race.filter(r=>r.error).length,1);const owner=race[0].mine?a:b,other=owner===a?b:a;
assert.equal((await ok('student',owner)).mine.id,1);assert((await request('claim',owner,{epoch,company:2})).error);await ok('claim',other,{epoch,company:2});await ok('claim',c,{epoch,company:3});await ok('claim',d,{epoch,company:4});
console.log('PASS: concurrent company claim, same-device resume, company switching blocked');
const channels=[];let signals=[0,0,0,0];
await Promise.all(signals.map(async(_,i)=>{const sb=createClient(SUPABASE_URL,SUPABASE_KEY,{auth:{persistSession:false},realtime:{transport:TestSocket}});channels.push(sb);await new Promise((resolve,reject)=>{const timeout=setTimeout(()=>reject(Error('Realtime subscription timeout')),15000);sb.channel('test-'+device()).on('postgres_changes',{event:'UPDATE',schema:'public',table:'idea_market_signal'},()=>signals[i]++).subscribe(x=>{if(x==='SUBSCRIBED'){clearTimeout(timeout);resolve()}})})}));
await ok('start',admin);await ok('working',owner,{epoch});
let items=[{to:2,amount:5000,reason:'실제 학교에서 활용할 수 있는 구체적인 해결책입니다.'}];
assert((await request('submit',owner,{epoch,items,confirmed:false})).error);
assert((await request('submit',owner,{epoch,items:[{...items[0],to:1}],confirmed:true})).error);
assert((await request('submit',owner,{epoch,items:[{...items[0],reason:'짧은 이유'}],confirmed:true})).error);
assert((await request('submit',owner,{epoch,items:[{...items[0],amount:4900}],confirmed:true})).error);
assert((await request('submit',owner,{epoch,items:[{...items[0],amount:4950},{to:3,amount:50,reason:items[0].reason}],confirmed:true})).error);
console.log('PASS: server rejects self-investment, short reasons, bad units, incomplete budget, missing confirmation');
await Promise.all([ok('submit',owner,{epoch,items,confirmed:true}),ok('submit',other,{epoch,items:[{...items[0],to:3}],confirmed:true}),ok('submit',c,{epoch,items:[{...items[0],to:4}],confirmed:true})]);
let snapshot=await ok('board',board);assert.equal(snapshot.teams.reduce((n,t)=>n+t.total,0),15000);assert.equal(snapshot.teams.filter(t=>t.submitted).length,3);assert((await request('submit',owner,{epoch,items,confirmed:true})).error);
await new Promise(resolve=>setTimeout(resolve,1500));assert(signals.every(n=>n>=3));console.log('PASS: 3 simultaneous submissions; 4 independent realtime clients received updates:',signals.join(','));
await ok('settings',admin,{names:snapshot.teams.map((t,i)=>i===0?'수정한 회사':t.name),budget:5000,minutes:0});assert.equal((await ok('student',owner)).mine.name,'수정한 회사');
await ok('cancel',admin,{company:1});snapshot=await ok('board',board);assert.equal(snapshot.teams.reduce((n,t)=>n+t.total,0),10000);await ok('submit',owner,{epoch,items,confirmed:true});
await ok('release',admin,{company:4});assert.equal((await ok('student',d)).mine,null);assert((await request('working',d,{epoch})).error);const replacement=device();await ok('claim',replacement,{epoch,company:4});
console.log('PASS: live rename, cancel/re-submit, revoke device and replace it');
await ok('close',admin);assert((await request('submit',replacement,{epoch,items:[{...items[0],to:1}],confirmed:true})).error);await ok('display',admin,{mode:'reasons',focus:2});assert.equal((await ok('board',board)).display,'reasons');
await ok('reset',admin,{confirm:'RESET',keep:true});const after=await ok('student',owner);assert.equal(after.mine,null);assert.notEqual(after.epoch,epoch);assert((await request('claim',owner,{epoch,company:1})).error);assert.equal((await ok('board',board)).investments.length,0);
await ok('settings',admin,{names:Array.from({length:7},(_,i)=>`${i+1}조 회사`),budget:5000,minutes:0});
console.log('PASS: closure, remote reflection, reset invalidates old session; clean classroom restored');
for(const sb of channels)await sb.removeAllChannels();

process.exit(0);
