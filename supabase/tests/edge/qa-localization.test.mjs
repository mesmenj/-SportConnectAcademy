import {test} from 'node:test';
import assert from 'node:assert/strict';
import {renderEmail} from '../../functions/_shared/handlers.mjs';
for(const [language,subject] of [['FR','Réservation confirmée'],['EN','Booking approved']]) {
 test(`notification ${language} uses academy timezone across date boundary`,()=>{
  const result=renderEmail({language,template:'BOOKING_APPROVED',body:{academy:'QA Academy',timezone:'Africa/Douala',starts_at:'2030-01-01T23:30:00Z'}});
  assert.equal(result.subject,subject);assert.match(result.textContent,/00:30/);assert.match(result.textContent,/Africa\/Douala/);
  assert.match(result.textContent,language==='FR'?/2 janvier 2030/:/2 January 2030/);
 });
}
test('email respects summer and winter offsets of academy timezone',()=>{
 const message=starts_at=>renderEmail({language:'EN',template:'BOOKING_REMINDER',body:{academy:'QA Academy',timezone:'Europe/Paris',starts_at}}).textContent;
 assert.match(message('2030-01-01T10:00:00Z'),/11:00/);assert.match(message('2030-07-01T10:00:00Z'),/12:00/);
});
