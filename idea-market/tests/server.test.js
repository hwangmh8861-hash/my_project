import test,{before,after} from 'node:test';
import {makeDatabase,runAssertions} from './sql-harness.js';
let db;before(async()=>{db=await makeDatabase()});after(async()=>{await db?.close()});
test('P0-1 and P0-2: school IP isolation, bounded delays, no shared lockout, instructor recovery',async()=>{await runAssertions(db,'access-delays.assert.sql')});
test('P0-3 and P0-4: restore only own cancelled submission, resubmit, retain six teams on reset',async()=>{await runAssertions(db,'submission-recovery.assert.sql')});
test('P1 controls: board heartbeat expiry, +1 minute, explicit result reveal',async()=>{await runAssertions(db,'presentation.assert.sql')});
test('upgrade migration chain preserves working server behaviours in isolated rollback schema',async()=>{await runAssertions(db,'access-delays.assert.sql',true);await runAssertions(db,'submission-recovery.assert.sql',true);await runAssertions(db,'presentation.assert.sql',true)});

test('existing server constraints, code secrecy, exclusive ownership and duplicate submission regression',async()=>{await runAssertions(db,'company-codes.assert.sql')});
test('short and long reasons pass without truncation; blank reasons fail; upgrade and fresh schema',async()=>{await runAssertions(db,'unrestricted-reasons.assert.sql');await runAssertions(db,'unrestricted-reasons.assert.sql',true)});
test('instructor can change 7 to 6 and 6 to 8; active class data requires explicit confirmation',async()=>{await runAssertions(db,'team-count.assert.sql');await runAssertions(db,'team-count.assert.sql',true)});
test('reset restores default company codes; explicit restoration preserves investments and rejects students',async()=>{await runAssertions(db,'default-codes.assert.sql');await runAssertions(db,'default-codes.assert.sql',true)});

test('one representative device per company, same-device resume, private names, instructor release and reset',async()=>{await runAssertions(db,'representative-lock.assert.sql');await runAssertions(db,'representative-lock.assert.sql',true)});
test('instructor projector navigation is validated, synchronized and never grants board/student admin access',async()=>{await runAssertions(db,'navigation.assert.sql');await runAssertions(db,'navigation.assert.sql',true)});
