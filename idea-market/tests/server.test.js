import test,{before,after} from 'node:test';
import {makeDatabase,runAssertions} from './sql-harness.js';
let db;before(async()=>{db=await makeDatabase()});after(async()=>{await db?.close()});
test('P0-1 and P0-2: school IP isolation, bounded delays, no shared lockout, instructor recovery',async()=>{await runAssertions(db,'access-delays.assert.sql')});
test('P0-3 and P0-4: restore only own cancelled submission, resubmit, retain six teams on reset',async()=>{await runAssertions(db,'submission-recovery.assert.sql')});
