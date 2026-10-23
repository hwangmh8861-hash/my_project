-- Dedicated classroom application. All sensitive access is through the Edge Function.
create schema if not exists idea_private;
revoke all on schema idea_private from public,anon,authenticated;
grant usage on schema idea_private to service_role;
create table idea_private.room(
 id int primary key default 1 check(id=1), status text not null default 'ready' check(status in ('ready','open','closed')),
 budget int not null default 5000 check(budget>0 and budget%100=0), epoch uuid not null default gen_random_uuid(),
 deadline timestamptz, timer_minutes int not null default 0, display text not null default 'qr', focus int not null default 1,
 pin_hash text not null, board_key text not null default encode(extensions.gen_random_bytes(32),'hex')
);
create table idea_private.entry_code_history(code text primary key check(code ~ '^[0-9]{4}$'));
create table idea_private.code_attempts(device_hash text primary key, failures int not null default 0, blocked_until timestamptz);
create table idea_private.code_failures(failed_at timestamptz not null default clock_timestamp());
create index code_failures_time on idea_private.code_failures(failed_at);
alter table idea_private.entry_code_history enable row level security;
alter table idea_private.code_attempts enable row level security;
alter table idea_private.code_failures enable row level security;
create function idea_private.new_entry_code(p_excluded text[] default '{}'::text[]) returns text language plpgsql security invoker set search_path='' as $code$
declare bytes bytea; candidate text; value int; tries int:=0;
begin
 loop
  tries:=tries+1;if tries>100000 then raise exception '입장 코드를 발급할 수 없습니다. 수업을 초기화해 주세요.';end if;
  bytes:=extensions.gen_random_bytes(2);value:=get_byte(bytes,0)*256+get_byte(bytes,1);
  if value>=60000 then continue;end if;
  candidate:=lpad((value%10000)::text,4,'0');
  if candidate=any(p_excluded) then continue;end if;
  insert into idea_private.entry_code_history(code) values(candidate) on conflict do nothing;
  if found then return candidate;end if;
 end loop;
end $code$;
revoke all on function idea_private.new_entry_code(text[]) from public,anon,authenticated;
grant execute on function idea_private.new_entry_code(text[]) to service_role;
create table idea_private.teams(id int primary key, name text not null, entry_code text not null unique default idea_private.new_entry_code() check(entry_code ~ '^[0-9]{4}$'), device_hash text unique, working boolean not null default false, submitted boolean not null default false, draft_version int not null default 0);
create table idea_private.investments(id uuid primary key default gen_random_uuid(), sender int not null references idea_private.teams(id), recipient int not null references idea_private.teams(id), amount int not null check(amount>0 and amount%100=0), reason text not null check(char_length(reason) between 10 and 60), created_at timestamptz not null default clock_timestamp(),unique(sender,recipient),check(sender<>recipient));
create table idea_private.admin_sessions(token_hash text primary key, expires timestamptz not null);
create table idea_private.attempts(ip text primary key, count int not null default 0, since timestamptz not null default now());
alter table idea_private.room enable row level security;
alter table idea_private.teams enable row level security;
alter table idea_private.investments enable row level security;
alter table idea_private.admin_sessions enable row level security;
alter table idea_private.attempts enable row level security;
grant all on all tables in schema idea_private to service_role;
create table public.idea_market_signal(id int primary key check(id=1), revision bigint not null default 0);
insert into public.idea_market_signal values(1,0);
alter table public.idea_market_signal enable row level security;
grant select on public.idea_market_signal to anon,authenticated;
grant all on public.idea_market_signal to service_role;
create policy idea_signal_read on public.idea_market_signal for select to anon,authenticated using (true);
alter publication supabase_realtime add table public.idea_market_signal;

