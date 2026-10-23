set local role service_role;
do $test$
declare a text:=repeat('a',64);d text:=repeat('b',64);ep text;code1 text;v jsonb;payload jsonb;
begin
 insert into idea_codes_test.room(pin_hash) values(extensions.crypt('1234',extensions.gen_salt('bf')));
 insert into idea_codes_test.teams(id,name) select g,'회사'||g from generate_series(1,7) g;
 insert into idea_codes_test.admin_sessions values(a,now()+interval '1 hour');
 select epoch::text into ep from idea_codes_test.room;select entry_code into code1 from idea_codes_test.teams where id=1;
 perform idea_codes_test.rpc('claim',d,jsonb_build_object('epoch',ep,'representativeName','테스트 대표','entryCode',code1));perform idea_codes_test.rpc('start',a);
 perform idea_codes_test.rpc('submit',d,jsonb_build_object('epoch',ep,'confirmed',true,'items','[{"to":7,"amount":5000,"reason":"좋아요"}]'::jsonb));
 payload:='{"names":["회사1","회사2","회사3","회사4","회사5","회사6"],"budget":5000,"minutes":0}'::jsonb;
 v:=idea_codes_test.rpc('settings',a,payload);
 if v->>'code' is distinct from 'RECONFIGURE_REQUIRED' or (select count(*) from idea_codes_test.investments)<>1 or (select count(*) from idea_codes_test.teams)<>7 then raise exception 'unconfirmed change modified active class';end if;
 v:=idea_codes_test.rpc('settings',d,payload||'{"confirmReconfigure":"RECONFIGURE"}'::jsonb);
 if v->>'code' is distinct from 'UNAUTHORIZED' then raise exception 'student changed count';end if;
 v:=idea_codes_test.rpc('settings',a,payload||'{"confirmReconfigure":"RECONFIGURE"}'::jsonb);
 if v ? 'error' or v->>'status'<>'ready' or v->>'epoch'=ep or jsonb_array_length(v->'teams')<>6 then raise exception '7 to 6 failed: %',v;end if;
 if exists(select 1 from idea_codes_test.investments) or exists(select 1 from idea_codes_test.teams where device_hash is not null or entry_code=code1) then raise exception 'new configuration retained investment or stale connection/code';end if;
 payload:=jsonb_set(payload,'{names}','["회사1","회사2","회사3","회사4","회사5","회사6","회사7","회사8"]'::jsonb);
 v:=idea_codes_test.rpc('settings',a,payload);
 if v ? 'error' or jsonb_array_length(v->'teams')<>8 or (select count(distinct entry_code) from idea_codes_test.teams)<>8 then raise exception '6 to 8 failed';end if;
end $test$;
