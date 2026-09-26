-- Entirely synthetic identities, no ChallengeMe data or credentials.
INSERT INTO auth.users (id) SELECT pg_temp.id(n) FROM generate_series(1,8) n;
INSERT INTO public.user_profiles (id,display_name,preferred_language,status)
SELECT pg_temp.id(n), 'Test ' || n, 'FR', 'ACTIVE' FROM generate_series(1,8) n;
INSERT INTO public.academies (id,name,city,country,timezone,default_language,status) VALUES
(pg_temp.id(101),'Test A','Douala','CM','Africa/Douala','FR','ACTIVE'),
(pg_temp.id(102),'Test B','Douala','CM','Africa/Douala','FR','ACTIVE');
INSERT INTO public.academy_memberships (id,academy_id,user_id,status) VALUES
(pg_temp.id(201),pg_temp.id(101),pg_temp.id(1),'ACTIVE'),
(pg_temp.id(202),pg_temp.id(101),pg_temp.id(2),'ACTIVE'),
(pg_temp.id(203),pg_temp.id(101),pg_temp.id(3),'ACTIVE'),
(pg_temp.id(204),pg_temp.id(101),pg_temp.id(4),'ACTIVE'),
(pg_temp.id(205),pg_temp.id(102),pg_temp.id(1),'ACTIVE'),
(pg_temp.id(206),pg_temp.id(101),pg_temp.id(6),'ACTIVE'),
(pg_temp.id(207),pg_temp.id(101),pg_temp.id(7),'ACTIVE'),
(pg_temp.id(208),pg_temp.id(102),pg_temp.id(8),'ACTIVE');
INSERT INTO public.players (id,academy_id,first_name,last_name,birth_date,status) VALUES
(pg_temp.id(301),pg_temp.id(101),'Player','A','2010-01-01','ACTIVE'),
(pg_temp.id(302),pg_temp.id(101),'Player','A2','2010-01-01','ACTIVE'),
(pg_temp.id(303),pg_temp.id(102),'Player','B','2010-01-01','ACTIVE');
INSERT INTO public.coaches (id,academy_id,membership_id) VALUES
(pg_temp.id(401),pg_temp.id(101),pg_temp.id(201)),
(pg_temp.id(402),pg_temp.id(101),pg_temp.id(202)),
(pg_temp.id(403),pg_temp.id(102),pg_temp.id(205));
INSERT INTO public.stadiums (id,academy_id,name,address) VALUES
(pg_temp.id(501),pg_temp.id(101),'Stadium A','Address A'),
(pg_temp.id(502),pg_temp.id(102),'Stadium B','Address B'),
(pg_temp.id(503),pg_temp.id(101),'Stadium A2','Address A2');
INSERT INTO public.courts (id,academy_id,stadium_id,number) VALUES
(pg_temp.id(601),pg_temp.id(101),pg_temp.id(501),1),
(pg_temp.id(602),pg_temp.id(102),pg_temp.id(502),1),
(pg_temp.id(603),pg_temp.id(101),pg_temp.id(501),2);
CREATE FUNCTION pg_temp.offer(n integer, academy integer, key integer, version_no integer DEFAULT 1, amount numeric DEFAULT 100, curr text DEFAULT 'XAF') RETURNS void LANGUAGE sql AS $$
 INSERT INTO public.service_offers (id,academy_id,offer_key,version,name,activity,session_type,min_age,max_age,session_count,price,currency,price_basis,duration_minutes,status)
 VALUES(pg_temp.id(n),pg_temp.id(academy),pg_temp.id(key),version_no,'Test offer','TENNIS','GROUP',5,25,10,amount,curr,'PACKAGE',60,'PUBLISHED');
$$;
SELECT pg_temp.offer(701,101,710);
SELECT pg_temp.offer(702,101,720);
SELECT pg_temp.offer(703,102,710);
CREATE FUNCTION pg_temp.package(n integer, academy integer, player integer, offer integer) RETURNS void LANGUAGE sql AS $$
 INSERT INTO public.player_packages (id,academy_id,player_id,service_offer_id,purchased_sessions,remaining_sessions,total_price,currency,payment_state,status,terms_snapshot,origin)
 VALUES(pg_temp.id(n),pg_temp.id(academy),pg_temp.id(player),pg_temp.id(offer),10,10,100,'XAF','CONFIRMED','ACTIVE','{}','PURCHASE');
$$;
SELECT pg_temp.package(801,101,301,701);
SELECT pg_temp.package(802,101,302,701);
SELECT pg_temp.package(803,102,303,703);
CREATE FUNCTION pg_temp.session(n integer, academy integer, offer integer, coach integer, stadium integer, court integer, begins timestamptz, finishes timestamptz, state text DEFAULT 'OPEN') RETURNS void LANGUAGE sql AS $$
 INSERT INTO public.sessions (id,academy_id,service_offer_id,coach_id,stadium_id,court_id,starts_at,ends_at,capacity,status)
 VALUES(pg_temp.id(n),pg_temp.id(academy),pg_temp.id(offer),pg_temp.id(coach),pg_temp.id(stadium),pg_temp.id(court),begins,finishes,2,state);
$$;
SELECT pg_temp.session(901,101,701,401,501,601,'2030-01-01 10:00Z','2030-01-01 11:00Z');
SELECT pg_temp.session(902,101,701,401,501,601,'2030-01-01 11:00Z','2030-01-01 12:00Z');
SELECT pg_temp.session(903,102,703,403,502,602,'2030-01-01 10:00Z','2030-01-01 11:00Z');
CREATE FUNCTION pg_temp.booking(n integer, academy integer, session_no integer, player integer, package integer, state text DEFAULT 'PENDING') RETURNS void LANGUAGE sql AS $$
 INSERT INTO public.bookings (id,academy_id,session_id,player_id,package_id,service_offer_id,created_by,status,amount_snapshot,currency,contract_snapshot,completion_source)
 VALUES(pg_temp.id(n),pg_temp.id(academy),pg_temp.id(session_no),pg_temp.id(player),pg_temp.id(package),pg_temp.id(CASE WHEN academy=101 THEN 701 ELSE 703 END),pg_temp.id(1),state,100,'XAF','{}',CASE WHEN state='COMPLETED' THEN 'ADMIN' ELSE NULL END);
$$;
SELECT pg_temp.booking(1001,101,901,301,801);