create function public.idea_market_rpc(p_action text,p_token text default '',p_data jsonb default '{}'::jsonb,p_ip text default '') returns jsonb language plpgsql security invoker set search_path='' as $$
declare r idea_private.room%rowtype; t idea_private.teams%rowtype; v jsonb; n int; amt int; total bigint:=0; ids int[]:='{}'; admin boolean:=false; board boolean:=false; changed boolean:=false; tok text; count_attempt int; recent timestamptz; out_json jsonb; mine jsonb; list jsonb; entries jsonb; names jsonb; code_state idea_private.code_attempts%rowtype; failure_count int; retry_at timestamptz; old_codes text[];
begin
 select * into r from idea_private.room where id=1 for update;
 if not found then return jsonb_build_object('error','수업이 준비되지 않았습니다.');end if;
 if r.status='open' and r.deadline is not null and clock_timestamp()>=r.deadline then update idea_private.room set status='closed',display='results' where id=1 returning * into r;changed:=true;end if;
 if p_action='login' then
  insert into idea_private.attempts(ip) values(p_ip) on conflict do nothing;
  select count,since into count_attempt,recent from idea_private.attempts where ip=p_ip for update;
  if recent<now()-interval '15 minutes' then count_attempt:=0;update idea_private.attempts set count=0,since=now() where ip=p_ip;end if;
  if count_attempt>=5 then return jsonb_build_object('error','로그인 시도가 많습니다. 15분 후 다시 시도해 주세요.','code','RATE_LIMIT');end if;
  if coalesce(p_data->>'pin','') !~ '^\d{4}$' or extensions.crypt(p_data->>'pin',r.pin_hash)<>r.pin_hash then update idea_private.attempts set count=count+1 where ip=p_ip;return jsonb_build_object('error','비밀번호가 맞지 않습니다.');end if;
  delete from idea_private.attempts where ip=p_ip;
  delete from idea_private.admin_sessions where expires<now();
  tok:=encode(extensions.gen_random_bytes(32),'hex');
  insert into idea_private.admin_sessions values(encode(extensions.digest(tok,'sha256'),'hex'),now()+interval '24 hours');
  return jsonb_build_object('token',tok);
 end if;
 select exists(select 1 from idea_private.admin_sessions where token_hash=p_token and expires>now()) into admin;
 board:=p_token=encode(extensions.digest(r.board_key,'sha256'),'hex');
 if p_action in ('admin','settings','start','close','display','cancel','release','reset','pin','logout','reissue') and not admin then return jsonb_build_object('error','강사 로그인이 필요합니다.','code','UNAUTHORIZED');end if;
 if board and p_action<>'board' then return jsonb_build_object('error','현황판은 보기 전용입니다.');end if;
 if p_action='board' and not (board or admin) then return jsonb_build_object('error','강사 화면에서 현황판을 열어 주세요.','code','UNAUTHORIZED');end if;
 if p_action in ('claim','working','submit') and (length(p_token)<>64 or (p_data->>'epoch') is distinct from r.epoch::text) then return jsonb_build_object('error','수업이 초기화되었습니다. 다시 접속해 주세요.','code','RESET');end if;
 if p_action='settings' then
  names:=p_data->'names';n:=jsonb_array_length(names);
  if n<2 or n>30 or exists(select 1 from jsonb_array_elements_text(names) x where length(btrim(x))<1 or length(x)>24) or (select count(distinct btrim(x)) from jsonb_array_elements_text(names) x)<>n then return jsonb_build_object('error','회사 이름은 1~24자로 서로 다르게 입력해 주세요. 조 개수는 2~30개입니다.');end if;
  amt:=(p_data->>'budget')::int;
  if amt<100 or amt>1000000 or amt%100<>0 or (p_data->>'minutes')::int not between 0 and 180 then return jsonb_build_object('error','투자금과 타이머 설정을 확인해 주세요.');end if;
  if (n<>(select count(*) from idea_private.teams) or amt<>r.budget) and (r.status<>'ready' or exists(select 1 from idea_private.teams where device_hash is not null)) then return jsonb_build_object('error','학생 접속 후에는 조 개수와 투자금을 바꿀 수 없습니다. 초기화 후 변경해 주세요.');end if;
  if n<(select count(*) from idea_private.teams) then delete from idea_private.teams where id>n;end if;
  for v,n in select value,ordinality::int from jsonb_array_elements(names) with ordinality loop update idea_private.teams set name=btrim(v#>>'{}') where id=n; if not found then insert into idea_private.teams(id,name) values(n,btrim(v#>>'{}'));end if;end loop;
  update idea_private.room set budget=amt,timer_minutes=case when status='ready' then (p_data->>'minutes')::int else timer_minutes end where id=1 returning * into r;changed:=true;
 elsif p_action='start' then
  if r.status='open' then return jsonb_build_object('error','이미 투자가 진행 중입니다.');end if;
  update idea_private.room set status='open',display='live',deadline=case when timer_minutes>0 then clock_timestamp()+timer_minutes*interval '1 minute' else null end where id=1 returning * into r;changed:=true;
 elsif p_action='close' then
  update idea_private.room set status='closed',display='results' where id=1 returning * into r;changed:=true;
 elsif p_action='display' then
  if p_data->>'mode' not in ('qr','live','results','reasons') then return jsonb_build_object('error','잘못된 화면 설정입니다.');end if;
  if p_data->>'mode' in ('results','reasons') and r.status<>'closed' then return jsonb_build_object('error','투자 마감 후 사용할 수 있습니다.');end if;
  update idea_private.room set display=p_data->>'mode',focus=coalesce((p_data->>'focus')::int,focus) where id=1 returning * into r;changed:=true;
 elsif p_action='cancel' then
  n:=(p_data->>'company')::int;delete from idea_private.investments where sender=n;update idea_private.teams set submitted=false,working=false,draft_version=draft_version+1 where id=n;changed:=true;
 elsif p_action='release' then
  update idea_private.teams set device_hash=null,working=false,draft_version=draft_version+1 where id=(p_data->>'company')::int;changed:=true;
 elsif p_action='reset' then
  if (p_data->>'confirm') is distinct from 'RESET' then return jsonb_build_object('error','초기화 확인이 필요합니다.');end if;
  select coalesce(array_agg(code),'{}'::text[]) into old_codes from idea_private.entry_code_history;
  delete from idea_private.entry_code_history;
  delete from idea_private.investments;
  if coalesce((p_data->>'keep')::boolean,true) then update idea_private.teams set entry_code=idea_private.new_entry_code(old_codes),device_hash=null,working=false,submitted=false,draft_version=draft_version+1;
  else delete from idea_private.teams;insert into idea_private.teams(id,name,entry_code) select i,i||'조 회사',idea_private.new_entry_code(old_codes) from generate_series(1,7) i;end if;
  update idea_private.room set status='ready',epoch=gen_random_uuid(),deadline=null,display='qr',focus=1,budget=case when (p_data->>'keep')::boolean then budget else 5000 end,timer_minutes=case when (p_data->>'keep')::boolean then timer_minutes else 0 end where id=1 returning * into r;changed:=true;
 elsif p_action='pin' then
  if coalesce(p_data->>'pin','') !~ '^\d{4}$' then return jsonb_build_object('error','비밀번호는 숫자 4자리입니다.');end if;
  update idea_private.room set pin_hash=extensions.crypt(p_data->>'pin',extensions.gen_salt('bf')) where id=1;
  delete from idea_private.admin_sessions where token_hash<>p_token;
 elsif p_action='logout' then delete from idea_private.admin_sessions where token_hash=p_token;return jsonb_build_object('ok',true);
 elsif p_action='reissue' then
  update idea_private.teams set entry_code=idea_private.new_entry_code(),device_hash=null,working=false,draft_version=draft_version+1 where id=(p_data->>'company')::int;
  if not found then return jsonb_build_object('error','회사를 찾을 수 없습니다.');end if;
  changed:=true;
 elsif p_action='claim' then
  delete from idea_private.code_failures where failed_at<=clock_timestamp()-interval '15 minutes';
  select count(*),min(failed_at)+interval '15 minutes' into failure_count,retry_at from idea_private.code_failures;
  if failure_count>100 then return jsonb_build_object('error','입력 실패가 많아 잠시 입장이 제한됩니다.','code','CODE_WAIT','retryAfter',greatest(1,ceil(extract(epoch from retry_at-clock_timestamp())))::int);end if;
  insert into idea_private.code_attempts(device_hash) values(p_token) on conflict do nothing;
  select * into code_state from idea_private.code_attempts where device_hash=p_token for update;
  if code_state.blocked_until>clock_timestamp() then return jsonb_build_object('error','코드 입력을 5회 실패했습니다. 잠시 후 다시 입력해 주세요.','code','CODE_WAIT','retryAfter',greatest(1,ceil(extract(epoch from code_state.blocked_until-clock_timestamp())))::int);end if;
  if code_state.blocked_until is not null then update idea_private.code_attempts set failures=0,blocked_until=null where device_hash=p_token;code_state.failures:=0;end if;
  select * into t from idea_private.teams where entry_code=p_data->>'entryCode' and coalesce(p_data->>'entryCode','') ~ '^[0-9]{4}$';
  if not found then
   insert into idea_private.code_failures default values;
   failure_count:=failure_count+1;
   update idea_private.code_attempts set failures=failures+1,blocked_until=case when failures+1>=5 then clock_timestamp()+interval '1 minute' else null end where device_hash=p_token returning * into code_state;
   if failure_count>100 then select min(failed_at)+interval '15 minutes' into retry_at from idea_private.code_failures;return jsonb_build_object('error','입력 실패가 많아 잠시 입장이 제한됩니다.','code','CODE_WAIT','retryAfter',greatest(1,ceil(extract(epoch from retry_at-clock_timestamp())))::int);end if;
   if code_state.failures>=5 then return jsonb_build_object('error','코드 입력을 5회 실패했습니다. 1분 후 다시 입력해 주세요.','code','CODE_WAIT','retryAfter',60);end if;
   return jsonb_build_object('error','회사 코드를 확인해 주세요.','code','INVALID_CODE','attemptsLeft',5-code_state.failures);
  end if;
  if exists(select 1 from idea_private.teams where device_hash=p_token and id<>t.id) then return jsonb_build_object('error','이미 다른 회사로 접속한 기기입니다.','code','ALREADY_CONNECTED');end if;
  delete from idea_private.code_attempts where device_hash=p_token;
  if t.device_hash is distinct from p_token then
   update idea_private.teams set device_hash=p_token,working=false,draft_version=draft_version+1 where id=t.id;
   changed:=true;
  end if;
 elsif p_action in ('working','submit') then
  select * into t from idea_private.teams where device_hash=p_token;
  if not found then return jsonb_build_object('error','기기 연결이 해제되었습니다.','code','RELEASED');end if;
  if r.status<>'open' then
   if changed then update public.idea_market_signal set revision=revision+1 where id=1;end if;
   return jsonb_build_object('error','투자가 마감되었거나 아직 시작되지 않았습니다.','code','CLOSED');
  end if;
  if t.submitted then return jsonb_build_object('error','이미 제출한 회사입니다.','code','SUBMITTED');end if;
  if p_action='working' then if not t.working then update idea_private.teams set working=true where id=t.id;changed:=true;end if;
  else
   if (p_data->>'confirmed') is distinct from 'true' then return jsonb_build_object('error','조원 모두와 상의했는지 확인해 주세요.');end if;
   if jsonb_typeof(p_data->'items')<>'array' or jsonb_array_length(p_data->'items')<1 then return jsonb_build_object('error','투자 내용을 확인해 주세요.');end if;
   for v in select value from jsonb_array_elements(p_data->'items') loop
    if coalesce(v->>'amount','') !~ '^\d+$' or coalesce(v->>'to','') !~ '^\d+$' then return jsonb_build_object('error','금액은 100만 원 단위의 숫자로 입력해 주세요.');end if;
    n:=(v->>'to')::int;amt:=(v->>'amount')::int;
    if n=t.id or n=any(ids) or not exists(select 1 from idea_private.teams where id=n) or amt<=0 or amt%100<>0 or char_length(btrim(coalesce(v->>'reason',''))) not between 10 and 60 then return jsonb_build_object('error','자기 회사 투자, 중복 대상, 금액 또는 투자 이유를 확인해 주세요.');end if;
    ids:=array_append(ids,n);total:=total+amt;
   end loop;
   if total<>r.budget then return jsonb_build_object('error','투자금 전액을 배분해 주세요.');end if;
   insert into idea_private.investments(sender,recipient,amount,reason) select t.id,(x->>'to')::int,(x->>'amount')::int,btrim(x->>'reason') from jsonb_array_elements(p_data->'items') x;
   update idea_private.teams set submitted=true,working=false where id=t.id;changed:=true;
  end if;
 elsif p_action not in ('student','board','admin','tick') then return jsonb_build_object('error','지원하지 않는 요청입니다.');
 end if;
 if changed then update public.idea_market_signal set revision=revision+1 where id=1;end if;
 out_json:=jsonb_build_object('status',r.status,'budget',r.budget,'epoch',r.epoch,'deadline',r.deadline,'minutes',r.timer_minutes,'display',r.display,'focus',r.focus,'now',clock_timestamp(),'revision',(select revision from public.idea_market_signal where id=1));
 if p_action='tick' then return jsonb_build_object('ok',true);end if;
 if (admin and p_action<>'student') or board then
  select coalesce(jsonb_agg(jsonb_build_object('id',q.id,'name',q.name,'connected',q.device_hash is not null,'working',q.working,'submitted',q.submitted,'total',coalesce((select sum(amount) from idea_private.investments where recipient=q.id),0)) order by q.id),'[]'::jsonb) into list from idea_private.teams q;
  select coalesce(jsonb_agg(to_jsonb(i) order by created_at desc,id),'[]'::jsonb) into entries from idea_private.investments i;
  out_json:=out_json||jsonb_build_object('teams',list,'investments',entries);
  if admin and p_action<>'board' then out_json:=out_json||jsonb_build_object('boardKey',r.board_key,'entryCodes',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'entryCode',entry_code) order by id),'[]'::jsonb) from idea_private.teams));end if;
 else
  select coalesce(jsonb_agg(jsonb_build_object('id',q.id,'name',q.name,'taken',q.device_hash is not null) order by q.id),'[]'::jsonb) into list from idea_private.teams q where exists(select 1 from idea_private.teams me where me.device_hash=p_token);
  select jsonb_build_object('id',id,'name',name,'submitted',submitted,'working',working,'draftVersion',draft_version) into mine from idea_private.teams where device_hash=p_token;
  out_json:=out_json||jsonb_build_object('teams',list,'mine',mine);
 end if;
 return out_json;
end $$;
revoke all on function public.idea_market_rpc(text,text,jsonb,text) from public,anon,authenticated;
grant execute on function public.idea_market_rpc(text,text,jsonb,text) to service_role;
