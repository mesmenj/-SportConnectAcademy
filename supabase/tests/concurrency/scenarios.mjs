// Two-connection races required by the roadmap. A runs its command and waits at a
// gate while holding its locks; B must be observed blocked, then the gate opens.
// `b` is the substring B's output must contain; `check` must return true.
export function scenarios(v, id) {
  const A = `'${id(101)}'`
  const q = key => `'${v[key]}'`
  return [
    {
      name: 'last credit: two approvals, one free credit',
      a: [13, `approve_booking(${A},${q('ra')},1,gen_random_uuid())`],
      b: [13, `approve_booking(${A},${q('rb')},1,gen_random_uuid())`],
      expect: 'CREDIT_UNAVAILABLE',
      check: `SELECT (SELECT array_agg(status ORDER BY id) FROM public.bookings WHERE id IN (${q('ra')},${q('rb')})) @> ARRAY['CONFIRMED','PENDING']
        AND private.package_hold(${A},${q('k1')}) = 1
        AND (SELECT remaining_sessions FROM public.player_packages WHERE id = ${q('k1')}) = 1
        AND NOT EXISTS (SELECT FROM private.course_ledger WHERE booking_id IN (${q('ra')},${q('rb')}))`,
    },
    {
      name: 'last place: two players, capacity 1',
      a: [13, `approve_booking(${A},${q('pc1')},1,gen_random_uuid())`],
      b: [13, `approve_booking(${A},${q('pc2')},1,gen_random_uuid())`],
      expect: 'SESSION_FULL',
      check: `SELECT (SELECT occupied_places FROM public.sessions WHERE id = ${q('sc')}) = 1
        AND (SELECT count(*) FROM public.bookings WHERE session_id = ${q('sc')} AND status = 'CONFIRMED') = 1`,
    },
    {
      name: 'double approval of the same booking',
      a: [13, `approve_booking(${A},${q('pd')},1,gen_random_uuid())`],
      b: [12, `approve_booking(${A},${q('pd')},1,gen_random_uuid())`],
      expect: 'STALE_REVISION',
      check: `SELECT (SELECT status = 'CONFIRMED' AND revision = 2 FROM public.bookings WHERE id = ${q('pd')})
        AND (SELECT occupied_places FROM public.sessions WHERE id = ${q('sd')}) = 1
        AND (SELECT count(*) FROM private.booking_events WHERE booking_id = ${q('pd')} AND event_type = 'APPROVED') = 1`,
    },
    {
      name: 'cancel versus attendance',
      a: [13, `cancel_booking(${A},${q('ce')},1,'Injury',gen_random_uuid())`],
      b: [2, `record_attendance(${A},${q('ce')},true,1,gen_random_uuid())`],
      expect: 'STALE_REVISION',
      check: `SELECT (SELECT status FROM public.bookings WHERE id = ${q('ce')}) = 'CANCELLED'
        AND NOT EXISTS (SELECT FROM private.course_ledger WHERE booking_id = ${q('ce')})
        AND NOT EXISTS (SELECT FROM public.booking_attendance WHERE booking_id = ${q('ce')})
        AND (SELECT occupied_places FROM public.sessions WHERE id = ${q('se')}) = 0`,
    },
    {
      name: 'retry with the same operation key',
      a: [12, `request_booking(${A},${q('sf')},'${id(302)}','${id(802)}','${id(95001)}')`],
      b: [12, `request_booking(${A},${q('sf')},'${id(302)}','${id(802)}','${id(95001)}')`],
      expect: '"outcome": "REQUESTED"',
      check: `SELECT (SELECT count(*) FROM public.bookings WHERE session_id = ${q('sf')}) = 1
        AND (SELECT count(*) FROM private.command_receipts WHERE operation_key = '${id(95001)}') = 1`,
    },
    {
      name: 'double compensation of one debit',
      a: [2, `record_attendance(${A},${q('cg')},false,2,gen_random_uuid(),'Left early')`],
      b: [2, `record_attendance(${A},${q('cg')},false,2,gen_random_uuid(),'Left early')`],
      expect: 'NO_CHANGE',
      check: `SELECT (SELECT count(*) FROM private.course_ledger WHERE booking_id = ${q('cg')} AND reason = 'ATTENDANCE_CORRECTION') = 1
        AND private.booking_net_consumed(${A},'${id(802)}',${q('cg')}) = 0`,
    },
    {
      name: 'same court, overlapping sessions',
      a: [12, `create_session(${A},'${id(701)}','${id(401)}','2031-04-01 10:00Z','2031-04-01 11:00Z',2,gen_random_uuid(),NULL,'${id(601)}')`],
      b: [12, `create_session(${A},'${id(701)}','${id(402)}','2031-04-01 10:30Z','2031-04-01 11:30Z',2,gen_random_uuid(),NULL,'${id(601)}')`],
      expect: 'COURT_CONFLICT',
      check: `SELECT count(*) = 1 FROM public.sessions WHERE court_id = '${id(601)}' AND starts_at >= '2031-04-01' AND starts_at < '2031-04-02'`,
    },
    {
      name: 'same coach, overlapping sessions',
      a: [12, `create_session(${A},'${id(701)}','${id(401)}','2031-04-02 10:00Z','2031-04-02 11:00Z',2,gen_random_uuid())`],
      b: [12, `create_session(${A},'${id(701)}','${id(401)}','2031-04-02 10:30Z','2031-04-02 11:30Z',2,gen_random_uuid())`],
      expect: 'COACH_CONFLICT',
      check: `SELECT count(*) = 1 FROM public.sessions WHERE coach_id = '${id(401)}' AND starts_at >= '2031-04-02' AND starts_at < '2031-04-03'`,
    },
    {
      name: '3D duplicate invitation acceptance',
      a: [60, `accept_invitation(${q('invite60')},repeat('e',64),'Parent','FR','${id(96002)}')`],
      b: [60, `accept_invitation(${q('invite60')},repeat('e',64),'Parent','FR','${id(96002)}')`],
      expect: 'ACCEPTED',
      check: `SELECT (SELECT count(*) FROM public.academy_memberships WHERE user_id='${id(60)}')=1
        AND (SELECT count(*) FROM private.audit_log WHERE action='invitation.accepted' AND resource_id=${q('invite60')})=1`,
    },
    {
      name: '3D invitation revocation versus acceptance',
      a: [10, `revoke_invitation(${A},${q('invite61')},'Cancelled invitation',gen_random_uuid())`],
      b: [61, `accept_invitation(${q('invite61')},repeat('f',64),'Parent','FR','${id(96003)}')`],
      expect: 'INVITATION_UNAVAILABLE',
      check: `SELECT NOT EXISTS(SELECT FROM public.academy_memberships WHERE user_id='${id(61)}')
        AND (SELECT status='REVOKED' FROM private.academy_invitations WHERE id=${q('invite61')})`,
    },
    {
      name: '3D invitation resend versus acceptance of the old link',
      a: [10, `resend_invitation(${A},${q('invite62')},clock_timestamp()+interval '1 day','Expired email link',gen_random_uuid())`],
      b: [62, `accept_invitation(${q('invite62')},repeat('g',64),'Parent','FR','${id(96004)}')`],
      expect: 'INVITATION_UNAVAILABLE',
      check: `SELECT NOT EXISTS(SELECT FROM public.academy_memberships WHERE user_id='${id(62)}')
        AND (SELECT status='REQUESTED' AND token_digest IS NULL FROM private.academy_invitations WHERE id=${q('invite62')})
        AND (SELECT count(*)=1 FROM private.notification_events WHERE invitation_id=${q('invite62')} AND event_type='INVITATION_RESENT')`,
    },
    {
      name: '3D webhook versus late sender result',
      a: [10, `svc_apply_email_webhook('${id(1801)}','race-message','delivered',clock_timestamp())`, 'service_role'],
      b: [10, `svc_record_delivery('${id(1801)}','${id(96001)}','ACCEPTED','race-message')`, 'service_role'],
      expect: 'DELIVERED',
      check: `SELECT status='DELIVERED' FROM private.notification_deliveries WHERE id='${id(1801)}'`,
    },
  ]
}
