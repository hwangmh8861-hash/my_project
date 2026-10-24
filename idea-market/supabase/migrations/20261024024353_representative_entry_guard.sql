-- Add only leader identity and exclusive company ownership to the current RPC.
-- Existing financial validation, access delays and spare credentials are preserved.
do $install$ declare definition text;next_definition text;begin
 select pg_get_functiondef('public.idea_market_rpc(text,text,jsonb,text)'::regprocedure) into definition;
 if position('TEAM_IN_USE' in definition)>0 then return;end if;
 next_definition:=replace(definition,$old0$p_action in ('claim','working','submit')$old0$,$new0$p_action in ('claim','working','submit','representative_name')$new0$);
 if next_definition=definition then raise exception '조장 입장 적용 기준 0 불일치';end if;definition:=next_definition;
 next_definition:=replace(definition,$old1$ elsif p_action='cancel' then$old1$,$new1$ elsif p_action='representative_name' then
  if length(btrim(coalesce(p_data->>'representativeName',''))) not between 1 and 30 then return jsonb_build_object('error','대표 이름을 1~30자로 입력해 주세요.','code','NAME_REQUIRED');end if;
  update idea_private.teams set representative_name=btrim(p_data->>'representativeName') where device_hash=p_token;
  if not found then return jsonb_build_object('error','기기 연결이 해제됐어요.','code','RELEASED');end if;changed:=true;
 elsif p_action='cancel' then$new1$);
 if next_definition=definition then raise exception '조장 입장 적용 기준 1 불일치';end if;definition:=next_definition;
 next_definition:=replace(definition,$old2$  if exists(select 1 from idea_private.teams where device_hash=p_token and id<>t.id) then return jsonb_build_object('error','이미 다른 회사로 접속한 기기입니다.','code','ALREADY_CONNECTED');end if;
$old2$,$new2$  if exists(select 1 from idea_private.teams where device_hash=p_token and id<>t.id) then return jsonb_build_object('error','이미 다른 회사로 접속한 기기입니다.','code','ALREADY_CONNECTED');end if;
  if t.device_hash is not null and t.device_hash<>p_token then return jsonb_build_object('error','이미 대표가 접속한 모둠이에요. 기기를 바꾸려면 강사님께 연결 해제를 요청해 주세요.','code','TEAM_IN_USE');end if;
  if t.device_hash is null and length(btrim(coalesce(p_data->>'representativeName',''))) not between 1 and 30 then return jsonb_build_object('error','대표 이름을 1~30자로 입력해 주세요.','code','NAME_REQUIRED');end if;
$new2$);
 if next_definition=definition then raise exception '조장 입장 적용 기준 2 불일치';end if;definition:=next_definition;
 next_definition:=replace(definition,$old3$set device_hash=p_token,working=false,draft_version=draft_version+1$old3$,$new3$set device_hash=p_token,representative_name=btrim(p_data->>'representativeName'),joined_at=clock_timestamp(),working=false,draft_version=draft_version+1$new3$);
 if next_definition=definition then raise exception '조장 입장 적용 기준 3 불일치';end if;definition:=next_definition;
 next_definition:=replace(definition,$old4$  if t.submitted then return jsonb_build_object('error','이미 제출한 회사입니다.','code','SUBMITTED');end if;
$old4$,$new4$  if t.submitted then return jsonb_build_object('error','이미 제출한 회사입니다.','code','SUBMITTED');end if;
  if t.representative_name is null then return jsonb_build_object('error','조장 이름을 입력해 주세요.','code','NAME_REQUIRED');end if;
$new4$);
 if next_definition=definition then raise exception '조장 입장 적용 기준 4 불일치';end if;definition:=next_definition;
 next_definition:=replace(definition,$old5$device_hash=null,working=false$old5$,$new5$device_hash=null,representative_name=null,joined_at=null,working=false$new5$);
 if next_definition=definition then raise exception '조장 입장 적용 기준 5 불일치';end if;definition:=next_definition;
 next_definition:=replace(definition,$old6$'total',coalesce((select sum(amount) from idea_private.investments where recipient=q.id),0)) order by q.id$old6$,$new6$'total',coalesce((select sum(amount) from idea_private.investments where recipient=q.id),0)) || case when admin and p_action<>'board' then jsonb_build_object('representativeName',q.representative_name,'joinedAt',q.joined_at) else '{}'::jsonb end order by q.id$new6$);
 if next_definition=definition then raise exception '조장 입장 적용 기준 6 불일치';end if;definition:=next_definition;
 next_definition:=replace(definition,$old7$jsonb_build_object('id',id,'name',name,'submitted'$old7$,$new7$jsonb_build_object('id',id,'name',name,'representativeName',representative_name,'submitted'$new7$);
 if next_definition=definition then raise exception '조장 입장 적용 기준 7 불일치';end if;definition:=next_definition;
 execute definition;
end $install$;
