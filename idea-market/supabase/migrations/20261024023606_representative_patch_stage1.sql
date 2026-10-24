-- Internal text transformation only; no classroom rows are modified.
create or replace function idea_private.representative_patch_stage1(p_definition text) returns text language plpgsql security invoker set search_path='' as $stage$
declare next_definition text;begin
 next_definition:=replace(p_definition,$old0$ end if;

 board:=p_token=encode(extensions.digest(r.board_key,'sha256'),'hex');
 if p_action in ('admin','settings','start','close','display','cancel','release','reset','pin','logout','reissue','restore_code','clear_entry_limits','extend','reveal') and not admin then return jsonb_build_object('error','강사 로그인이 필요합니다.','code','UNAUTHORIZED');end if;
 if board and p_action<>'board' then return jsonb_build_object('error','현황판은 보기 전용입니다.');end if;
 if p_action='board' and not (board or admin) then return jsonb_build_object('error','강사 화면에서 현황판을 열어 주세요.','code','UNAUTHORIZED');end if;
 if p_action in ('claim','working','submit') and (length(p_token)<>64 or (p_data->>'epoch') is distinct from r.epoch::text) then return jsonb_build_object('error','수업이 초기화되었습니다. 다시 접속해 주세요.','code','RESET');end if;
 if p_action='settings' then
  names:=p_data->'names';n:=jsonb_array_length(names);
  if n<2 or n>30 or exists(select 1 from jsonb_array_elements_text(names) x where length(btrim(x))<1 or length(x)>24) or (select count(distinct btrim(x)) from jsonb_array_elements_text(names) x)<>n then return jsonb_build_object('error','회사 이름은 1~24자로 서로 다르게 입력해 주세요. 조 개수는 2~30개입니다.');end if;
$old0$,$new0$ end if;

 board:=p_token=encode(extensions.digest(r.board_key,'sha256'),'hex');
 if p_action in ('admin','settings','start','close','display','cancel','release','reset','pin','logout','reissue','restore_code','clear_entry_limits','extend','reveal','presentation') and not admin then return jsonb_build_object('error','강사 로그인이 필요합니다.','code','UNAUTHORIZED');end if;
 if board and p_action<>'board' then return jsonb_build_object('error','현황판은 보기 전용입니다.');end if;
 if p_action='board' and not (board or admin) then return jsonb_build_object('error','강사 화면에서 현황판을 열어 주세요.','code','UNAUTHORIZED');end if;
 if p_action in ('claim','working','submit','representative_name') and (length(p_token)<>64 or (p_data->>'epoch') is distinct from r.epoch::text) then return jsonb_build_object('error','수업이 초기화되었습니다. 다시 접속해 주세요.','code','RESET');end if;
 if p_action='settings' then
  names:=p_data->'names';n:=jsonb_array_length(names);
  if n<2 or n>30 or exists(select 1 from jsonb_array_elements_text(names) x where length(btrim(x))<1 or length(x)>24) or (select count(distinct btrim(x)) from jsonb_array_elements_text(names) x)<>n then return jsonb_build_object('error','회사 이름은 1~24자로 서로 다르게 입력해 주세요. 조 개수는 2~30개입니다.');end if;
$new0$);
 if next_definition=p_definition then raise exception '대표 제한 적용 기준 0 불일치';end if;
 p_definition:=next_definition;
 return p_definition;end $stage$;
revoke all on function idea_private.representative_patch_stage1(text) from public,anon,authenticated,service_role;
