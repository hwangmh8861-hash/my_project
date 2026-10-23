import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
// Supabase API 연결에는 safeupdate가 켜져 있어 WHERE 없는 UPDATE/DELETE가 21000 오류로 실패한다.
// 로컬 PGlite에는 이 확장이 없으므로 운영 함수의 문장을 직접 검사한다.
function bareStatements(sql){return [...sql.matchAll(/(?:delete\s+from|update)\s+(?:idea_private|public)\.[a-z_]+[^;]*;/gi)].map(m=>m[0]).filter(s=>!/\swhere\s/i.test(s))}
test('운영 RPC는 WHERE 없는 UPDATE/DELETE를 쓰지 않는다',()=>{
 const dir=new URL('../supabase/migrations/',import.meta.url);
 const latest=fs.readdirSync(dir).filter(f=>f.endsWith('.sql')).sort().filter(f=>fs.readFileSync(new URL(f,dir),'utf8').includes('function public.idea_market_rpc(')).pop();
 assert.deepEqual(bareStatements(fs.readFileSync(new URL(latest,dir),'utf8')),[],latest);
 assert.deepEqual(bareStatements(fs.readFileSync(new URL('../supabase/schema.sql',import.meta.url),'utf8')),[]);
});
