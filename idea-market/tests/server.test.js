import test,{before,after} from 'node:test';
import {makeDatabase,runAssertions} from './sql-harness.js';
let db;before(async()=>{db=await makeDatabase()});after(async()=>{await db?.close()});
test('P0-1 and P0-2: school IP isolation, bounded delays, no shared lockout, instructor recovery',async()=>{await runAssertions(db,'access-delays.assert.sql')});
