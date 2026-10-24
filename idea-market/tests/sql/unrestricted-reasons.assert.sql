set local role service_role;
do $test$
declare a text:=repeat('a',64);d text:=repeat('b',64);ep text;code1 text;result jsonb;reason_value text;
begin
 insert into idea_codes_test.room(pin_hash) values(extensions.crypt('1234',extensions.gen_salt('bf')));
 insert into idea_codes_test.teams(id,name) select g,'회사'||g from generate_series(1,3) g;
 insert into idea_codes_test.admin_sessions values(a,now()+interval '1 hour');
 select epoch::text into ep from idea_codes_test.room;
 select entry_code into code1 from idea_codes_test.teams where id=1;
 perform idea_codes_test.rpc('claim',d,jsonb_build_object('epoch',ep,'representativeName','테스트 대표','entryCode',code1));
 perform idea_codes_test.rpc('start',a);
 foreach reason_value in array array['','   ',E'\n\t \r'] loop
 result:=idea_codes_test.rpc('submit',d,jsonb_build_object('epoch',ep,'confirmed',true,'items',jsonb_build_array(jsonb_build_object('to',2,'amount',5000,'reason',reason_value))));
 if not result ? 'error' then raise exception 'blank reason accepted';end if;
 end loop;
 foreach reason_value in array array['굿',repeat('긴 이유도 잘 보관돼요. ',300)] loop
  result:=idea_codes_test.rpc('submit',d,jsonb_build_object('epoch',ep,'confirmed',true,'items',jsonb_build_array(jsonb_build_object('to',2,'amount',5000,'reason',reason_value))));
  if result ? 'error' then raise exception 'valid nonblank reason rejected: %',result;end if;
  if result->'mine'->'items'->0->>'reason' is distinct from btrim(reason_value) then raise exception 'reason truncated in response';end if;
  if (select reason from idea_codes_test.investments where sender=1) is distinct from btrim(reason_value) then raise exception 'reason truncated in DB';end if;
  result:=idea_codes_test.rpc('student',repeat('c',64));
  if result ? 'investments' or result->'mine' is distinct from 'null'::jsonb then raise exception 'other device received reason';end if;
  perform idea_codes_test.rpc('cancel',a,'{"company":1}');
 end loop;
end $test$;
