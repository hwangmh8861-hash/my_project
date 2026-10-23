import fs from 'node:fs';
import {PGlite} from '@electric-sql/pglite';
// PGlite executes real PostgreSQL/PLpgSQL offline. It lacks pgcrypto; these test-only
// stand-ins verify control flow, NOT cryptographic strength. Production uses pgcrypto.
export async function makeDatabase(){const db=new PGlite();await db.exec(`
 create role anon; create role authenticated; create role service_role bypassrls;
 create schema extensions;
 create function extensions.gen_salt(text) returns text language sql as $$ select 'test-salt'::text $$;
 create function extensions.crypt(text,text) returns text language sql as $$ select md5($1||'test-only') $$;
 create function extensions.digest(text,text) returns bytea language sql as $$ select sha256(convert_to($1,'UTF8')) $$;
 create function extensions.gen_random_bytes(int) returns bytea language sql as $$ select substring(decode(repeat(md5(gen_random_uuid()::text),greatest(1,$1)),'hex') from 1 for $1) $$;
 grant usage on schema extensions to service_role;
 `);return db;}
export function isolated(text){return text.replaceAll('idea_private','idea_codes_test').replaceAll('public.idea_market_signal','idea_codes_test.signal').replaceAll('public.idea_market_rpc','idea_codes_test.rpc').split('\n').filter(l=>!l.includes('alter publication')).join('\n');}
export function schemaSource(upgrade=false){let src=fs.readFileSync(new URL(upgrade?'./fixtures/pre-hardening.sql':'../supabase/schema.sql',import.meta.url),'utf8');if(upgrade)for(const file of fs.readdirSync(new URL('../supabase/migrations/',import.meta.url)).filter(f=>f.endsWith('.sql')).sort())src+='\n'+fs.readFileSync(new URL('../supabase/migrations/'+file,import.meta.url),'utf8');return isolated(src);}
export async function runAssertions(db,file,upgrade=false){const sql='begin;\n'+schemaSource(upgrade)+'\n'+fs.readFileSync(new URL('./sql/'+file,import.meta.url),'utf8')+'\nrollback;';if(sql.includes('idea_private')||sql.includes('public.idea_market_rpc'))throw Error('Production reference in isolated test');try{await db.exec(sql)}catch(e){await db.exec('rollback');throw Error(e.message+' '+(e.where||'')+' '+(e.internalQuery||''))}const r=await db.query("select to_regnamespace('idea_codes_test') as schema");if(r.rows[0].schema!==null)throw Error('Test schema escaped rollback');}
