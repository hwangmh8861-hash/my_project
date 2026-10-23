export function money(n){if(!n)return '0원';const sign=n<0?'−':'';n=Math.abs(n);const e=Math.floor(n/10000),m=n%10000;return sign+(e?e.toLocaleString('ko-KR')+'억'+(m?' ':''):'')+(m?m.toLocaleString('ko-KR')+'만':'')+' 원';}
export const escapeHtml=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
export function validate(draft,budget,mine,teams){let total=0,active=0;for(const [id,x]of Object.entries(draft)){const n=Number(x.amount);if(!Number.isInteger(n)||n<0||n%100!==0)return '투자금은 100만 원 단위로 입력해 주세요.';if(n){if(Number(id)===mine||!teams.some(t=>t.id===Number(id)))return '투자 대상을 확인해 주세요.';total+=n;active++;if(!(x.reason||'').trim())return '투자한 회사마다 이유를 작성해 주세요.';}}if(total>budget)return '투자 가능한 금액을 넘었어요.';if(total!==budget||!active)return '남은 투자금을 모두 배분해 주세요.';return '';}
export function csv(rows){return '\ufeff'+rows.map(row=>row.map(v=>{let x=String(v??'');if(/^[=+\-@\t\r]/.test(x))x="'"+x;return '"'+x.replace(/"/g,'""')+'"'}).join(',')).join('\r\n')}

export const pollDelay=status=>status==='open'?3000:10000;
export const isInAppBrowser=ua=>/KAKAOTALK|NAVER\(|NAVER\/|DaumApps|Instagram|FBAN|FBAV|Line\//i.test(ua||'');
export const draftFromItems=items=>Object.fromEntries((items||[]).map(x=>[String(x.to),{amount:x.amount,reason:x.reason}]));
