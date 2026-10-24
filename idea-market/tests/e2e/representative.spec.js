import {test,expect} from '@playwright/test';
import {createHash} from 'node:crypto';
import {makeDatabase,schemaSource} from '../sql-harness.js';
import {createHandler} from '../../supabase/edge-handler.js';
let db,handler,contexts,errors;
test.beforeEach(async()=>{
 db=await makeDatabase();contexts=[];errors=[];
 await db.exec('begin;'+schemaSource()+`insert into idea_codes_test.room(pin_hash) values(extensions.crypt('1234','test'));insert into idea_codes_test.teams(id,name,entry_code) select g,g||'조 회사',idea_codes_test.default_entry_code(g) from generate_series(1,8) g;set local role service_role;`);
 handler=createHandler(async p=>{const r=await db.query('select idea_codes_test.rpc($1,$2,$3::jsonb,$4) as result',[p.p_action,p.p_token,JSON.stringify(p.p_data),p.p_ip]);return {data:r.rows[0].result}});
});
test.afterEach(async()=>{for(const c of contexts)await c.close();await db.exec('rollback');expect((await db.query("select to_regnamespace('idea_codes_test') as ns")).rows[0].ns).toBeNull();await db.close();expect(errors).toEqual([])});
async function device(browser,width=390){
 const c=await browser.newContext({viewport:{width,height:844},serviceWorkers:'block'});contexts.push(c);c.setDefaultTimeout(10000);
 await c.route('https://**/*',r=>r.abort());
 await c.route('**/functions/v1/idea-market',async route=>{const req=route.request();const res=await handler(new Request(req.url(),{method:req.method(),headers:req.headers(),body:req.postData()}));await route.fulfill({status:res.status,headers:Object.fromEntries(res.headers),body:await res.text()})});
 await c.routeWebSocket(/.*/,ws=>ws.close());
 const p=await c.newPage();p.on('pageerror',e=>errors.push(e.message));p.on('dialog',d=>d.accept());return p;
}
async function enter(p,id,name){await p.goto('/s');await p.locator('#representative').fill(name);for(let i=0;i<4;i++)await p.locator(`[data-digit="${i}"]`).fill(String(id*1000+1)[i])}
async function teacher(browser){const p=await device(browser);await p.goto('/admin');await p.getByLabel('비밀번호 4자리').fill('1234');await p.getByRole('button',{name:'로그인',exact:true}).click();await expect(p.locator('#adminsticky')).toBeVisible();return p}
test('company leader name, second-phone rejection, resume, legacy registration and instructor release at 375/390px',async({browser})=>{
 const instructor=await teacher(browser),first=await device(browser,375),second=await device(browser,390);
 await first.goto('/s');for(let i=0;i<4;i++)await first.locator(`[data-digit="${i}"]`).fill('1001'[i]);await expect(first.locator('#claim')).toBeVisible();await expect(first.locator('.identity')).toHaveCount(0);
 await first.locator('#representative').fill('김조장');await first.getByRole('button',{name:'입장하기',exact:true}).click();await expect(first.locator('.identity')).toContainText('김조장');
 await enter(second,1,'다른 학생');await expect(second.locator('#toast')).toContainText('이미 대표가 접속한');await expect(second.locator('#claim')).toBeVisible();
 await instructor.getByRole('button',{name:'투자 시작',exact:true}).click();await expect(first.locator('#amount-2')).toBeVisible({timeout:15000});await first.locator('#amount-2').fill('5000');await first.locator('#reason-2').fill('수요가 많을 것 같아요');
 await first.reload();await expect(first.locator('#amount-2')).toHaveValue('5000');await expect(first.locator('#reason-2')).toHaveValue('수요가 많을 것 같아요');await expect(first.locator('.identity')).toContainText('김조장');
 await expect(instructor.locator('#teamstatus')).toContainText('조장 김조장',{timeout:15000});
 const token=await first.evaluate(()=>localStorage.getItem('im-device'));const hash=createHash('sha256').update(token).digest('hex');await db.query('update idea_codes_test.teams set representative_name=null where device_hash=$1',[hash]);
 await first.reload();await expect(first.locator('#representativeform')).toBeVisible();await expect(first.locator('#amount-2')).toHaveCount(0);await first.locator('#representative').fill('김조장');await first.getByRole('button',{name:'이름 저장하고 계속',exact:true}).click();await expect(first.locator('#amount-2')).toHaveValue('5000');
 for(const p of [first,second])expect(await p.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBeTruthy();
 await instructor.locator('[data-more="1"]').click();await instructor.getByRole('button',{name:'기기 연결 해제',exact:true}).click();await second.getByRole('button',{name:'입장하기',exact:true}).click();await expect(second.locator('.identity')).toContainText('다른 학생');await expect(first.locator('#claim')).toBeVisible({timeout:15000});
});
test('eight named leaders submit concurrently and polling updates projector',async({browser})=>{
 const instructor=await teacher(browser);const link=await instructor.getByRole('link',{name:'투자 현황판 열기 ↗'}).getAttribute('href');const board=await device(browser,1920);await board.goto(link);
 const phones=await Promise.all(Array.from({length:8},()=>device(browser)));
 await Promise.all(phones.map(async(p,i)=>{await enter(p,i+1,`${i+1}조 조장`);await expect(p.locator('.identity')).toContainText(`${i+1}조 조장`)}));
 await instructor.getByRole('button',{name:'투자 시작',exact:true}).click();
 await Promise.all(phones.map(async(p,i)=>{const to=(i+1)%8+1;await expect(p.locator(`#amount-${to}`)).toBeVisible({timeout:15000});await p.locator(`#amount-${to}`).fill('5000');await p.locator(`#reason-${to}`).fill('필요한 서비스예요');await p.getByRole('button',{name:'투자 내용 확인',exact:true}).click();await p.getByLabel('조원 모두와 상의해서 결정했나요?').check();await p.getByRole('button',{name:'최종 제출',exact:true}).click();await expect(p.getByRole('heading',{name:'제출 완료',exact:true})).toBeVisible()}));
 await expect(board.locator('#boardcount')).toContainText('8 / 8',{timeout:6000});expect((await db.query('select count(*)::int as count,sum(amount)::int as total from idea_codes_test.investments')).rows[0]).toEqual({count:8,total:40000});
});
