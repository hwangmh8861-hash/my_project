set local role service_role;
do $test$
declare a text:=repeat('a',64);d text:=repeat('b',64);other text:=repeat('c',64);ep text;code1 text;v jsonb;payload jsonb;version_before int;
begin
 insert into idea_codes_test.room(pin_hash) values(extensions.crypt('1234',extensions.gen_salt('bf')));
 insert into idea_codes_test.teams(id,name) select g,'기존 회사'||g from generate_series(1,6) g;
 insert into idea_codes_test.admin_sessions values(a,now()+interval '1 hour');
 select epoch::text into ep from idea_codes_test.room;
 select entry_code into code1 from idea_codes_test.teams where id=1;
 perform idea_codes_test.rpc('claim',d,jsonb_build_object('epoch',ep,'entryCode',code1));
 perform idea_codes_test.rpc('start',a);
 payload:=jsonb_build_object('epoch',ep,'confirmed',true,'items','[{"to":2,"amount":3500,"reason":"여러 사람이 겪는 문제라서 수요가 충분할 것 같아요"},{"to":3,"amount":1500,"reason":"실제로 쉽게 사용할 수 있는 좋은 아이디어 같아요"}]'::jsonb);
 v:=idea_codes_test.rpc('submit',d,payload);if v ? 'error' then raise exception 'initial submission failed';end if;
 if jsonb_array_length(v->'mine'->'items')<>2 then raise exception 'own submitted summary missing';end if;
 select draft_version into version_before from idea_codes_test.teams where id=1;
 perform idea_codes_test.rpc('cancel',a,'{"company":1}');
 v:=idea_codes_test.rpc('student',d);
 if v->'mine'->'items'<>payload->'items' or (v->'mine'->>'submitted')::boolean or (v->'mine'->>'draftVersion')::int<=version_before then raise exception 'P0-3 cancelled submission not restored';end if;
 if exists(select 1 from idea_codes_test.investments) then raise exception 'cancelled investment still counted';end if;
 v:=idea_codes_test.rpc('student',other);if v->'mine'<>'null'::jsonb or v ? 'investments' or v ? 'items' then raise exception 'other device received returned items';end if;
 select entry_code into code1 from idea_codes_test.teams where id=2;
 perform idea_codes_test.rpc('claim',other,jsonb_build_object('epoch',ep,'entryCode',code1));
 v:=idea_codes_test.rpc('student',other);if v->'mine'->'items'<>'[]'::jsonb then raise exception 'other company received returned items';end if;
 v:=idea_codes_test.rpc('submit',d,payload);if v ? 'error' then raise exception 'restored submission could not resubmit';end if;
 perform idea_codes_test.rpc('close',a);v:=idea_codes_test.rpc('cancel',a,'{"company":1}');if not v ? 'error' then raise exception 'cancelled after close';end if;
 v:=idea_codes_test.rpc('reset',a,'{"confirm":"RESET","keep":false}');
 if jsonb_array_length(v->'teams')<>6 or exists(select 1 from idea_codes_test.teams where name<>id||'조 회사' or returned_items<>'[]'::jsonb) then raise exception 'P0-4 reset changed team count or retained old data';end if;
 if v->>'budget'<>'5000' or v->>'status'<>'ready' then raise exception 'reset defaults incorrect';end if;
end $test$;
