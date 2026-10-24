import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {makeDatabase,isolated} from './sql-harness.js';
const read=path=>fs.readFileSync(new URL(path,import.meta.url),'utf8');
test('production entry-only activation preserves spare logins, financial validation, delays, ownership and privacy',async()=>{
 const db=await makeDatabase();const files=fs.readdirSync(new URL('../supabase/migrations/',import.meta.url)).filter(f=>f.endsWith('.sql')).sort();
 let base=read('./fixtures/pre-hardening.sql');for(const f of files.filter(f=>!f.includes('representative_')&&!f.includes('spare_instructor')))base+='\n'+read('../supabase/migrations/'+f);
 base+='\n'+read('./fixtures/pre-spare-production-rpc.sql')+';\n'+read('../supabase/migrations/20261023124013_spare_instructor_access.sql');
 const patches=files.filter(f=>f.includes('representative_')&&!f.includes('lock_and_presentation')&&!f.includes('patch_stage')).map(f=>read('../supabase/migrations/'+f)).join('\n');
 try{for(const assertion of ['representative-lock.assert.sql','company-codes.assert.sql','access-delays.assert.sql','submission-recovery.assert.sql','spare-instructor.assert.sql']){
  await db.exec('begin;'+isolated(base+'\n'+patches));
  const body=(await db.query("select prosrc from pg_proc where oid='idea_codes_test.rpc(text,text,jsonb,text)'::regprocedure")).rows[0].prosrc;
  assert(body.includes('TEAM_IN_USE'));assert(body.includes('verify_instructor_pin'));assert(body.includes("p_action='representative_name'"));
  await db.exec(read('./sql/'+assertion));await db.exec('rollback');
  assert.equal((await db.query("select to_regnamespace('idea_codes_test') as ns")).rows[0].ns,null);
 }}catch(e){throw new Error(e.message+' '+(e.where||''))}finally{await db.close()}
});
