set local role service_role;
do $test$
declare a text:=repeat('a',64);one text:=repeat('b',64);two text:=repeat('c',64);ep text;board text;v jsonb;before_version int;
begin
 insert into idea_codes_test.room(pin_hash) values(extensions.crypt('1234',extensions.gen_salt('bf')));
 insert into idea_codes_test.admin_sessions values(a,now()+interval '1 hour');
 perform idea_codes_test.rpc('settings',a,'{"names":["회사 하나","회사 둘"],"budget":5000,"minutes":0}');
 select epoch::text,encode(extensions.digest(board_key,'sha256'),'hex') into ep,board from idea_codes_test.room;
 v:=idea_codes_test.rpc('claim',one,jsonb_build_object('epoch',ep,'entryCode','1001'));if v->>'code' is distinct from 'NAME_REQUIRED' then raise exception 'missing name claimed team';end if;
 v:=idea_codes_test.rpc('claim',one,jsonb_build_object('epoch',ep,'entryCode','1001','representativeName',repeat('김',31)));if v->>'code' is distinct from 'NAME_REQUIRED' then raise exception 'unbounded name accepted';end if;
 v:=idea_codes_test.rpc('claim',one,jsonb_build_object('epoch',ep,'entryCode','1001','representativeName',' 김대표 '));if v->'mine'->>'representativeName'<>'김대표' then raise exception 'own identity missing';end if;
 select draft_version into before_version from idea_codes_test.teams where id=1;
 v:=idea_codes_test.rpc('claim',two,jsonb_build_object('epoch',ep,'entryCode','1001','representativeName','악의적 학생'));if v->>'code' is distinct from 'TEAM_IN_USE' then raise exception 'second device stole company';end if;
 if not exists(select 1 from idea_codes_test.teams where id=1 and device_hash=one and representative_name='김대표' and draft_version=before_version) then raise exception 'rejected claim changed owner or draft';end if;
 v:=idea_codes_test.rpc('claim',one,jsonb_build_object('epoch',ep,'entryCode','1001'));if v ? 'error' or (v->'mine'->>'draftVersion')::int<>before_version then raise exception 'same device lost continuation';end if;
 v:=idea_codes_test.rpc('admin',a);if v->'teams'->0->>'representativeName'<>'김대표' then raise exception 'instructor cannot verify identity';end if;
 v:=idea_codes_test.rpc('board',board);if v::text like '%김대표%' or v::text like '%representativeName%' or v ? 'entryCodes' then raise exception 'projector exposed identity or code';end if;
 v:=idea_codes_test.rpc('claim',two,jsonb_build_object('epoch',ep,'entryCode','2001','representativeName','이대표'));if v::text like '%김대표%' or v ? 'investments' or v ? 'entryCodes' then raise exception 'other company identity or results leaked';end if;
 v:=idea_codes_test.rpc('representative_name',repeat('d',64),jsonb_build_object('epoch',ep,'representativeName','탈취'));if v->>'code' is distinct from 'RELEASED' then raise exception 'outsider edited representative';end if;
 perform idea_codes_test.rpc('start',a);
 v:=idea_codes_test.rpc('submit',one,jsonb_build_object('epoch',ep,'confirmed',true,'items','[{"to":2,"amount":5000,"reason":"좋아요"}]'::jsonb));if v ? 'error' then raise exception 'representative could not submit';end if;
 perform idea_codes_test.rpc('release',a,'{"company":1}');
 v:=idea_codes_test.rpc('student',one);if v->'mine'<>'null'::jsonb then raise exception 'released device retained access';end if;
 v:=idea_codes_test.rpc('claim',repeat('d',64),jsonb_build_object('epoch',ep,'entryCode','1001','representativeName','새 대표'));if v->'mine'->>'submitted'<>'true' or jsonb_array_length(v->'mine'->'items')<>1 then raise exception 'replacement lost submitted data';end if;
 update idea_codes_test.teams set representative_name=null where id=2;
 v:=idea_codes_test.rpc('working',two,jsonb_build_object('epoch',ep));if v->>'code' is distinct from 'NAME_REQUIRED' then raise exception 'legacy unnamed device bypass';end if;
 v:=idea_codes_test.rpc('representative_name',two,jsonb_build_object('epoch',ep,'representativeName','기존 대표'));if v ? 'error' then raise exception 'legacy name recovery failed';end if;
 perform idea_codes_test.rpc('reset',a,'{"confirm":"RESET","keep":true}');if exists(select 1 from idea_codes_test.teams where representative_name is not null or joined_at is not null) then raise exception 'reset retained personal names';end if;
end $test$;
