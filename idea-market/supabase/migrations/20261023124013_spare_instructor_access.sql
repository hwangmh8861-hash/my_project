-- Add two spare instructor credentials without changing the existing PIN,
-- classroom state, investments or already authenticated instructor sessions.
create table if not exists idea_private.instructor_credentials (
 id text primary key check(id in ('spare1','spare2')),
 pin_hash text not null,
 created_at timestamptz not null default clock_timestamp()
);
alter table idea_private.instructor_credentials enable row level security;
revoke all on idea_private.instructor_credentials from public,anon,authenticated;
grant select,insert,update on idea_private.instructor_credentials to service_role;

create or replace function idea_private.verify_instructor_pin(p_pin text,p_primary_hash text)
returns boolean language sql stable security invoker set search_path='' as $verify$
 select coalesce(extensions.crypt(p_pin,p_primary_hash)=p_primary_hash,false)
 or exists(select 1 from idea_private.instructor_credentials c
           where extensions.crypt(p_pin,c.pin_hash)=c.pin_hash)
$verify$;
revoke all on function idea_private.verify_instructor_pin(text,text) from public,anon,authenticated;
grant execute on function idea_private.verify_instructor_pin(text,text) to service_role;

create or replace function idea_private.create_spare_instructor(p_slot int default 1)
returns jsonb language plpgsql security invoker set search_path='' as $create$
declare bytes bytea;number int;candidate text;primary_hash text;tries int:=0;
begin
 select pin_hash into primary_hash from idea_private.room where id=1;
 if p_slot is null or p_slot not between 1 and 2 then return jsonb_build_object('error','보조 강사는 1번 또는 2번을 선택해 주세요.');end if;
 loop
  tries:=tries+1;if tries>100000 then raise exception '보조 강사 비밀번호를 만들지 못했습니다.';end if;
  bytes:=extensions.gen_random_bytes(2);number:=get_byte(bytes,0)*256+get_byte(bytes,1);
  if number>=60000 then continue;end if;
  candidate:=lpad((number%10000)::text,4,'0');
  if extensions.crypt(candidate,primary_hash)=primary_hash
     or exists(select 1 from idea_private.instructor_credentials where extensions.crypt(candidate,pin_hash)=pin_hash)
     or exists(select 1 from idea_private.teams where entry_code=candidate)
     or exists(select 1 from generate_series(1,30) g where idea_private.default_entry_code(g)=candidate)
  then continue;end if;
  exit;
 end loop;
 insert into idea_private.instructor_credentials(id,pin_hash) values('spare'||p_slot,extensions.crypt(candidate,extensions.gen_salt('bf')))
 on conflict(id) do update set pin_hash=excluded.pin_hash,created_at=clock_timestamp();
 -- Plaintext is returned only to this authorized creation request, never stored.
 return jsonb_build_object('name','보조 강사 '||p_slot,'slot',p_slot,'pin',candidate);
end $create$;
revoke all on function idea_private.create_spare_instructor(int) from public,anon,authenticated;
grant execute on function idea_private.create_spare_instructor(int) to service_role;

-- Owner-only installer patches the existing RPC instead of replacing its body
-- with a different classroom version. Reused after the pending representative
-- migration so either deployment order preserves the spare login extension.
create or replace function idea_private.install_spare_instructor_login()
returns void language plpgsql security invoker set search_path='' as $install$
declare definition text;login_anchor text:='extensions.crypt(p_data->>''pin'',r.pin_hash)<>r.pin_hash';
 admin_anchor text:='select exists(select 1 from idea_private.admin_sessions where token_hash=p_token and expires>now()) into admin;';
begin
 select pg_get_functiondef('public.idea_market_rpc(text,text,jsonb,text)'::regprocedure) into definition;
 if position('idea_private.verify_instructor_pin(' in definition)=0 then
  if position(login_anchor in definition)=0 then raise exception '강사 로그인 함수 버전이 예상과 다릅니다.';end if;
  definition:=replace(definition,login_anchor,'not idea_private.verify_instructor_pin(p_data->>''pin'',r.pin_hash)');
 end if;
 if position('p_action=''spare_admin''' in definition)=0 then
  if position(admin_anchor in definition)=0 then raise exception '강사 권한 함수 버전이 예상과 다릅니다.';end if;
  definition:=replace(definition,admin_anchor,admin_anchor||$branch$
 if p_action='spare_admin' then
  if not admin then return jsonb_build_object('error','강사 로그인이 필요합니다.','code','UNAUTHORIZED');end if;
  return idea_private.create_spare_instructor(coalesce((p_data->>'slot')::int,1));
 end if;
$branch$);
 end if;
 execute definition;
end $install$;
revoke all on function idea_private.install_spare_instructor_login() from public,anon,authenticated,service_role;
select idea_private.install_spare_instructor_login();
