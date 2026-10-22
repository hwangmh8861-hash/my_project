set local role service_role;
do $test$
declare a text:=repeat('a',64);bad text:=repeat('b',64);teacher text:=repeat('c',64);student text:=repeat('d',64);ep text;code1 text;v jsonb;deadline_before timestamptz;i int;
begin
 insert into idea_codes_test.room(pin_hash) values(extensions.crypt('1234',extensions.gen_salt('bf')));
 insert into idea_codes_test.teams(id,name) select g,g||'조 회사' from generate_series(1,6) g;
 insert into idea_codes_test.admin_sessions values(a,now()+interval '1 hour');
 select epoch::text into ep from idea_codes_test.room;
 -- All devices share the same IP, but failures affect only the failing device.
 for i in 1..8 loop
  update idea_codes_test.login_attempts set next_at=clock_timestamp()-interval '1 second',seen_at=clock_timestamp()-interval '31 seconds' where device_hash=bad;
  v:=idea_codes_test.rpc('login',bad,'{"pin":"9999"}','same-school-ip');
  if v->>'code' is distinct from 'LOGIN_WAIT' or (v->>'retryAfter')::int>30 then raise exception 'P0-1 unbounded or missing delay';end if;
 end loop;
 v:=idea_codes_test.rpc('login',teacher,'{"pin":"1234"}','same-school-ip');
 if not v ? 'token' then raise exception 'P0-1 shared IP locked instructor';end if;
 insert into idea_codes_test.login_failures select clock_timestamp() from generate_series(1,51);
 v:=idea_codes_test.rpc('login',teacher,'{"pin":"1234"}','same-school-ip');
 if v->>'code' is distinct from 'LOGIN_WAIT' or (v->>'retryAfter')::int>30 then raise exception 'P0-1 global delay missing';end if;
 select next_at into deadline_before from idea_codes_test.login_attempts where device_hash=teacher;
 perform idea_codes_test.rpc('login',teacher,'{"pin":"1234"}','same-school-ip');
 perform idea_codes_test.rpc('login',bad,'{"pin":"9999"}','same-school-ip');
 if (select next_at from idea_codes_test.login_attempts where device_hash=teacher)<>deadline_before then raise exception 'P0-1 retry extended waiting instructor deadline';end if;
 update idea_codes_test.login_attempts set next_at=clock_timestamp()-interval '1 second',seen_at=clock_timestamp()-interval '31 seconds' where device_hash=teacher;
 v:=idea_codes_test.rpc('login',teacher,'{"pin":"1234"}','same-school-ip');
 if not v ? 'token' then raise exception 'P0-1 correct instructor could not login after 30 seconds';end if;
 v:=idea_codes_test.rpc('admin',a);
 if v ? 'error' then raise exception 'P0-1 active instructor session affected';end if;
 -- A global code attack imposes a bounded per-device interval, never a shared gate.
 insert into idea_codes_test.code_failures select clock_timestamp() from generate_series(1,101);
 select entry_code into code1 from idea_codes_test.teams where id=1;
 v:=idea_codes_test.rpc('claim',student,jsonb_build_object('epoch',ep,'entryCode',code1));
 if v->>'code' is distinct from 'CODE_WAIT' or (v->>'retryAfter')::int>5 then raise exception 'P0-2 global code block unbounded';end if;
 select next_at into deadline_before from idea_codes_test.code_attempts where device_hash=student;
 perform idea_codes_test.rpc('claim',student,jsonb_build_object('epoch',ep,'entryCode',code1));
 if (select next_at from idea_codes_test.code_attempts where device_hash=student)<>deadline_before then raise exception 'P0-2 deadline sliding';end if;
 update idea_codes_test.code_attempts set next_at=clock_timestamp()-interval '1 second' where device_hash=student;
 v:=idea_codes_test.rpc('claim',student,jsonb_build_object('epoch',ep,'entryCode',code1));
 if v ? 'error' or v->'mine'->>'id'<>'1' then raise exception 'P0-2 normal code blocked while global failures remain';end if;
 v:=idea_codes_test.rpc('admin',a);if not (v->>'entryLimited')::boolean then raise exception 'P0-2 warning missing';end if;
 v:=idea_codes_test.rpc('clear_entry_limits',student);if v->>'code'<>'UNAUTHORIZED' then raise exception 'student cleared limits';end if;
 v:=idea_codes_test.rpc('clear_entry_limits',a);
 if (v->>'entryLimited')::boolean or exists(select 1 from idea_codes_test.code_failures) or exists(select 1 from idea_codes_test.code_attempts) or v->>'entryLimitVersion'<>'1' then raise exception 'P0-2 reset incomplete';end if;
end $test$;
