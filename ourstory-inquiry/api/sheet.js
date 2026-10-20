const headers=['접수일시','학교명','학교급','담당자명','담당자 직책','이메일','연락처','관심 프로그램','희망 교육 시기','예상 참여인원','희망 차시','문의 내용','개인정보 수집 동의','진행 상태','다음 연락일','담당자 메모','접수 경로'];
const cell=(v)=>{let s=String(v??'');if(/^[\s]*[=+@\-]/.test(s))s="'"+s;return '"'+s.replace(/"/g,'""')+'"';};
module.exports=async(req,res)=>{
 if(req.method!=='GET')return res.status(405).end();
 res.setHeader('Cache-Control','no-store, max-age=0');res.setHeader('X-Robots-Tag','noindex, nofollow');
 if(!process.env.SUPABASE_ANON_KEY||!process.env.SUPABASE_URL||!process.env.INQUIRY_SHARED_SECRET)return res.status(503).end();
 if(typeof req.query.key!=='string'||req.query.key!==process.env.INQUIRY_SHARED_SECRET)return res.status(403).end();
 try{
 const r=await fetch(process.env.SUPABASE_URL+'/rest/v1/rpc/ourstory_sheet_export',{method:'POST',headers:{'apikey':process.env.SUPABASE_ANON_KEY,'Authorization':'Bearer '+process.env.SUPABASE_ANON_KEY,'Content-Type':'application/json'},body:JSON.stringify({p_token:process.env.INQUIRY_SHARED_SECRET})});
 if(!r.ok)return res.status(502).end();
 const rows=await r.json();const data=[headers.map(cell).join(','),...rows.map(x=>headers.map(h=>cell(x[h])).join(','))].join('\r\n');
 res.setHeader('Content-Type','text/csv; charset=utf-8');return res.status(200).send('\uFEFF'+data);
 }catch{return res.status(502).end()}
};