import test from 'node:test';
import {makeDatabase,runAssertions} from './sql-harness.js';
test('two spare instructor logins preserve primary access, active sessions and private class data',async()=>{
 const db=await makeDatabase();
 try{await runAssertions(db,'spare-instructor.assert.sql');await runAssertions(db,'spare-instructor.assert.sql',true)}finally{await db.close()}
});
