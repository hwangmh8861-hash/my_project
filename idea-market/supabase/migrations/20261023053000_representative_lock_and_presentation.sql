-- Representative ownership, admin-only identity and projector controls. Existing investments are preserved.
alter table idea_private.teams add column representative_name text check(representative_name is null or (length(btrim(representative_name)) between 1 and 30));
alter table idea_private.teams add column joined_at timestamptz;
alter table idea_private.room add column presentation jsonb not null default '{"page":0,"auto":true,"at":null,"version":0}'::jsonb;
create or replace function public.idea_market_rpc(p_action text,p_token text default '',p_data jsonb default '{}'::jsonb,p_ip text default '') returns jsonb language plpgsql security invoker set search_path='' as $$
declare r idea_private.room%rowtype; t idea_private.teams%rowtype; v jsonb; n int; amt int; total bigint:=0; ids int[]:='{}'; admin boolean:=false; board boolean:=false; changed boolean:=false; tok text; count_attempt int; recent timestamptz; out_json jsonb; mine jsonb; list jsonb; entries jsonb; names jsonb; code_state idea_private.code_attempts%rowtype; failure_count int; retry_at timestamptz; old_codes text[]; login_state idea_private.login_attempts%rowtype; delay_seconds int; stamp timestamptz;
begin
 select * into r from idea_private.room where id=1 for update;
 if not found then return jsonb_build_object('error','수업이 준비되지 않았습니다.');end if;
 if r.status='open' and r.deadline is not null and clock_timestamp()>=r.deadline then update idea_private.room set status='closed',display='awaiting' where id=1 returning * into r;changed:=true;end if;
 if p_action='login' then
  -- p_ip is retained only for RPC signature compatibility. It never identifies a device.
  if p_token !~ '^[0-9a-f]{64}$' then return jsonb_build_object('error','로그인 화면을 새로고침해 주세요.','code','DEVICE_REQUIRED');end if;
  stamp:=clock_timestamp();
  delete from idea_private.login_failures where failed_at<=stamp-interval '15 minutes';
  select count(*) into failure_count from idea_private.login_failures;
  delete from idea_private.login_attempts where seen_at<=stamp-interval '15 minutes' and coalesce(next_at,stamp)<=stamp;
  insert into idea_private.login_attempts(device_hash,next_at) values(p_token,case when failure_count>50 then stamp+interval '30 seconds' else null end) on conflict do nothing;
  select * into login_state from idea_private.login_attempts where device_hash=p_token for update;
  -- A rejected early retry never pushes the deadline forward; other devices cannot steal the slot.
  retry_at:=greatest(login_state.next_at,case when failure_count>50 then login_state.seen_at+interval '30 seconds' else null end);
  if retry_at>stamp then return jsonb_build_object('error','잠시 후 다시 로그인해 주세요.','code','LOGIN_WAIT','retryAfter',least(30,greatest(1,ceil(extract(epoch from retry_at-stamp))::int)));end if;
  if coalesce(p_data->>'pin','') !~ '^[0-9]{4}$' or extensions.crypt(p_data->>'pin',r.pin_hash)<>r.pin_hash then
   insert into idea_private.login_failures default values;
   delay_seconds:=case when failure_count+1>50 then 30 else least(30,2^least(login_state.failures+1,5))::int end;
   update idea_private.login_attempts set failures=failures+1,next_at=stamp+delay_seconds*interval '1 second',seen_at=stamp where device_hash=p_token;
   return jsonb_build_object('error','비밀번호를 확인해 주세요.','code','LOGIN_WAIT','retryAfter',delay_seconds);
  end if;
  delete from idea_private.login_attempts where device_hash=p_token;
  delete from idea_private.admin_sessions where expires<now();
  tok:=encode(extensions.gen_random_bytes(32),'hex');
  insert into idea_private.admin_sessions values(encode(extensions.digest(tok,'sha256'),'hex'),now()+interval '24 hours');
  return jsonb_build_object('token',tok);
 end if;
 select exists(select 1 from idea_private.admin_sessions where token_hash=p_token and expires>now()) into admin;
 board:=p_token=encode(extensions.digest(r.board_key,'sha256'),'hex');
 if p_action in ('admin','settings','start','close','display','cancel','release','reset','pin','logout','reissue','restore_code','clear_entry_limits','extend','reveal','presentation') and not admin then return jsonb_build_object('error','강사 로그인이 필요합니다.','code','UNAUTHORIZED');end if;
 if board and p_action<>'board' then return jsonb_build_object('error','현황판은 보기 전용입니다.');end if;
 if p_action='board' and not (board or admin) then return jsonb_build_object('error','강사 화면에서 현황판을 열어 주세요.','code','UNAUTHORIZED');end if;
 if p_action in ('claim','working','submit','representative_name') and (length(p_token)<>64 or (p_data->>'epoch') is distinct from r.epoch::text) then return jsonb_build_object('error','수업이 초기화되었습니다. 다시 접속해 주세요.','code','RESET');end if;
 if p_action='settings' then
  names:=p_data->'names';n:=jsonb_array_length(names);
  if n<2 or n>30 or exists(select 1 from jsonb_array_elements_text(names) x where length(btrim(x))<1 or length(x)>24) or (select count(distinct btrim(x)) from jsonb_array_elements_text(names) x)<>n then return jsonb_build_object('error','회사 이름은 1~24자로 서로 다르게 입력해 주세요. 조 개수는 2~30개입니다.');end if;
  amt:=(p_data->>'budget')::int;
  if amt<100 or amt>1000000 or amt%100<>0 or (p_data->>'minutes')::int not between 0 and 180 then return jsonb_build_object('error','투자금과 타이머 설정을 확인해 주세요.');end if;
  if n<>(select count(*) from idea_private.teams) and (r.status<>'ready' or exists(select 1 from idea_private.teams where device_hash is not null) or exists(select 1 from idea_private.investments)) then
   if coalesce(p_data->>'confirmReconfigure','')<>'RECONFIGURE' then return jsonb_build_object('error','조 개수를 변경하려면 현재 투자와 학생 접속 초기화를 확인해 주세요.','code','RECONFIGURE_REQUIRED');end if;
   select coalesce(array_agg(entry_code),'{}') into old_codes from idea_private.teams;
   delete from idea_private.investments where id is not null;
   delete from idea_private.teams where id is not null;
   delete from idea_private.code_attempts where device_hash is not null;
   delete from idea_private.code_failures where failed_at is not null;
   for v,n in select value,ordinality::int from jsonb_array_elements(names) with ordinality loop insert into idea_private.teams(id,name,entry_code) values(n,btrim(v#>>'{}'),idea_private.default_entry_code(n));end loop;
   update idea_private.room set status='ready',epoch=gen_random_uuid(),deadline=null,revealed_at=null,display='qr',focus=1 where id=1 returning * into r;
  end if;
  if amt<>r.budget and (r.status<>'ready' or exists(select 1 from idea_private.teams where device_hash is not null)) then return jsonb_build_object('error','투자금 변경은 초기화 후 사용할 수 있습니다.');end if;
  if n<(select count(*) from idea_private.teams) then delete from idea_private.teams where id>n;end if;
  for v,n in select value,ordinality::int from jsonb_array_elements(names) with ordinality loop update idea_private.teams set name=btrim(v#>>'{}') where id=n; if not found then insert into idea_private.teams(id,name,entry_code) values(n,btrim(v#>>'{}'),idea_private.default_entry_code(n));end if;end loop;
  update idea_private.room set budget=amt,timer_minutes=case when status='ready' then (p_data->>'minutes')::int else timer_minutes end where id=1 returning * into r;changed:=true;
 elsif p_action='start' then
  if r.status='open' then return jsonb_build_object('error','이미 투자가 진행 중입니다.');end if;
  update idea_private.room set status='open',display='live',revealed_at=null,deadline=case when timer_minutes>0 then clock_timestamp()+timer_minutes*interval '1 minute' else null end where id=1 returning * into r;changed:=true;
 elsif p_action='close' then
  update idea_private.room set status='closed',display='awaiting' where id=1 returning * into r;changed:=true;
 elsif p_action='extend' then
  if r.status<>'open' or r.deadline is null then return jsonb_build_object('error','타이머로 투자 진행 중일 때만 시간을 늘릴 수 있습니다.');end if;
  update idea_private.room set deadline=deadline+interval '1 minute' where id=1 returning * into r;changed:=true;
 elsif p_action='reveal' then
  if r.status<>'closed' then return jsonb_build_object('error','마감 후 결과를 공개할 수 있습니다.');end if;
  update idea_private.room set display='results',revealed_at=clock_timestamp(),reveal_version=reveal_version+1 where id=1 returning * into r;changed:=true;
 elsif p_action='display' then
  if p_data->>'mode' not in ('qr','live','results','reasons') then return jsonb_build_object('error','잘못된 화면 설정입니다.');end if;
  if p_data->>'mode' in ('results','reasons') and r.status<>'closed' then return jsonb_build_object('error','투자 마감 후 사용할 수 있습니다.');end if;
  if p_data->>'mode'='results' and r.revealed_at is null then return jsonb_build_object('error','결과 공개 버튼을 눌러 주세요.');end if;
  update idea_private.room set display=p_data->>'mode',focus=coalesce((p_data->>'focus')::int,focus) where id=1 returning * into r;changed:=true;
 elsif p_action='presentation' then
  if coalesce(p_data->>'page','') !~ '^[0-9]{1,2}$' or (p_data->>'page')::int>29 or jsonb_typeof(p_data->'auto') is distinct from 'boolean' then return jsonb_build_object('error','넘김 설정을 확인해 주세요.');end if;
  update idea_private.room set presentation=jsonb_build_object('page',(p_data->>'page')::int,'auto',(p_data->>'auto')::boolean,'at',clock_timestamp(),'version',coalesce((presentation->>'version')::int,0)+1) where id=1 returning * into r;changed:=true;
 elsif p_action='representative_name' then
  if length(btrim(coalesce(p_data->>'representativeName',''))) not between 1 and 30 then return jsonb_build_object('error','대표 이름을 1~30자로 입력해 주세요.','code','NAME_REQUIRED');end if;
  update idea_private.teams set representative_name=btrim(p_data->>'representativeName') where device_hash=p_token;
  if not found then return jsonb_build_object('error','기기 연결이 해제됐어요.','code','RELEASED');end if;changed:=true;
 elsif p_action='cancel' then
  n:=(p_data->>'company')::int;
  if r.status='closed' then return jsonb_build_object('error','투자를 다시 연 뒤 제출을 취소해 주세요.');end if;
  select * into t from idea_private.teams where id=n;
  if not found or not t.submitted then return jsonb_build_object('error','제출된 회사만 취소할 수 있습니다.');end if;
  update idea_private.teams set returned_items=(select coalesce(jsonb_agg(jsonb_build_object('to',recipient,'amount',amount,'reason',reason) order by recipient),'[]'::jsonb) from idea_private.investments where sender=n),submitted=false,working=false,draft_version=draft_version+1 where id=n;
  delete from idea_private.investments where sender=n;changed:=true;
 elsif p_action='release' then
  update idea_private.teams set device_hash=null,representative_name=null,joined_at=null,working=false,draft_version=draft_version+1 where id=(p_data->>'company')::int;changed:=true;
 elsif p_action='reset' then
  if (p_data->>'confirm') is distinct from 'RESET' then return jsonb_build_object('error','초기화 확인이 필요합니다.');end if;
  select count(*) into n from idea_private.teams;
  select coalesce(array_agg(code),'{}'::text[]) into old_codes from idea_private.entry_code_history;
  delete from idea_private.entry_code_history where code is not null;
  delete from idea_private.investments where id is not null;
  if coalesce((p_data->>'keep')::boolean,true) then update idea_private.teams set entry_code=idea_private.new_entry_code(old_codes) where id is not null;update idea_private.teams set entry_code=idea_private.default_entry_code(id),device_hash=null,representative_name=null,joined_at=null,working=false,submitted=false,returned_items='[]'::jsonb,draft_version=draft_version+1 where id is not null;
  else delete from idea_private.teams where id is not null;insert into idea_private.teams(id,name,entry_code) select i,i||'조 회사',idea_private.default_entry_code(i) from generate_series(1,n) i;end if;
  update idea_private.room set status='ready',epoch=gen_random_uuid(),deadline=null,revealed_at=null,display='qr',focus=1,budget=case when (p_data->>'keep')::boolean then budget else 5000 end,timer_minutes=case when (p_data->>'keep')::boolean then timer_minutes else 0 end where id=1 returning * into r;changed:=true;
 elsif p_action='pin' then
  if coalesce(p_data->>'pin','') !~ '^\d{4}$' then return jsonb_build_object('error','비밀번호는 숫자 4자리입니다.');end if;
  update idea_private.room set pin_hash=extensions.crypt(p_data->>'pin',extensions.gen_salt('bf')) where id=1;
  delete from idea_private.admin_sessions where token_hash<>p_token;
 elsif p_action='logout' then delete from idea_private.admin_sessions where token_hash=p_token;return jsonb_build_object('ok',true);
 elsif p_action='restore_code' then
  n:=(p_data->>'company')::int;
  if not exists(select 1 from idea_private.teams where id=n) then return jsonb_build_object('error','회사를 찾을 수 없습니다.');end if;
  if exists(select 1 from idea_private.teams where id<>n and entry_code=idea_private.default_entry_code(n)) then return jsonb_build_object('error','다른 회사가 이 기본 코드를 사용 중입니다. 해당 회사 코드를 재발급한 뒤 복원해 주세요.');end if;
  update idea_private.teams set entry_code=idea_private.default_entry_code(n),device_hash=null,representative_name=null,joined_at=null,working=false,draft_version=draft_version+1 where id=n;
  changed:=true;
 elsif p_action='reissue' then
  update idea_private.teams set entry_code=idea_private.new_entry_code(),device_hash=null,representative_name=null,joined_at=null,working=false,draft_version=draft_version+1 where id=(p_data->>'company')::int;
  if not found then return jsonb_build_object('error','회사를 찾을 수 없습니다.');end if;
  changed:=true;
 elsif p_action='clear_entry_limits' then
  delete from idea_private.code_attempts where device_hash is not null;
  delete from idea_private.code_failures where failed_at is not null;
  update idea_private.room set entry_limit_version=entry_limit_version+1 where id=1 returning * into r;changed:=true;
 elsif p_action='claim' then
  stamp:=clock_timestamp();
  delete from idea_private.code_failures where failed_at<=stamp-interval '15 minutes';
  select count(*) into failure_count from idea_private.code_failures;
  insert into idea_private.code_attempts(device_hash,next_at) values(p_token,case when failure_count>100 then stamp+interval '5 seconds' else null end) on conflict do nothing;
  select * into code_state from idea_private.code_attempts where device_hash=p_token for update;
  retry_at:=greatest(code_state.blocked_until,case when failure_count>100 then code_state.next_at else null end);
  if retry_at>stamp then return jsonb_build_object('error','잠시 후 코드를 다시 입력해 주세요.','code','CODE_WAIT','retryAfter',greatest(1,ceil(extract(epoch from retry_at-stamp)))::int);end if;
  if code_state.blocked_until is not null then update idea_private.code_attempts set failures=0,blocked_until=null where device_hash=p_token;code_state.failures:=0;end if;
  update idea_private.code_attempts set next_at=stamp+interval '5 seconds' where device_hash=p_token;
  select * into t from idea_private.teams where entry_code=p_data->>'entryCode' and coalesce(p_data->>'entryCode','') ~ '^[0-9]{4}$';
  if not found then
   insert into idea_private.code_failures default values;
   update idea_private.code_attempts set failures=failures+1,blocked_until=case when failures+1>=5 then stamp+interval '1 minute' else null end where device_hash=p_token returning * into code_state;
   update public.idea_market_signal set revision=revision+1 where id=1;
   if code_state.failures>=5 then return jsonb_build_object('error','코드를 5번 틀렸어요. 1분 후 다시 입력해 주세요.','code','CODE_WAIT','retryAfter',60);end if;
   if failure_count+1>100 then return jsonb_build_object('error','5초 후 코드를 다시 입력해 주세요.','code','CODE_WAIT','retryAfter',5);end if;
   return jsonb_build_object('error','회사 코드를 확인해 주세요.','code','INVALID_CODE','attemptsLeft',5-code_state.failures);
  end if;
  if exists(select 1 from idea_private.teams where device_hash=p_token and id<>t.id) then return jsonb_build_object('error','이미 다른 회사로 접속한 기기입니다.','code','ALREADY_CONNECTED');end if;
  if t.device_hash is not null and t.device_hash<>p_token then return jsonb_build_object('error','이미 대표가 접속한 모둠이에요. 기기를 바꾸려면 강사님께 연결 해제를 요청해 주세요.','code','TEAM_IN_USE');end if;
  if t.device_hash is null and length(btrim(coalesce(p_data->>'representativeName',''))) not between 1 and 30 then return jsonb_build_object('error','대표 이름을 1~30자로 입력해 주세요.','code','NAME_REQUIRED');end if;
  delete from idea_private.code_attempts where device_hash=p_token;
  if t.device_hash is distinct from p_token then
   update idea_private.teams set device_hash=p_token,representative_name=btrim(p_data->>'representativeName'),joined_at=clock_timestamp(),working=false,draft_version=draft_version+1 where id=t.id;
   changed:=true;
  end if;
 elsif p_action in ('working','submit') then
  select * into t from idea_private.teams where device_hash=p_token;
  if not found then return jsonb_build_object('error','기기 연결이 해제되었습니다.','code','RELEASED');end if;
  if r.status<>'open' then
   if changed then update public.idea_market_signal set revision=revision+1 where id=1;end if;
   return jsonb_build_object('error','투자가 마감되었거나 아직 시작되지 않았습니다.','code','CLOSED');
  end if;
  if t.representative_name is null then return jsonb_build_object('error','대표 이름을 먼저 입력해 주세요.','code','NAME_REQUIRED');end if;
  if t.submitted then return jsonb_build_object('error','이미 제출한 회사입니다.','code','SUBMITTED');end if;
  if p_action='working' then if not t.working then update idea_private.teams set working=true where id=t.id;changed:=true;end if;
  else
   if (p_data->>'confirmed') is distinct from 'true' then return jsonb_build_object('error','조원 모두와 상의했는지 확인해 주세요.');end if;
   if jsonb_typeof(p_data->'items')<>'array' or jsonb_array_length(p_data->'items')<1 then return jsonb_build_object('error','투자 내용을 확인해 주세요.');end if;
   for v in select value from jsonb_array_elements(p_data->'items') loop
    if coalesce(v->>'amount','') !~ '^\d+$' or coalesce(v->>'to','') !~ '^\d+$' then return jsonb_build_object('error','금액은 100만 원 단위의 숫자로 입력해 주세요.');end if;
    n:=(v->>'to')::int;amt:=(v->>'amount')::int;
    if n=t.id or n=any(ids) or not exists(select 1 from idea_private.teams where id=n) or amt<=0 or amt%100<>0 or coalesce(v->>'reason','') ~ '^[[:space:]]*$' then return jsonb_build_object('error','자기 회사 투자, 중복 대상, 금액 또는 투자 이유를 확인해 주세요.');end if;
    ids:=array_append(ids,n);total:=total+amt;
   end loop;
   if total<>r.budget then return jsonb_build_object('error','투자금 전액을 배분해 주세요.');end if;
   insert into idea_private.investments(sender,recipient,amount,reason) select t.id,(x->>'to')::int,(x->>'amount')::int,btrim(x->>'reason') from jsonb_array_elements(p_data->'items') x;
   update idea_private.teams set submitted=true,working=false,returned_items='[]'::jsonb where id=t.id;changed:=true;
  end if;
 elsif p_action not in ('student','board','admin','tick') then return jsonb_build_object('error','지원하지 않는 요청입니다.');
 end if;
 if changed and p_action in ('settings','start','close','display','reveal','reset') then
  update idea_private.room set presentation=jsonb_build_object('page',0,'auto',true,'at',clock_timestamp()+case when p_action='reveal' then interval '5 seconds' else interval '0 seconds' end,'version',coalesce((presentation->>'version')::int,0)+1) where id=1 returning * into r;
 end if;
 if p_action='board' then update idea_private.room set board_seen_at=clock_timestamp() where id=1 returning * into r;end if;
 if changed then update public.idea_market_signal set revision=revision+1 where id=1;end if;
 out_json:=jsonb_build_object('status',r.status,'budget',r.budget,'epoch',r.epoch,'deadline',r.deadline,'minutes',r.timer_minutes,'display',r.display,'focus',r.focus,'now',clock_timestamp(),'entryLimitVersion',r.entry_limit_version,'revision',(select revision from public.idea_market_signal where id=1));
 if p_action='tick' then return jsonb_build_object('ok',true);end if;
 if (admin and p_action<>'student') or board then
  select coalesce(jsonb_agg(jsonb_build_object('id',q.id,'name',q.name,'connected',q.device_hash is not null,'working',q.working,'submitted',q.submitted,'total',coalesce((select sum(amount) from idea_private.investments where recipient=q.id),0)) || case when admin and p_action<>'board' then jsonb_build_object('representativeName',q.representative_name,'joinedAt',q.joined_at) else '{}'::jsonb end order by q.id),'[]'::jsonb) into list from idea_private.teams q;
  select coalesce(jsonb_agg(to_jsonb(i) order by created_at desc,id),'[]'::jsonb) into entries from idea_private.investments i;
  out_json:=out_json||jsonb_build_object('teams',list,'investments',entries,'revealedAt',r.revealed_at,'revealVersion',r.reveal_version,'presentation',r.presentation);
  if admin and p_action<>'board' then out_json:=out_json||jsonb_build_object('boardConnected',coalesce(r.board_seen_at>clock_timestamp()-interval '45 seconds',false),'entryLimited',(select count(*)>100 from idea_private.code_failures where failed_at>clock_timestamp()-interval '15 minutes') or exists(select 1 from idea_private.code_attempts where blocked_until>clock_timestamp()),'boardKey',r.board_key,'entryCodes',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'entryCode',entry_code) order by id),'[]'::jsonb) from idea_private.teams));end if;
 else
  select coalesce(jsonb_agg(jsonb_build_object('id',q.id,'name',q.name,'taken',q.device_hash is not null) order by q.id),'[]'::jsonb) into list from idea_private.teams q where exists(select 1 from idea_private.teams me where me.device_hash=p_token);
  select jsonb_build_object('id',id,'name',name,'representativeName',representative_name,'submitted',submitted,'working',working,'draftVersion',draft_version,'items',case when submitted then (select coalesce(jsonb_agg(jsonb_build_object('to',recipient,'amount',amount,'reason',reason) order by recipient),'[]'::jsonb) from idea_private.investments where sender=idea_private.teams.id) else returned_items end) into mine from idea_private.teams where device_hash=p_token;
  out_json:=out_json||jsonb_build_object('teams',list,'mine',mine);
 end if;
 return out_json;
end $$;
revoke all on function public.idea_market_rpc(text,text,jsonb,text) from public,anon,authenticated;
grant execute on function public.idea_market_rpc(text,text,jsonb,text) to service_role;
