set local role service_role;
do $test$
declare a text:=repeat('a',64);d text:=repeat('b',64);ep text;code1 text;v jsonb;
begin
 insert into idea_codes_test.room(pin_hash) values(extensions.crypt('1234',extensions.gen_salt('bf')));
 insert into idea_codes_test.teams(id,name,entry_code) select g,'회사'||g,idea_codes_test.default_entry_code(g) from generate_series(1,7) g;
 insert into idea_codes_test.admin_sessions values(a,now()+interval '1 hour');
 select epoch::text into ep from idea_codes_test.room;
 perform idea_codes_test.rpc('claim',d,jsonb_build_object('epoch',ep,'representativeName','테스트 대표','entryCode','1001'));perform idea_codes_test.rpc('start',a);
 perform idea_codes_test.rpc('submit',d,jsonb_build_object('epoch',ep,'confirmed',true,'items','[{"to":2,"amount":5000,"reason":"좋아요"}]'::jsonb));
 perform idea_codes_test.rpc('reissue',a,'{"company":1}');select entry_code into code1 from idea_codes_test.teams where id=1;
 if code1='1001' or exists(select 1 from generate_series(1,30) g where idea_codes_test.default_entry_code(g)=code1) then raise exception 'reissued code collides with defaults';end if;
 v:=idea_codes_test.rpc('restore_code',d,'{"company":1}');if v->>'code' is distinct from 'UNAUTHORIZED' then raise exception 'student restored code';end if;
 v:=idea_codes_test.rpc('restore_code',a,'{"company":1}');if v ? 'error' or (select entry_code from idea_codes_test.teams where id=1)<>'1001' or (select count(*) from idea_codes_test.investments)<>1 then raise exception 'restore lost investment or code';end if;
 perform idea_codes_test.rpc('reset',a,'{"confirm":"RESET","keep":true}');
 if exists(select 1 from idea_codes_test.teams where entry_code<>idea_codes_test.default_entry_code(id) or device_hash is not null) then raise exception 'kept settings reset did not restore default codes';end if;
 perform idea_codes_test.rpc('reissue',a,'{"company":2}');perform idea_codes_test.rpc('reset',a,'{"confirm":"RESET","keep":false}');
 if exists(select 1 from idea_codes_test.teams where entry_code<>idea_codes_test.default_entry_code(id)) or (select count(*) from idea_codes_test.teams)<>7 then raise exception 'default reset failed';end if;
 if (select count(distinct idea_codes_test.default_entry_code(g)) from generate_series(1,30) g)<>30 or exists(select 1 from generate_series(1,30) g where idea_codes_test.default_entry_code(g) !~ '^[0-9]{4}$') then raise exception 'default 30 codes invalid';end if;
end $test$;
