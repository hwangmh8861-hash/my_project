// Generate an isolated, rollback-only SQL test. This script never connects to a DB.
import fs from 'node:fs';
const base=new URL('../',import.meta.url);
let schema=fs.readFileSync(new URL('supabase/schema.sql',base),'utf8')
 .replaceAll('idea_private','idea_codes_test')
 .replaceAll('public.idea_market_signal','idea_codes_test.signal')
 .replaceAll('public.idea_market_rpc','idea_codes_test.rpc')
 .replace('create schema if not exists idea_codes_test','create schema idea_codes_test')
 .split('\n').filter(l=>!l.includes('alter publication')).join('\n');
const assertions=fs.readFileSync(new URL('tests/sql/company-codes.assert.sql',base),'utf8');
const query='begin;\n'+schema+'\n'+assertions+'\nrollback;\n';
if(query.includes('idea_private')||query.includes('public.idea_market_signal'))throw Error('Production reference found in isolated test');
fs.mkdirSync(new URL('.runtime/',base),{recursive:true});
fs.writeFileSync(new URL('.runtime/test_codes.sql',base),query);
console.log('Prepared .runtime/test_codes.sql — isolated schema, transaction rollback, no DB connection.');
