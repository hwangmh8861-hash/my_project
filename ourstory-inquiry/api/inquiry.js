const clean=(value,max)=>typeof value==='string'?value.trim().slice(0,max):'';
module.exports=async(req,res)=>{
 res.setHeader('Cache-Control','no-store');
 if(req.method!=='POST')return res.status(405).json({ok:false});
 if(!process.env.SUPABASE_ANON_KEY||!process.env.SUPABASE_URL)return res.status(503).json({ok:false});
 if(JSON.stringify(req.body||{}).length>6000)return res.status(413).json({ok:false});
 const d=req.body||{};
 if(d.website)return res.status(200).json({ok:true});
 const school_name=clean(d.schoolName,80),school_type=clean(d.schoolType,40),contact_name=clean(d.contactName,50),position=clean(d.position,80),phone=clean(d.phone,35),email=clean(d.email,120),program=clean(d.program,150),message=clean(d.message,1800);
 if(!school_name||!contact_name||!phone||!program||d.privacy!==true)return res.status(400).json({ok:false});
 if(email&&!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email))return res.status(400).json({ok:false});
 try{
  const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),9000);
  let r;try{r=await fetch(process.env.SUPABASE_URL+'/rest/v1/ourstory_inquiries',{method:'POST',headers:{'apikey':process.env.SUPABASE_ANON_KEY,'Authorization':'Bearer '+process.env.SUPABASE_ANON_KEY,'Content-Type':'application/json','Prefer':'return=minimal'},body:JSON.stringify({school_name,school_type,contact_name,position,phone,email,program,message,privacy_consent:true}),signal:controller.signal})}finally{clearTimeout(timer)}
  if(!r.ok){console.error('Inquiry DB write failed',r.status);return res.status(502).json({ok:false})}
  return res.status(201).json({ok:true});
 }catch(e){console.error('Inquiry request error',e.message);return res.status(502).json({ok:false})}
};