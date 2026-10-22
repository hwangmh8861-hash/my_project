-- Keep the class, codes, device sessions and submitted investments when reopening.
do $patch$
declare body text;
begin
 body:=pg_get_functiondef('public.idea_market_rpc(text,text,jsonb,text)'::regprocedure);
 if strpos(body, '이미 투자가 진행 중입니다.')>0 then return;end if;
 if strpos(body, '이미 시작했거나 마감된 수업입니다.')=0 then raise exception 'Unexpected start guard; migration needs review';end if;
 body:=replace(body, 'if r.status<>''ready'' then return jsonb_build_object(''error'',''이미 시작했거나 마감된 수업입니다.'');end if;', 'if r.status=''open'' then return jsonb_build_object(''error'',''이미 투자가 진행 중입니다.'');end if;');
 execute body;
end $patch$;
