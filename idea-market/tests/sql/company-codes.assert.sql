-- This body is composed with an isolated schema and executed within BEGIN/ROLLBACK.
set local role service_role;
do $test$
declare
 a text:=repeat('a',64);d1 text:=repeat('b',64);d2 text:=repeat('c',64);d3 text:=repeat('d',64); stranger text:=repeat('e',64);
 result jsonb; config jsonb; code1 text; old_code text; wrong text; ep text; board text; before_epoch text; previous_codes text[]; failures int;
begin
 insert into idea_codes_test.room(pin_hash) values(extensions.crypt('1234',extensions.gen_salt('bf')));
 insert into idea_codes_test.teams(id,name) values(1,'첫 번째 회사'),(2,'두 번째 회사'),(3,'세 번째 회사');
 insert into idea_codes_test.admin_sessions values(a,now()+interval '1 hour');
 select epoch::text,encode(extensions.digest(board_key,'sha256'),'hex') into ep,board from idea_codes_test.room;
 result:=idea_codes_test.rpc('admin',a);
 if jsonb_array_length(result->'entryCodes')<>3 then raise exception 'admin codes missing';end if;
 if (select count(distinct entry_code) from idea_codes_test.teams)<>3 or exists(select 1 from idea_codes_test.teams where entry_code !~ '^[0-9]{4}$') then raise exception 'invalid codes';end if;
 select entry_code into code1 from idea_codes_test.teams where id=1;
 select lpad(i::text,4,'0') into wrong from generate_series(0,9999) i where lpad(i::text,4,'0') not in(select entry_code from idea_codes_test.teams) limit 1;
 result:=idea_codes_test.rpc('student',stranger);
 if result ? 'entryCodes' or result ? 'investments' or jsonb_array_length(result->'teams')<>0 then raise exception 'pre-entry disclosure';end if;
 -- Old company-id route must not allow entry.
 result:=idea_codes_test.rpc('claim',stranger,jsonb_build_object('epoch',ep,'company',1));
 if result->>'code' is distinct from 'INVALID_CODE' then raise exception 'legacy company claim allowed';end if;
 -- Five wrong attempts lock this device for one minute, even with the correct code.
 for failures in 1..5 loop
  result:=idea_codes_test.rpc('claim',d1,jsonb_build_object('epoch',ep,'representativeName','테스트 대표','entryCode',wrong));
 end loop;
 if result->>'code' is distinct from 'CODE_WAIT' or (result->>'retryAfter')::int is distinct from 60 then raise exception 'fifth failure did not lock';end if;
 result:=idea_codes_test.rpc('claim',d1,jsonb_build_object('epoch',ep,'representativeName','테스트 대표','entryCode',code1));
 if result->>'code' is distinct from 'CODE_WAIT' then raise exception 'correct code bypassed device lock';end if;
 -- Simulate elapsed wait in test-only data.
 update idea_codes_test.code_attempts set blocked_until=clock_timestamp()-interval '1 second' where device_hash=d1;
 result:=idea_codes_test.rpc('claim',d1,jsonb_build_object('epoch',ep,'representativeName','테스트 대표','entryCode',code1));
 if (result->'mine'->>'id')::int is distinct from 1 then raise exception 'entry after wait failed';end if;
 if result ? 'entryCodes' or result ? 'investments' or result->'teams'->0 ? 'entry_code' then raise exception 'student secrets/results leaked';end if;
 result:=idea_codes_test.rpc('claim',d2,jsonb_build_object('epoch',ep,'representativeName','테스트 대표','entryCode',code1));
 if result->>'code' is distinct from 'TEAM_IN_USE' then raise exception 'second device stole connected company';end if;
 perform idea_codes_test.rpc('release',a,'{"company":1}');
 result:=idea_codes_test.rpc('claim',d2,jsonb_build_object('epoch',ep,'representativeName','새 대표','entryCode',code1));
 if result ? 'error' then raise exception 'released company could not reconnect';end if;
 result:=idea_codes_test.rpc('student',d1);
 if result->'mine' is distinct from 'null'::jsonb or jsonb_array_length(result->'teams')<>0 then raise exception 'old device still connected';end if;
 result:=idea_codes_test.rpc('working',d1,jsonb_build_object('epoch',ep));
 if result->>'code' is distinct from 'RELEASED' then raise exception 'revoked device can work';end if;
 -- Submission regression checks.
 perform idea_codes_test.rpc('start',a);
 result:=idea_codes_test.rpc('submit',d2,jsonb_build_object('epoch',ep,'confirmed',true,'items',jsonb_build_array(jsonb_build_object('to',1,'amount',5000,'reason','실제로 활용 가능한 좋은 아이디어입니다.'))));
 if not result ? 'error' then raise exception 'self investment allowed';end if;
 result:=idea_codes_test.rpc('submit',d2,jsonb_build_object('epoch',ep,'confirmed',true,'items',jsonb_build_array(jsonb_build_object('to',2,'amount',5000,'reason','실제로 활용 가능한 좋은 아이디어입니다.'))));
 if result ? 'error' or (result->'mine'->>'submitted')::boolean is distinct from true then raise exception 'valid submission failed';end if;
 -- Reopening preserves data and restarts timer; only instructor may reopen.
 perform idea_codes_test.rpc('close',a);
 update idea_codes_test.room set timer_minutes=5;
 result:=idea_codes_test.rpc('start',stranger);
 if result->>'code' is distinct from 'UNAUTHORIZED' then raise exception 'student reopened class';end if;
 result:=idea_codes_test.rpc('start',a);
 if result->>'status' is distinct from 'open' or result->>'epoch' is distinct from ep then raise exception 'class did not reopen';end if;
 if not exists(select 1 from idea_codes_test.teams where id=1 and submitted and device_hash=d2 and entry_code=code1) or not exists(select 1 from idea_codes_test.investments where sender=1) then raise exception 'reopen lost submission or connection';end if;
 if not exists(select 1 from idea_codes_test.room where deadline>clock_timestamp()+interval '4 minutes') then raise exception 'reopen timer did not restart';end if;
 result:=idea_codes_test.rpc('start',a);
 if not result ? 'error' then raise exception 'double start allowed';end if;

 perform idea_codes_test.rpc('release',a,'{"company":1}');
 result:=idea_codes_test.rpc('claim',d3,jsonb_build_object('epoch',ep,'representativeName','테스트 대표','entryCode',code1));
 if (result->'mine'->>'submitted')::boolean is distinct from true then raise exception 'submitted state lost during takeover';end if;
 result:=idea_codes_test.rpc('submit',d3,jsonb_build_object('epoch',ep,'confirmed',true,'items',jsonb_build_array(jsonb_build_object('to',2,'amount',5000,'reason','실제로 활용 가능한 좋은 아이디어입니다.'))));
 if result->>'code' is distinct from 'SUBMITTED' then raise exception 'duplicate submission allowed';end if;
 -- Regeneration revokes connection and old code, retains submission.
 old_code:=code1;
 result:=idea_codes_test.rpc('reissue',a,'{"company":1}');
 select entry_code into code1 from idea_codes_test.teams where id=1;
 if code1=old_code then raise exception 'reissue reused old code';end if;
 result:=idea_codes_test.rpc('claim',d1,jsonb_build_object('epoch',ep,'representativeName','테스트 대표','entryCode',old_code));
 if result->>'code' is distinct from 'INVALID_CODE' then raise exception 'revoked code accepted';end if;
 result:=idea_codes_test.rpc('student',d3);
 if result->'mine' is distinct from 'null'::jsonb then raise exception 'reissue did not revoke old device';end if;
 result:=idea_codes_test.rpc('claim',d1,jsonb_build_object('epoch',ep,'representativeName','테스트 대표','entryCode',code1));
 if (result->'mine'->>'submitted')::boolean is distinct from true then raise exception 'reissue lost submission';end if;
 -- Board and students never receive code fields, even admin using board action.
 result:=idea_codes_test.rpc('board',board);
 if result ? 'entryCodes' or result ? 'entry_code' or result->'teams'->0 ? 'entryCode' then raise exception 'board codes leaked';end if;
 result:=idea_codes_test.rpc('board',a);
 if result ? 'entryCodes' then raise exception 'admin board codes leaked';end if;
 result:=idea_codes_test.rpc('student',a);
 if result ? 'entryCodes' or result ? 'investments' then raise exception 'admin student response leaked';end if;
 result:=idea_codes_test.rpc('reissue',d1,'{"company":1}');
 if result->>'code' is distinct from 'UNAUTHORIZED' then raise exception 'student reissued code';end if;
 -- All investment validation remains on the server.
 perform idea_codes_test.rpc('cancel',a,'{"company":1}');
 for config in select value from jsonb_array_elements('[{"to":2,"amount":4900,"reason":"실제로 활용 가능한 좋은 아이디어입니다."},{"to":2,"amount":4950,"reason":"실제로 활용 가능한 좋은 아이디어입니다."},{"to":2,"amount":5000,"reason":"   "},{"to":99,"amount":5000,"reason":"실제로 활용 가능한 좋은 아이디어입니다."}]'::jsonb) loop
  result:=idea_codes_test.rpc('submit',d1,jsonb_build_object('epoch',ep,'confirmed',true,'items',jsonb_build_array(config)));
  if not result ? 'error' then raise exception 'investment validation bypass: %',config->>'amount';end if;
 end loop;
 result:=idea_codes_test.rpc('submit',d1,jsonb_build_object('epoch',ep,'confirmed',false,'items',jsonb_build_array(jsonb_build_object('to',2,'amount',5000,'reason','실제로 활용 가능한 좋은 아이디어입니다.'))));
 if not result ? 'error' then raise exception 'consent check bypassed';end if;
 -- More than 100 failures introduces at most five seconds between attempts.
 insert into idea_codes_test.code_failures(failed_at) select clock_timestamp() from generate_series(1,101);
 result:=idea_codes_test.rpc('claim',repeat('f',64),jsonb_build_object('epoch',ep,'representativeName','테스트 대표','entryCode',code1));
 if result->>'code' is distinct from 'CODE_WAIT' or (result->>'retryAfter')::int>5 then raise exception 'global rate limit failed';end if;
 update idea_codes_test.code_failures set failed_at=clock_timestamp()-interval '16 minutes';
 perform idea_codes_test.rpc('release',a,'{"company":1}');
 result:=idea_codes_test.rpc('claim',repeat('f',64),jsonb_build_object('epoch',ep,'representativeName','테스트 대표','entryCode',code1));
 if result ? 'error' then raise exception 'global limit did not expire';end if;
 -- Reset rotates codes; settings preserve existing codes and generate new teams.
 select array_agg(entry_code) into previous_codes from idea_codes_test.teams;
 result:=idea_codes_test.rpc('reset',a,'{"confirm":"RESET","keep":true}');
 if exists(select 1 from idea_codes_test.teams where entry_code=any(previous_codes) or device_hash is not null) then raise exception 'reset did not rotate/revoke';end if;
 select entry_code into code1 from idea_codes_test.teams where id=1;
 result:=idea_codes_test.rpc('settings',a,'{"names":["회사1","회사2","회사3","회사4"],"budget":5000,"minutes":0}');
 if result ? 'error' or (select entry_code from idea_codes_test.teams where id=1)<>code1 or (select count(distinct entry_code) from idea_codes_test.teams)<>4 then raise exception 'new team code or existing code preservation failed';end if;
 select array_agg(entry_code) into previous_codes from idea_codes_test.teams;
 result:=idea_codes_test.rpc('reset',a,'{"confirm":"RESET","keep":false}');
 if jsonb_array_length(result->'teams')<>4 or exists(select 1 from idea_codes_test.teams where entry_code<>idea_codes_test.default_entry_code(id)) then raise exception 'default reset rotation failed';end if;
end $test$;
