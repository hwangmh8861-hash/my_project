set local role service_role;
do $test$
declare a text:=repeat('a',64);b text;v jsonb;before_time timestamptz;
begin
 insert into idea_codes_test.room(pin_hash,timer_minutes) values(extensions.crypt('1234',extensions.gen_salt('bf')),5);
 insert into idea_codes_test.teams(id,name) values(1,'회사1'),(2,'회사2');
 insert into idea_codes_test.admin_sessions values(a,now()+interval '1 hour');
 select encode(extensions.digest(board_key,'sha256'),'hex') into b from idea_codes_test.room;
 v:=idea_codes_test.rpc('admin',a);if (v->>'boardConnected')::boolean then raise exception 'board falsely connected';end if;
 perform idea_codes_test.rpc('board',b);v:=idea_codes_test.rpc('admin',a);if not (v->>'boardConnected')::boolean then raise exception 'board heartbeat missing';end if;
 update idea_codes_test.room set board_seen_at=clock_timestamp()-interval '46 seconds';v:=idea_codes_test.rpc('admin',a);if (v->>'boardConnected')::boolean then raise exception 'board heartbeat expiry broken';end if;
 perform idea_codes_test.rpc('start',a);select deadline into before_time from idea_codes_test.room;perform idea_codes_test.rpc('extend',a);
 if (select deadline from idea_codes_test.room)<>before_time+interval '1 minute' then raise exception 'extension incorrect';end if;
 v:=idea_codes_test.rpc('extend',repeat('d',64));if v->>'code'<>'UNAUTHORIZED' then raise exception 'student extended timer';end if;
 perform idea_codes_test.rpc('close',a);v:=idea_codes_test.rpc('board',b);if v->>'revealedAt' is not null then raise exception 'automatic reveal on close';end if;
 v:=idea_codes_test.rpc('display',a,'{"mode":"results"}');if not v ? 'error' then raise exception 'implicit reveal allowed';end if;
 v:=idea_codes_test.rpc('reveal',a);if v->>'revealedAt' is null or v->>'revealVersion'<>'1' then raise exception 'explicit reveal missing';end if;
 perform idea_codes_test.rpc('start',a);v:=idea_codes_test.rpc('close',a);if v->>'revealedAt' is not null then raise exception 'new close reused old reveal';end if;
end $test$;
