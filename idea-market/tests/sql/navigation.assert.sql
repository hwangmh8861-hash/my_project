set local role service_role;
do $test$
declare a text:=repeat('a',64);d text:=repeat('b',64);b text;v jsonb;ver int;
begin
 insert into idea_codes_test.room(pin_hash) values(extensions.crypt('1234',extensions.gen_salt('bf')));
 insert into idea_codes_test.admin_sessions values(a,now()+interval '1 hour');
 insert into idea_codes_test.teams(id,name) select i,'회사'||i from generate_series(1,8) i;
 select encode(extensions.digest(board_key,'sha256'),'hex') into b from idea_codes_test.room;
 v:=idea_codes_test.rpc('presentation',d,'{"page":1,"auto":false}');if v->>'code' is distinct from 'UNAUTHORIZED' then raise exception 'student controlled presentation';end if;
 v:=idea_codes_test.rpc('presentation',b,'{"page":1,"auto":false}');if v->>'code' is distinct from 'UNAUTHORIZED' then raise exception 'board token gained admin write';end if;
 v:=idea_codes_test.rpc('presentation',a,'{"page":30,"auto":false}');if not v ? 'error' then raise exception 'invalid page accepted';end if;
 v:=idea_codes_test.rpc('presentation',a,'{"page":1,"auto":false}');if v->'presentation'->>'page'<>'1' or v->'presentation'->>'auto'<>'false' then raise exception 'manual instructor page failed';end if;
 v:=idea_codes_test.rpc('board',b);if v->'presentation'->>'page'<>'1' or v ? 'entryCodes' then raise exception 'board missing control state or leaking codes';end if;
 ver:=(v->'presentation'->>'version')::int;
 perform idea_codes_test.rpc('start',a);v:=idea_codes_test.rpc('board',b);if v->'presentation'->>'page'<>'0' or v->'presentation'->>'auto'<>'true' or (v->'presentation'->>'version')::int<=ver then raise exception 'new stage did not reset navigation';end if;
 v:=idea_codes_test.rpc('student',d);if v ? 'presentation' or v ? 'investments' then raise exception 'student presentation/result leak';end if;
end $test$;
