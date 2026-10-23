import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {makeDatabase,isolated} from './sql-harness.js';
const read=path=>fs.readFileSync(new URL(path,import.meta.url),'utf8');
const extension=read('../supabase/migrations/20261023124013_spare_instructor_access.sql');
const representative=read('../supabase/migrations/20261023053000_representative_lock_and_presentation.sql');
test('production RPC upgrade preserves its entire body except two login hooks and tolerates pending migration order',async()=>{
 const db=await makeDatabase();
 let base=read('./fixtures/pre-hardening.sql');
 for(const name of fs.readdirSync(new URL('../supabase/migrations/',import.meta.url)).filter(n=>n.endsWith('.sql')&&!n.includes('representative_lock')&&!n.includes('spare_instructor')).sort())base+='\n'+read('../supabase/migrations/'+name);
 base+='\n'+read('./fixtures/pre-spare-production-rpc.sql');
 try{for(const applyPending of [false,true]){
  await db.exec('begin;'+isolated(base));
  const before=(await db.query("select prosrc from pg_proc where oid='idea_codes_test.rpc(text,text,jsonb,text)'::regprocedure")).rows[0].prosrc;
  await db.exec(isolated(extension));
  const after=(await db.query("select prosrc from pg_proc where oid='idea_codes_test.rpc(text,text,jsonb,text)'::regprocedure")).rows[0].prosrc;
  const branch=isolated(extension).match(/\$branch\$([\s\S]*?)\$branch\$/)[1];
  const expected=before.replace("extensions.crypt(p_data->>'pin',r.pin_hash)<>r.pin_hash","not idea_codes_test.verify_instructor_pin(p_data->>'pin',r.pin_hash)").replace('select exists(select 1 from idea_codes_test.admin_sessions where token_hash=p_token and expires>now()) into admin;',s=>s+branch);
  assert.equal(after,expected);
  if(applyPending)await db.exec(isolated(representative));
  await db.exec(read('./sql/spare-instructor.assert.sql'));
  await db.exec('rollback');
  assert.equal((await db.query("select to_regnamespace('idea_codes_test') as ns")).rows[0].ns,null);
 }}finally{await db.close()}
});
