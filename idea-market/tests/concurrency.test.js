import test from 'node:test';
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {once} from 'node:events';
import {createHash} from 'node:crypto';
import {makeDatabase,schemaSource} from './sql-harness.js';
import {createHandler} from '../supabase/edge-handler.js';

// Eight independent HTTP clients → actual Edge handler → actual PL/pgSQL.
// PGlite queues statements: this verifies overlapping requests and integrity,
// not production PostgreSQL multi-connection lock performance or cloud capacity.
test('eight devices: overlapping claims, double submission, privacy, totals and polling',async t=>{
 const db=await makeDatabase();let server;const timings=[];
 const hash=s=>createHash('sha256').update(s).digest('hex');
 try{
  await db.exec('begin;'+schemaSource()+`insert into idea_codes_test.room(pin_hash) values(extensions.crypt('1234','test'));insert into idea_codes_test.teams(id,name,entry_code) select g,g||'조 회사',idea_codes_test.default_entry_code(g) from generate_series(1,8) g;set local role service_role;`);
  const handler=createHandler(async args=>{const r=await db.query('select idea_codes_test.rpc($1,$2,$3::jsonb,$4) as result',[args.p_action,args.p_token,JSON.stringify(args.p_data),args.p_ip]);return {data:r.rows[0].result}});
  server=createServer(async(req,res)=>{try{const parts=[];for await(const part of req)parts.push(part);const response=await handler(new Request('http://test.invalid',{method:'POST',body:Buffer.concat(parts).toString()}));res.writeHead(response.status,Object.fromEntries(response.headers));res.end(await response.text())}catch(e){res.writeHead(500);res.end(JSON.stringify({error:e.message}))}});
  server.listen(0,'127.0.0.1');await once(server,'listening');
  const url=`http://127.0.0.1:${server.address().port}`;
  const call=async(action,token,data={})=>{const began=performance.now();const response=await fetch(url,{method:'POST',body:JSON.stringify({action,token,data})});const body=await response.json();timings.push(performance.now()-began);assert(response.status<500,JSON.stringify(body));return body};
  const devices=Array.from({length:8},(_,i)=>hash('student-device-'+i));
  const instructor=hash('instructor-device');
  const login=await call('login',instructor,{pin:'1234'});assert(login.token);
  const admin=await call('admin',login.token);const epoch=admin.epoch;
  const board=admin.boardKey;
  const claims=await Promise.all(devices.map((token,i)=>call('claim',token,{epoch,entryCode:admin.entryCodes[i].entryCode,representativeName:`대표 ${i+1}`})));
  claims.forEach((r,i)=>{assert.equal(r.mine.id,i+1);assert.equal(r.mine.representativeName,`대표 ${i+1}`);assert(!r.entryCodes);assert(!r.investments)});
  // Two devices racing for an unoccupied company: exactly one wins.
  await call('release',login.token,{company:8});
  const challengers=[devices[7],hash('ninth-device')];
  const raced=await Promise.all(challengers.map(token=>call('claim',token,{epoch,entryCode:admin.entryCodes[7].entryCode,representativeName:'경합 대표'})));
  assert.equal(raced.filter(r=>r.mine?.id===8).length,1);assert.equal(raced.filter(r=>r.code==='TEAM_IN_USE').length,1);
  devices[7]=challengers[raced.findIndex(r=>r.mine?.id===8)];
  assert.equal((await call('start',login.token)).status,'open');
  const items=i=>[{to:(i+1)%8+1,amount:3000,reason:'수요가 많아요'},{to:(i+2)%8+1,amount:2000,reason:'실생활에 도움이 돼요'}];
  // Two requests per company arrive together, as with a double tap/retry.
  const submissions=await Promise.all(devices.flatMap((token,i)=>[call('submit',token,{epoch,confirmed:true,items:items(i)}),call('submit',token,{epoch,confirmed:true,items:items(i)})]));
  assert.equal(submissions.filter(r=>r.mine?.submitted===true&&!r.error).length,8);
  assert.equal(submissions.filter(r=>r.code==='SUBMITTED').length,8);
  const totals=(await db.query('select count(*)::int as count,sum(amount)::int as amount,count(distinct sender)::int as senders from idea_codes_test.investments')).rows[0];
  assert.deepEqual(totals,{count:16,amount:40000,senders:8});
  const audience=await call('board',board);assert.equal(audience.teams.filter(t=>t.submitted).length,8);assert.equal(audience.teams.reduce((sum,t)=>sum+t.total,0),40000);
  assert(!JSON.stringify(audience).match(/entryCodes|entry_code|representativeName|대표/));
  // Twenty waves with eight simultaneous polls (160 requests).
  for(let round=0;round<20;round++){
   const results=await Promise.all(devices.map(token=>call('student',token)));
   results.forEach((r,i)=>{assert.equal(r.mine.id,i+1);assert.deepEqual(r.mine.items,items(i).toSorted((a,b)=>a.to-b.to));assert(!r.investments);assert(!r.entryCodes);assert(r.teams.every(team=>!('total'in team)&&!('representativeName'in team)))});
  }
  assert.equal((await call('close',login.token)).status,'closed');
  assert.equal((await call('start',login.token)).status,'open');
  await call('cancel',login.token,{company:1});
  assert.deepEqual((await call('student',devices[0])).mine.items,items(0));
  assert.equal((await call('submit',devices[0],{epoch,confirmed:true,items:items(0)})).mine.submitted,true);
  const sorted=timings.toSorted((a,b)=>a-b);
  t.diagnostic(JSON.stringify({httpRequests:timings.length,p95Ms:Math.round(sorted[Math.ceil(sorted.length*.95)-1]),maxMs:Math.round(sorted.at(-1)),scope:'local PGlite, not cloud capacity'}));
 }finally{
  if(server)await new Promise(resolve=>server.close(resolve));
  await db.exec('rollback');assert.equal((await db.query("select to_regnamespace('idea_codes_test') as ns")).rows[0].ns,null);await db.close();
 }
});

test('fresh and upgraded RPC retain explicit bulk predicates for safe-update servers',async()=>{
 const db=await makeDatabase();
 try{for(const upgrade of [false,true]){
  await db.exec('begin;'+schemaSource(upgrade));
  const source=(await db.query("select prosrc from pg_proc where oid='idea_codes_test.rpc(text,text,jsonb,text)'::regprocedure")).rows[0].prosrc;
  const writes=source.match(/\b(?:delete\s+from|update)\s+idea_codes_test\.\w+[^;]*;/gi)||[];
  assert(writes.length>15);for(const statement of writes)assert.match(statement,/\bwhere\b/i,statement);
  await db.exec('rollback');
 }}finally{await db.close()}
});
