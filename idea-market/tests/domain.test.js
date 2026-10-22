import {test} from 'node:test';import assert from 'node:assert/strict';import {money,validate,csv} from '../src/domain.js';
test('Korean money units',()=>{assert.equal(money(0),'0원');assert.equal(money(3500),'3,500만 원');assert.equal(money(15000),'1억 5,000만 원');assert.equal(money(35000),'3억 5,000만 원');assert.equal(money(10000),'1억 원')});
test('investment constraints',()=>{const t=[{id:1},{id:2},{id:3}],good={2:{amount:5000,reason:'실제로 활용할 수 있는 아이디어입니다.'}};assert.equal(validate(good,5000,1,t),'');assert(validate(good,6000,1,t));assert(validate(good,5000,2,t));assert(validate({2:{amount:5000,reason:'짧음'}},5000,1,t));assert(validate({2:{amount:4950,reason:'실제로 활용할 수 있는 아이디어입니다.'}},4950,1,t))});
test('Excel CSV prevents formulas and escapes quotes',()=>{assert(csv([['=1+1','a"b','가나다']]).startsWith('\ufeff'));assert(csv([['=1+1']]).includes("'=1+1"));assert(csv([['a"b']]).includes('a""b'))});

import {pollDelay,isInAppBrowser} from '../src/domain.js';
test('P0 polling interval and in-app detection',()=>{assert.equal(pollDelay('open'),3000);assert.equal(pollDelay('closed'),10000);assert.equal(pollDelay('ready'),10000);assert(isInAppBrowser('Mozilla KAKAOTALK'));assert(isInAppBrowser('Mozilla NAVER(inapp)'));assert(!isInAppBrowser('Mozilla iPhone Version/15.0 Mobile Safari/604.1'));assert(!isInAppBrowser('Mozilla Android Chrome/100.0'));});
