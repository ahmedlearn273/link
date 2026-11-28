-- P6: PRIME personality. Greetings in every form, small talk, playful Egyptian tone, aware of Cairo time of day, Fridays and occasions (Ramadan, Eids, national days).
-- Requires P1b (patches the P1b version of prime_answer). Read-only: no orders, money or permissions are touched.
-- New: table private.prime_occasions (dates 2026-2030, editable; Hijri dates are estimates until the official sighting), helper private.prime_pick,
-- private.prime_personality, ~362 small-talk phrases (kind intent), and CREATE OR REPLACE public.prime_answer (same signature, same grants).
BEGIN;

CREATE TABLE IF NOT EXISTS private.prime_occasions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text NOT NULL,
  name_ar text NOT NULL,
  starts_on date NOT NULL,
  ends_on date NOT NULL,
  greeting text NOT NULL,
  is_estimate boolean NOT NULL DEFAULT false,
  UNIQUE (code, starts_on),
  CHECK (ends_on >= starts_on)
);
ALTER TABLE private.prime_occasions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON private.prime_occasions FROM PUBLIC, anon, authenticated;

INSERT INTO private.prime_occasions (code, name_ar, starts_on, ends_on, greeting, is_estimate) VALUES
  ('new_year','رأس السنة الميلادية','2026-01-01','2026-01-01','وكل سنة وانت طيب ومعاك كل خير في السنة الجديدة!',false),
  ('coptic_christmas','عيد الميلاد المجيد','2026-01-07','2026-01-07','وكل سنة وانت طيب بمناسبة عيد الميلاد المجيد، أعياد سعيدة على كل إخواتنا المسيحيين!',false),
  ('isra_miraj','الإسراء والمعراج','2026-01-16','2026-01-16','كل سنة وانت طيب بمناسبة ذكرى الإسراء والمعراج!',true),
  ('jan25','عيد الشرطة','2026-01-25','2026-01-25','وكل سنة ومصر طيبة بمناسبة عيد الشرطة!',false),
  ('ramadan','رمضان','2026-02-18','2026-03-19','رمضان كريم! الله أكرم، كل سنة وانت طيب وصيام مقبول إن شاء الله.',true),
  ('eid_fitr','عيد الفطر','2026-03-20','2026-03-22','عيد مبارك! كل سنة وانت طيب وعيدك سعيد، وعيدية حلوة إن شاء الله.',true),
  ('mothers_day','عيد الأم','2026-03-21','2026-03-21','وكل سنة وكل الأمهات طيبين، عيد أم سعيد! ما تنساش تفرح ماما النهاردة.',false),
  ('sham_el_nessim','شم النسيم','2026-04-13','2026-04-13','وكل سنة وانت طيب، شم النسيم حلو بالفسيخ والرنجة والبصل الأخضر!',false),
  ('sinai','عيد تحرير سيناء','2026-04-25','2026-04-25','وكل سنة ومصر طيبة بمناسبة ذكرى تحرير سيناء!',false),
  ('labour','عيد العمال','2026-05-01','2026-05-01','وكل سنة وكل شغيل ومجتهد طيب، عيد عمال سعيد!',false),
  ('eid_adha','عيد الأضحى','2026-05-27','2026-05-30','عيد أضحى مبارك! كل سنة وانت طيب وتعيد على خير وصحة وسلامة.',true),
  ('hijri_new_year','رأس السنة الهجرية','2026-06-17','2026-06-17','وكل سنة وانت طيب بمناسبة رأس السنة الهجرية، عام هجري سعيد!',true),
  ('jun30','ذكرى 30 يونيو','2026-06-30','2026-06-30','وكل سنة ومصر طيبة بمناسبة ذكرى 30 يونيو!',false),
  ('jul23','ذكرى ثورة 23 يوليو','2026-07-23','2026-07-23','وكل سنة ومصر طيبة بمناسبة ذكرى ثورة 23 يوليو!',false),
  ('mawlid','المولد النبوي','2026-08-26','2026-08-26','كل سنة وانت طيب بمناسبة المولد النبوي الشريف، وحلاوة المولد عليك!',true),
  ('oct6','ذكرى نصر أكتوبر','2026-10-06','2026-10-06','وكل سنة وانت طيب بمناسبة ذكرى نصر أكتوبر المجيد!',false),
  ('new_year','رأس السنة الميلادية','2027-01-01','2027-01-01','وكل سنة وانت طيب ومعاك كل خير في السنة الجديدة!',false),
  ('isra_miraj','الإسراء والمعراج','2027-01-06','2027-01-06','كل سنة وانت طيب بمناسبة ذكرى الإسراء والمعراج!',true),
  ('coptic_christmas','عيد الميلاد المجيد','2027-01-07','2027-01-07','وكل سنة وانت طيب بمناسبة عيد الميلاد المجيد، أعياد سعيدة على كل إخواتنا المسيحيين!',false),
  ('jan25','عيد الشرطة','2027-01-25','2027-01-25','وكل سنة ومصر طيبة بمناسبة عيد الشرطة!',false),
  ('ramadan','رمضان','2027-02-08','2027-03-09','رمضان كريم! الله أكرم، كل سنة وانت طيب وصيام مقبول إن شاء الله.',true),
  ('eid_fitr','عيد الفطر','2027-03-10','2027-03-12','عيد مبارك! كل سنة وانت طيب وعيدك سعيد، وعيدية حلوة إن شاء الله.',true),
  ('mothers_day','عيد الأم','2027-03-21','2027-03-21','وكل سنة وكل الأمهات طيبين، عيد أم سعيد! ما تنساش تفرح ماما النهاردة.',false),
  ('sinai','عيد تحرير سيناء','2027-04-25','2027-04-25','وكل سنة ومصر طيبة بمناسبة ذكرى تحرير سيناء!',false),
  ('labour','عيد العمال','2027-05-01','2027-05-01','وكل سنة وكل شغيل ومجتهد طيب، عيد عمال سعيد!',false),
  ('sham_el_nessim','شم النسيم','2027-05-03','2027-05-03','وكل سنة وانت طيب، شم النسيم حلو بالفسيخ والرنجة والبصل الأخضر!',false),
  ('eid_adha','عيد الأضحى','2027-05-17','2027-05-20','عيد أضحى مبارك! كل سنة وانت طيب وتعيد على خير وصحة وسلامة.',true),
  ('hijri_new_year','رأس السنة الهجرية','2027-06-06','2027-06-06','وكل سنة وانت طيب بمناسبة رأس السنة الهجرية، عام هجري سعيد!',true),
  ('jun30','ذكرى 30 يونيو','2027-06-30','2027-06-30','وكل سنة ومصر طيبة بمناسبة ذكرى 30 يونيو!',false),
  ('jul23','ذكرى ثورة 23 يوليو','2027-07-23','2027-07-23','وكل سنة ومصر طيبة بمناسبة ذكرى ثورة 23 يوليو!',false),
  ('mawlid','المولد النبوي','2027-08-15','2027-08-15','كل سنة وانت طيب بمناسبة المولد النبوي الشريف، وحلاوة المولد عليك!',true),
  ('oct6','ذكرى نصر أكتوبر','2027-10-06','2027-10-06','وكل سنة وانت طيب بمناسبة ذكرى نصر أكتوبر المجيد!',false),
  ('isra_miraj','الإسراء والمعراج','2027-12-26','2027-12-26','كل سنة وانت طيب بمناسبة ذكرى الإسراء والمعراج!',true),
  ('new_year','رأس السنة الميلادية','2028-01-01','2028-01-01','وكل سنة وانت طيب ومعاك كل خير في السنة الجديدة!',false),
  ('coptic_christmas','عيد الميلاد المجيد','2028-01-07','2028-01-07','وكل سنة وانت طيب بمناسبة عيد الميلاد المجيد، أعياد سعيدة على كل إخواتنا المسيحيين!',false),
  ('jan25','عيد الشرطة','2028-01-25','2028-01-25','وكل سنة ومصر طيبة بمناسبة عيد الشرطة!',false),
  ('ramadan','رمضان','2028-01-28','2028-02-26','رمضان كريم! الله أكرم، كل سنة وانت طيب وصيام مقبول إن شاء الله.',true),
  ('eid_fitr','عيد الفطر','2028-02-27','2028-02-29','عيد مبارك! كل سنة وانت طيب وعيدك سعيد، وعيدية حلوة إن شاء الله.',true),
  ('mothers_day','عيد الأم','2028-03-21','2028-03-21','وكل سنة وكل الأمهات طيبين، عيد أم سعيد! ما تنساش تفرح ماما النهاردة.',false),
  ('sham_el_nessim','شم النسيم','2028-04-17','2028-04-17','وكل سنة وانت طيب، شم النسيم حلو بالفسيخ والرنجة والبصل الأخضر!',false),
  ('sinai','عيد تحرير سيناء','2028-04-25','2028-04-25','وكل سنة ومصر طيبة بمناسبة ذكرى تحرير سيناء!',false),
  ('labour','عيد العمال','2028-05-01','2028-05-01','وكل سنة وكل شغيل ومجتهد طيب، عيد عمال سعيد!',false),
  ('eid_adha','عيد الأضحى','2028-05-05','2028-05-08','عيد أضحى مبارك! كل سنة وانت طيب وتعيد على خير وصحة وسلامة.',true),
  ('hijri_new_year','رأس السنة الهجرية','2028-05-25','2028-05-25','وكل سنة وانت طيب بمناسبة رأس السنة الهجرية، عام هجري سعيد!',true),
  ('jun30','ذكرى 30 يونيو','2028-06-30','2028-06-30','وكل سنة ومصر طيبة بمناسبة ذكرى 30 يونيو!',false),
  ('jul23','ذكرى ثورة 23 يوليو','2028-07-23','2028-07-23','وكل سنة ومصر طيبة بمناسبة ذكرى ثورة 23 يوليو!',false),
  ('mawlid','المولد النبوي','2028-08-03','2028-08-03','كل سنة وانت طيب بمناسبة المولد النبوي الشريف، وحلاوة المولد عليك!',true),
  ('oct6','ذكرى نصر أكتوبر','2028-10-06','2028-10-06','وكل سنة وانت طيب بمناسبة ذكرى نصر أكتوبر المجيد!',false),
  ('isra_miraj','الإسراء والمعراج','2028-12-14','2028-12-14','كل سنة وانت طيب بمناسبة ذكرى الإسراء والمعراج!',true),
  ('new_year','رأس السنة الميلادية','2029-01-01','2029-01-01','وكل سنة وانت طيب ومعاك كل خير في السنة الجديدة!',false),
  ('coptic_christmas','عيد الميلاد المجيد','2029-01-07','2029-01-07','وكل سنة وانت طيب بمناسبة عيد الميلاد المجيد، أعياد سعيدة على كل إخواتنا المسيحيين!',false),
  ('ramadan','رمضان','2029-01-16','2029-02-14','رمضان كريم! الله أكرم، كل سنة وانت طيب وصيام مقبول إن شاء الله.',true),
  ('jan25','عيد الشرطة','2029-01-25','2029-01-25','وكل سنة ومصر طيبة بمناسبة عيد الشرطة!',false),
  ('eid_fitr','عيد الفطر','2029-02-15','2029-02-17','عيد مبارك! كل سنة وانت طيب وعيدك سعيد، وعيدية حلوة إن شاء الله.',true),
  ('mothers_day','عيد الأم','2029-03-21','2029-03-21','وكل سنة وكل الأمهات طيبين، عيد أم سعيد! ما تنساش تفرح ماما النهاردة.',false),
  ('sham_el_nessim','شم النسيم','2029-04-09','2029-04-09','وكل سنة وانت طيب، شم النسيم حلو بالفسيخ والرنجة والبصل الأخضر!',false),
  ('eid_adha','عيد الأضحى','2029-04-24','2029-04-27','عيد أضحى مبارك! كل سنة وانت طيب وتعيد على خير وصحة وسلامة.',true),
  ('sinai','عيد تحرير سيناء','2029-04-25','2029-04-25','وكل سنة ومصر طيبة بمناسبة ذكرى تحرير سيناء!',false),
  ('labour','عيد العمال','2029-05-01','2029-05-01','وكل سنة وكل شغيل ومجتهد طيب، عيد عمال سعيد!',false),
  ('hijri_new_year','رأس السنة الهجرية','2029-05-15','2029-05-15','وكل سنة وانت طيب بمناسبة رأس السنة الهجرية، عام هجري سعيد!',true),
  ('jun30','ذكرى 30 يونيو','2029-06-30','2029-06-30','وكل سنة ومصر طيبة بمناسبة ذكرى 30 يونيو!',false),
  ('jul23','ذكرى ثورة 23 يوليو','2029-07-23','2029-07-23','وكل سنة ومصر طيبة بمناسبة ذكرى ثورة 23 يوليو!',false),
  ('mawlid','المولد النبوي','2029-07-24','2029-07-24','كل سنة وانت طيب بمناسبة المولد النبوي الشريف، وحلاوة المولد عليك!',true),
  ('oct6','ذكرى نصر أكتوبر','2029-10-06','2029-10-06','وكل سنة وانت طيب بمناسبة ذكرى نصر أكتوبر المجيد!',false),
  ('isra_miraj','الإسراء والمعراج','2029-12-04','2029-12-04','كل سنة وانت طيب بمناسبة ذكرى الإسراء والمعراج!',true),
  ('new_year','رأس السنة الميلادية','2030-01-01','2030-01-01','وكل سنة وانت طيب ومعاك كل خير في السنة الجديدة!',false),
  ('ramadan','رمضان','2030-01-06','2030-02-04','رمضان كريم! الله أكرم، كل سنة وانت طيب وصيام مقبول إن شاء الله.',true),
  ('coptic_christmas','عيد الميلاد المجيد','2030-01-07','2030-01-07','وكل سنة وانت طيب بمناسبة عيد الميلاد المجيد، أعياد سعيدة على كل إخواتنا المسيحيين!',false),
  ('jan25','عيد الشرطة','2030-01-25','2030-01-25','وكل سنة ومصر طيبة بمناسبة عيد الشرطة!',false),
  ('eid_fitr','عيد الفطر','2030-02-05','2030-02-07','عيد مبارك! كل سنة وانت طيب وعيدك سعيد، وعيدية حلوة إن شاء الله.',true),
  ('mothers_day','عيد الأم','2030-03-21','2030-03-21','وكل سنة وكل الأمهات طيبين، عيد أم سعيد! ما تنساش تفرح ماما النهاردة.',false),
  ('eid_adha','عيد الأضحى','2030-04-14','2030-04-17','عيد أضحى مبارك! كل سنة وانت طيب وتعيد على خير وصحة وسلامة.',true),
  ('sinai','عيد تحرير سيناء','2030-04-25','2030-04-25','وكل سنة ومصر طيبة بمناسبة ذكرى تحرير سيناء!',false),
  ('sham_el_nessim','شم النسيم','2030-04-29','2030-04-29','وكل سنة وانت طيب، شم النسيم حلو بالفسيخ والرنجة والبصل الأخضر!',false),
  ('labour','عيد العمال','2030-05-01','2030-05-01','وكل سنة وكل شغيل ومجتهد طيب، عيد عمال سعيد!',false),
  ('hijri_new_year','رأس السنة الهجرية','2030-05-04','2030-05-04','وكل سنة وانت طيب بمناسبة رأس السنة الهجرية، عام هجري سعيد!',true),
  ('jun30','ذكرى 30 يونيو','2030-06-30','2030-06-30','وكل سنة ومصر طيبة بمناسبة ذكرى 30 يونيو!',false),
  ('mawlid','المولد النبوي','2030-07-13','2030-07-13','كل سنة وانت طيب بمناسبة المولد النبوي الشريف، وحلاوة المولد عليك!',true),
  ('jul23','ذكرى ثورة 23 يوليو','2030-07-23','2030-07-23','وكل سنة ومصر طيبة بمناسبة ذكرى ثورة 23 يوليو!',false),
  ('oct6','ذكرى نصر أكتوبر','2030-10-06','2030-10-06','وكل سنة وانت طيب بمناسبة ذكرى نصر أكتوبر المجيد!',false),
  ('isra_miraj','الإسراء والمعراج','2030-11-23','2030-11-23','كل سنة وانت طيب بمناسبة ذكرى الإسراء والمعراج!',true),
  ('ramadan','رمضان','2030-12-26','2031-01-24','رمضان كريم! الله أكرم، كل سنة وانت طيب وصيام مقبول إن شاء الله.',true)
ON CONFLICT (code, starts_on) DO NOTHING;

INSERT INTO private.prime_synonyms (phrase, phrase_norm, canonical, kind)
SELECT v.p, private.prime_stem(v.p), v.c, v.k
FROM (VALUES
  ('انت مين','who_are_you','intent'),
  ('انت مين يا برايم','who_are_you','intent'),
  ('مين انت','who_are_you','intent'),
  ('اسمك ايه','who_are_you','intent'),
  ('انت اسمك ايه','who_are_you','intent'),
  ('اسمك','who_are_you','intent'),
  ('عرفني بنفسك','who_are_you','intent'),
  ('انت ايه','who_are_you','intent'),
  ('inta meen','who_are_you','intent'),
  ('enta meen','who_are_you','intent'),
  ('meen enta','who_are_you','intent'),
  ('esmak eh','who_are_you','intent'),
  ('esmak e','who_are_you','intent'),
  ('who are you','who_are_you','intent'),
  ('what is your name','who_are_you','intent'),
  ('whats your name','who_are_you','intent'),
  ('your name','who_are_you','intent'),
  ('introduce yourself','who_are_you','intent'),
  ('انت روبوت','robot_q','intent'),
  ('انت بني ادم','robot_q','intent'),
  ('انت بنى ادم','robot_q','intent'),
  ('انت انسان','robot_q','intent'),
  ('انت حقيقي','robot_q','intent'),
  ('انت بتفهم','robot_q','intent'),
  ('انت ذكي','robot_q','intent'),
  ('inta robot','robot_q','intent'),
  ('enta robot','robot_q','intent'),
  ('inta ensan','robot_q','intent'),
  ('are you a robot','robot_q','intent'),
  ('are you human','robot_q','intent'),
  ('are you real','robot_q','intent'),
  ('are you ai','robot_q','intent'),
  ('are you a bot','robot_q','intent'),
  ('you a bot','robot_q','intent'),
  ('مين عملك','creator','intent'),
  ('مين صنعك','creator','intent'),
  ('مين صاحبك','creator','intent'),
  ('مين صاحب وصلة','creator','intent'),
  ('مين اللي عملك','creator','intent'),
  ('meen 3amalak','creator','intent'),
  ('meen sana3ak','creator','intent'),
  ('who made you','creator','intent'),
  ('who created you','creator','intent'),
  ('who built you','creator','intent'),
  ('who owns wasla','creator','intent'),
  ('نكتة','joke','intent'),
  ('نكته','joke','intent'),
  ('قولي نكتة','joke','intent'),
  ('قولي نكته','joke','intent'),
  ('احكيلي نكتة','joke','intent'),
  ('احكيلي نكته','joke','intent'),
  ('هزرني','joke','intent'),
  ('فرفشني','joke','intent'),
  ('ضحكني','joke','intent'),
  ('عايز اضحك','joke','intent'),
  ('عاوز اضحك','joke','intent'),
  ('قول نكتة','joke','intent'),
  ('nokta','joke','intent'),
  ('noktah','joke','intent'),
  ('olly nokta','joke','intent'),
  ('olli nokta','joke','intent'),
  ('7kili nokta','joke','intent'),
  ('ehkeli nokta','joke','intent'),
  ('ed7akny','joke','intent'),
  ('joke','joke','intent'),
  ('a joke','joke','intent'),
  ('tell me a joke','joke','intent'),
  ('make me laugh','joke','intent'),
  ('say something funny','joke','intent'),
  ('funny','joke','intent'),
  ('انت جامد','compliment','intent'),
  ('انت جامد اوي','compliment','intent'),
  ('انت حلو','compliment','intent'),
  ('انت جميل','compliment','intent'),
  ('انت ظريف','compliment','intent'),
  ('انت شاطر','compliment','intent'),
  ('انت تحفة','compliment','intent'),
  ('انت تحفه','compliment','intent'),
  ('انت عظمة','compliment','intent'),
  ('انت عظمه','compliment','intent'),
  ('برافو عليك','compliment','intent'),
  ('برافو','compliment','intent'),
  ('احسنت','compliment','intent'),
  ('ممتاز','compliment','intent'),
  ('تحفة','compliment','intent'),
  ('تحفه','compliment','intent'),
  ('عظمة','compliment','intent'),
  ('عظمه','compliment','intent'),
  ('جامد','compliment','intent'),
  ('جامد جدا','compliment','intent'),
  ('شاطر','compliment','intent'),
  ('ابن حلال','compliment','intent'),
  ('bravo','compliment','intent'),
  ('inta gamed','compliment','intent'),
  ('enta gamed','compliment','intent'),
  ('inta 7elw','compliment','intent'),
  ('enta helw','compliment','intent'),
  ('inta shater','compliment','intent'),
  ('enta shater','compliment','intent'),
  ('inta ta7fa','compliment','intent'),
  ('you are great','compliment','intent'),
  ('you are awesome','compliment','intent'),
  ('you are amazing','compliment','intent'),
  ('you are good','compliment','intent'),
  ('well done','compliment','intent'),
  ('good job','compliment','intent'),
  ('great job','compliment','intent'),
  ('awesome','compliment','intent'),
  ('amazing','compliment','intent'),
  ('nice one','compliment','intent'),
  ('غبي','mild_insult','intent'),
  ('انت غبي','mild_insult','intent'),
  ('انت وحش','mild_insult','intent'),
  ('انت مش بتفهم','mild_insult','intent'),
  ('انت بتهبل','mild_insult','intent'),
  ('انت مش فاهم','mild_insult','intent'),
  ('مش بتفهم','mild_insult','intent'),
  ('مبتفهمش','mild_insult','intent'),
  ('مش فاهمني','mild_insult','intent'),
  ('انت فاشل','mild_insult','intent'),
  ('بايظ','mild_insult','intent'),
  ('inta ghaby','mild_insult','intent'),
  ('enta ghaby','mild_insult','intent'),
  ('inta mesh bet fahem','mild_insult','intent'),
  ('mesh betfham','mild_insult','intent'),
  ('stupid','mild_insult','intent'),
  ('dumb','mild_insult','intent'),
  ('you are stupid','mild_insult','intent'),
  ('you are dumb','mild_insult','intent'),
  ('you are useless','mild_insult','intent'),
  ('useless','mild_insult','intent'),
  ('you dont understand','mild_insult','intent'),
  ('you do not understand','mild_insult','intent'),
  ('اسف','sorry','intent'),
  ('آسف','sorry','intent'),
  ('متأسف','sorry','intent'),
  ('متاسف','sorry','intent'),
  ('معلش','sorry','intent'),
  ('اسفة','sorry','intent'),
  ('آسفة','sorry','intent'),
  ('متأسفة','sorry','intent'),
  ('sorry','sorry','intent'),
  ('so sorry','sorry','intent'),
  ('my bad','sorry','intent'),
  ('asef','sorry','intent'),
  ('asf','sorry','intent'),
  ('mo3lesh','sorry','intent'),
  ('ma3lesh','sorry','intent'),
  ('ma3leesh','sorry','intent'),
  ('apologies','sorry','intent'),
  ('apologize','sorry','intent'),
  ('زهقان','bored','intent'),
  ('زهقانة','bored','intent'),
  ('زهقانه','bored','intent'),
  ('زهقت','bored','intent'),
  ('ملل','bored','intent'),
  ('مملل','bored','intent'),
  ('مش عارف اعمل ايه','bored','intent'),
  ('مفيش حاجة اعمل','bored','intent'),
  ('ازهق','bored','intent'),
  ('bored','bored','intent'),
  ('im bored','bored','intent'),
  ('i am bored','bored','intent'),
  ('z2han','bored','intent'),
  ('zahqan','bored','intent'),
  ('zah2an','bored','intent'),
  ('zahqana','bored','intent'),
  ('zah2ana','bored','intent'),
  ('mesh 3aref a3mel eh','bored','intent'),
  ('جعان','hungry','intent'),
  ('جعانة','hungry','intent'),
  ('جعانه','hungry','intent'),
  ('جعت','hungry','intent'),
  ('عايز اكل','hungry','intent'),
  ('عاوز اكل','hungry','intent'),
  ('هاكل ايه','hungry','intent'),
  ('اكل ايه','hungry','intent'),
  ('ناكل ايه','hungry','intent'),
  ('ga3an','hungry','intent'),
  ('ga3ana','hungry','intent'),
  ('3ayez akol','hungry','intent'),
  ('3awez akol','hungry','intent'),
  ('hungry','hungry','intent'),
  ('im hungry','hungry','intent'),
  ('i am hungry','hungry','intent'),
  ('what should i eat','hungry','intent'),
  ('food','hungry','intent'),
  ('الجو عامل ايه','weather','intent'),
  ('الجو ايه','weather','intent'),
  ('الطقس','weather','intent'),
  ('الطقس ايه','weather','intent'),
  ('الجو حر','weather','intent'),
  ('الجو برد','weather','intent'),
  ('الجو النهارده','weather','intent'),
  ('el gaw','weather','intent'),
  ('el gaw eh','weather','intent'),
  ('el ta2s','weather','intent'),
  ('el taqs','weather','intent'),
  ('weather','weather','intent'),
  ('whats the weather','weather','intent'),
  ('how is the weather','weather','intent'),
  ('is it hot','weather','intent'),
  ('is it cold','weather','intent'),
  ('مبروك','congrats','intent'),
  ('الف مبروك','congrats','intent'),
  ('ألف مبروك','congrats','intent'),
  ('مبروك عليا','congrats','intent'),
  ('مبروك عليك','congrats','intent'),
  ('mabrouk','congrats','intent'),
  ('mabrook','congrats','intent'),
  ('mabruk','congrats','intent'),
  ('alf mabrouk','congrats','intent'),
  ('congrats','congrats','intent'),
  ('congratulations','congrats','intent'),
  ('congratulation','congrats','intent'),
  ('بحبك','love','intent'),
  ('احبك','love','intent'),
  ('بحبك يا برايم','love','intent'),
  ('انا بحبك','love','intent'),
  ('love you','love','intent'),
  ('i love you','love','intent'),
  ('luv u','love','intent'),
  ('ba7ebak','love','intent'),
  ('bahebak','love','intent'),
  ('ba7bak','love','intent'),
  ('bahbak','love','intent'),
  ('ana ba7ebak','love','intent'),
  ('مع السلامة','bye','intent'),
  ('مع السلامه','bye','intent'),
  ('سلامو عليكم','bye','intent'),
  ('يلا سلام','bye','intent'),
  ('باي','bye','intent'),
  ('باى','bye','intent'),
  ('تصبح على خير','bye','intent'),
  ('تصبحي على خير','bye','intent'),
  ('سلام بقى','bye','intent'),
  ('الى اللقاء','bye','intent'),
  ('إلى اللقاء','bye','intent'),
  ('اشوفك بعدين','bye','intent'),
  ('اشوفك','bye','intent'),
  ('يلا باي','bye','intent'),
  ('bye','bye','intent'),
  ('bye bye','bye','intent'),
  ('goodbye','bye','intent'),
  ('good bye','bye','intent'),
  ('see you','bye','intent'),
  ('see ya','bye','intent'),
  ('good night','bye','intent'),
  ('gn','bye','intent'),
  ('ma3 el salama','bye','intent'),
  ('ma3a salama','bye','intent'),
  ('yalla salam','bye','intent'),
  ('yalla bye','bye','intent'),
  ('tosbah 3ala 5eir','bye','intent'),
  ('tosbah 3ala kheir','bye','intent'),
  ('tesbah 3ala 5eir','bye','intent'),
  ('ashoufak','bye','intent'),
  ('ashofak','bye','intent'),
  ('الساعة كام','time_ask','intent'),
  ('الساعه كام','time_ask','intent'),
  ('الساعة كام دلوقتي','time_ask','intent'),
  ('الساعه كام دلوقتي','time_ask','intent'),
  ('الوقت كام','time_ask','intent'),
  ('كام الساعة','time_ask','intent'),
  ('كام الساعه','time_ask','intent'),
  ('الوقت ايه','time_ask','intent'),
  ('el sa3a kam','time_ask','intent'),
  ('el sa3a kam delwa2ty','time_ask','intent'),
  ('el sa3a kam delwaqty','time_ask','intent'),
  ('el wa2t kam','time_ask','intent'),
  ('kam el sa3a','time_ask','intent'),
  ('what time is it','time_ask','intent'),
  ('whats the time','time_ask','intent'),
  ('what is the time','time_ask','intent'),
  ('current time','time_ask','intent'),
  ('time now','time_ask','intent'),
  ('النهارده ايه','date_ask','intent'),
  ('النهاردة ايه','date_ask','intent'),
  ('النهارده كام','date_ask','intent'),
  ('النهاردة كام','date_ask','intent'),
  ('النهارده يوم ايه','date_ask','intent'),
  ('النهاردة يوم ايه','date_ask','intent'),
  ('التاريخ ايه','date_ask','intent'),
  ('التاريخ كام','date_ask','intent'),
  ('انهي يوم','date_ask','intent'),
  ('ايه تاريخ النهارده','date_ask','intent'),
  ('el naharda eh','date_ask','intent'),
  ('el naharda kam','date_ask','intent'),
  ('naharda eh','date_ask','intent'),
  ('naharda kam','date_ask','intent'),
  ('el naharda yom eh','date_ask','intent'),
  ('el ta2reekh eh','date_ask','intent'),
  ('el tareekh eh','date_ask','intent'),
  ('what day is it','date_ask','intent'),
  ('what is the date','date_ask','intent'),
  ('whats the date','date_ask','intent'),
  ('todays date','date_ask','intent'),
  ('today date','date_ask','intent'),
  ('what day is today','date_ask','intent'),
  ('رمضان كريم','occasion_greet','intent'),
  ('رمضان مبارك','occasion_greet','intent'),
  ('كل سنة وانت طيب','occasion_greet','intent'),
  ('كل سنة وانتي طيبة','occasion_greet','intent'),
  ('كل سنة وانتم طيبين','occasion_greet','intent'),
  ('كل عام وانتم بخير','occasion_greet','intent'),
  ('كل عام وانت بخير','occasion_greet','intent'),
  ('عيد مبارك','occasion_greet','intent'),
  ('عيد سعيد','occasion_greet','intent'),
  ('عيد اضحى مبارك','occasion_greet','intent'),
  ('عيد فطر سعيد','occasion_greet','intent'),
  ('اضحى مبارك','occasion_greet','intent'),
  ('جمعة مباركة','occasion_greet','intent'),
  ('جمعه مباركه','occasion_greet','intent'),
  ('كل سنه وانت طيب','occasion_greet','intent'),
  ('كل سنه وانتم طيبين','occasion_greet','intent'),
  ('ramadan kareem','occasion_greet','intent'),
  ('ramadan mubarak','occasion_greet','intent'),
  ('eid mubarak','occasion_greet','intent'),
  ('eid said','occasion_greet','intent'),
  ('eid saeed','occasion_greet','intent'),
  ('kol sana we enta tayeb','occasion_greet','intent'),
  ('kol sana wenta tayeb','occasion_greet','intent'),
  ('kol sana winta tayeb','occasion_greet','intent'),
  ('kol sana we enty tayeba','occasion_greet','intent'),
  ('kol 3am we antum bekhair','occasion_greet','intent'),
  ('kol 3am wa antum bikhair','occasion_greet','intent'),
  ('happy eid','occasion_greet','intent'),
  ('happy ramadan','occasion_greet','intent'),
  ('happy new year','occasion_greet','intent'),
  ('merry christmas','occasion_greet','intent'),
  ('happy holidays','occasion_greet','intent'),
  ('happy friday','occasion_greet','intent'),
  ('gom3a mobaraka','occasion_greet','intent'),
  ('gom3a mubaraka','occasion_greet','intent'),
  ('امتى رمضان','occasion_when','intent'),
  ('رمضان امتى','occasion_when','intent'),
  ('باقي كام على رمضان','occasion_when','intent'),
  ('كام يوم على رمضان','occasion_when','intent'),
  ('امتى العيد','occasion_when','intent'),
  ('العيد امتى','occasion_when','intent'),
  ('باقي كام على العيد','occasion_when','intent'),
  ('كام يوم على العيد','occasion_when','intent'),
  ('امتى عيد الفطر','occasion_when','intent'),
  ('امتى عيد الاضحى','occasion_when','intent'),
  ('عيد الفطر امتى','occasion_when','intent'),
  ('عيد الاضحى امتى','occasion_when','intent'),
  ('امتى الاجازة','occasion_when','intent'),
  ('الاجازة امتى','occasion_when','intent'),
  ('emta ramadan','occasion_when','intent'),
  ('ramadan emta','occasion_when','intent'),
  ('baqy kam 3ala ramadan','occasion_when','intent'),
  ('kam yom 3ala ramadan','occasion_when','intent'),
  ('emta el 3eid','occasion_when','intent'),
  ('el 3eid emta','occasion_when','intent'),
  ('emta el eid','occasion_when','intent'),
  ('el eid emta','occasion_when','intent'),
  ('kam yom 3ala el 3eid','occasion_when','intent'),
  ('when is ramadan','occasion_when','intent'),
  ('when is eid','occasion_when','intent'),
  ('when is the next eid','occasion_when','intent'),
  ('how many days until ramadan','occasion_when','intent'),
  ('how many days until eid','occasion_when','intent')
) AS v(p, c, k)
WHERE char_length(private.prime_stem(v.p)) >= 2
ON CONFLICT (kind, phrase_norm) DO NOTHING;

CREATE OR REPLACE FUNCTION private.prime_pick(p_options text[])
 RETURNS text
 LANGUAGE sql
 VOLATILE
 SET search_path TO ''
AS $function$
  SELECT p_options[1 + floor(random() * cardinality(p_options))::integer];
$function$;

CREATE OR REPLACE FUNCTION private.prime_personality(p_intent text, p_stem text, p_name text, p_role text)
 RETURNS text
 LANGUAGE plpgsql
 VOLATILE
 SET search_path TO ''
AS $function$
DECLARE
  v_now timestamp := (now() AT TIME ZONE 'Africa/Cairo');
  v_h integer := extract(hour FROM (now() AT TIME ZONE 'Africa/Cairo'))::integer;
  v_dow integer := extract(dow FROM (now() AT TIME ZONE 'Africa/Cairo'))::integer;
  v_band text;
  v_who text;
  v_occ_greet text;
  v_occ_code text;
  v_tail text := '';
  v_days text[] := ARRAY['الأحد','الاثنين','الثلاثاء','الأربعاء','الخميس','الجمعة','السبت'];
  v_ans text;
  v_code text;
  v_start date;
  v_est boolean;
  v_n integer;
  v_s text := coalesce(p_stem, '');
BEGIN
  IF p_intent IS NULL OR p_intent NOT IN ('greeting','thanks','bye','who_are_you','robot_q','creator','joke','compliment','mild_insult','sorry','bored','hungry',
       'weather','congrats','love','time_ask','date_ask','occasion_greet','occasion_when') THEN
    RETURN NULL;
  END IF;
  v_band := CASE WHEN v_h BETWEEN 5 AND 11 THEN 'morning' WHEN v_h BETWEEN 12 AND 16 THEN 'noon' WHEN v_h BETWEEN 17 AND 21 THEN 'evening' ELSE 'night' END;
  v_who := CASE WHEN coalesce(p_name, '') <> '' THEN ' يا ' || p_name || CASE WHEN p_role IN ('owner','admin') THEN ' باشا' ELSE '' END
                WHEN p_role IN ('owner','admin') THEN ' يا باشا' ELSE '' END;
  SELECT o.greeting, o.code INTO v_occ_greet, v_occ_code
  FROM private.prime_occasions o WHERE v_now::date BETWEEN o.starts_on AND o.ends_on ORDER BY (o.ends_on - o.starts_on), o.starts_on LIMIT 1;
  IF v_occ_greet IS NOT NULL THEN v_tail := E'\n' || v_occ_greet; END IF;
  IF v_dow = 5 AND v_band IN ('morning','noon') THEN v_tail := v_tail || E'\nوجمعة مباركة عليك.'; END IF;
  IF v_occ_code = 'ramadan' AND v_band = 'evening' THEN v_tail := v_tail || E'\nوفطار شهي إن شاء الله.'; END IF;

  IF p_intent = 'greeting' THEN
    IF v_s ~ '(^| )(سلام|salam|assalamu)( |$)' AND v_s !~ '(^| )(صباح|مساء|sabah|masa)' THEN
      v_ans := private.prime_pick(ARRAY['وعليكم السلام ورحمة الله وبركاته' || v_who || '، نورتنا!',
                                         'وعليكم السلام ورحمة الله' || v_who || '، أهلا وسهلا بيك!']);
    ELSIF v_s ~ '(^| )(عامل|عامله|ازيك|ازيكم|ازيكو|اخبارك|اخبار|3amel|3amla|ezayak|ezayek|ezaykom|a5barak|akhbarak|how|sup|wassup|whats)( |$)' THEN
      v_ans := private.prime_pick(ARRAY['أنا تمام الحمد لله، وبقيت أحسن لما كلمتني' || v_who || '! وانت عامل إيه؟',
                                         'الحمد لله زي الفل' || v_who || '، شغال ومستعد! إنت أخبارك إيه؟',
                                         'تمام التمام' || v_who || '، ربنا يخليك. نورت!']);
    ELSIF v_s ~ '(^| )(صباح|sabah|sabaho|morning)' THEN
      IF v_band IN ('morning','noon') THEN
        v_ans := private.prime_pick(ARRAY['صباح النور' || v_who || '! صباحك فل وياسمين.',
                                           'صباح الفل' || v_who || '! يوم جميل إن شاء الله.',
                                           'صباح الورد' || v_who || '! ابتدينا اليوم بنشاط.']);
      ELSE
        v_ans := 'صباح النور' || v_who || '! بس الوقت عندنا بقى ' || CASE WHEN v_band = 'evening' THEN 'مسا' ELSE 'ليل' END || '، شكلك صاحي بدري أوي ولا لسه ما نمتش؟';
      END IF;
    ELSIF v_s ~ '(^| )(مساء|masa|masa2|masak|مساك|evening)' THEN
      IF v_band IN ('evening','night','noon') THEN
        v_ans := private.prime_pick(ARRAY['مساء النور' || v_who || '! مساك سكر.',
                                           'مساء الفل' || v_who || '! نورت المسا.',
                                           'مساء الورد' || v_who || '! أهلا بيك.']);
      ELSE
        v_ans := 'مساء النور' || v_who || '! بس لسه بدري، الدنيا صباح عندنا.';
      END IF;
    ELSE
      v_ans := CASE v_band
        WHEN 'morning' THEN private.prime_pick(ARRAY['صباح الفل' || v_who || '! أنا برايم، أقدر أساعدك في إيه؟', 'صباح النور' || v_who || '! أهلا بيك، أنا برايم.'])
        WHEN 'noon' THEN private.prime_pick(ARRAY['أهلا بيك' || v_who || '! أنا برايم، يوم حلو إن شاء الله.', 'هلا والله' || v_who || '! أقدر أساعدك في إيه النهارده؟'])
        WHEN 'evening' THEN private.prime_pick(ARRAY['مساء الفل' || v_who || '! أنا برايم، إيه اللي محتاجه؟', 'مساء النور' || v_who || '! نورت.'])
        ELSE private.prime_pick(ARRAY['أهلا' || v_who || '! لسه صاحي في الوقت ده؟ أنا برايم وجاهز.', 'مساء الخير' || v_who || '! سهران معانا؟ قولي أساعدك في إيه.'])
      END;
    END IF;
    RETURN v_ans || v_tail || E'\nتحب أساعدك في إيه؟';
  ELSIF p_intent = 'thanks' THEN
    RETURN private.prime_pick(ARRAY['العفو' || v_who || '، ده واجبي!', 'ولا يهمك' || v_who || '، أنا موجود في أي وقت.', 'تحت أمرك' || v_who || '، سلامتك!', 'على إيه بس' || v_who || '، دي مهمتي.']);
  ELSIF p_intent = 'bye' THEN
    v_ans := CASE WHEN v_band = 'night' THEN private.prime_pick(ARRAY['تصبح على خير' || v_who || '، أحلام سعيدة!', 'ليلة سعيدة' || v_who || '، نام كويس.'])
                  WHEN v_band = 'morning' THEN private.prime_pick(ARRAY['مع السلامة' || v_who || '، يومك سعيد!', 'في أمان الله' || v_who || '، يوم موفق.'])
                  ELSE private.prime_pick(ARRAY['مع السلامة' || v_who || '، نورتنا!', 'في أمان الله' || v_who || '، أشوفك قريب.']) END;
    RETURN v_ans || v_tail;
  ELSIF p_intent = 'who_are_you' THEN
    RETURN 'أنا برايم، مساعد وصلة. أساعدك تلاقي الخدمة اللي محتاجها، وأجاوبك عن الأسعار وطلباتك وأي حاجة عن المنصة.';
  ELSIF p_intent = 'robot_q' THEN
    RETURN 'أنا روبوت، بس روبوت لطيف وخفيف الدم 😄. أنا بتعلم من أسئلتكم، وبفهم كلامك بالمصري.';
  ELSIF p_intent = 'creator' THEN
    RETURN 'أنا من فريق وصلة. اتعملت عشان أخدمك وأسهل عليك كل حاجة على المنصة.';
  ELSIF p_intent = 'joke' THEN
    RETURN private.prime_pick(ARRAY[
      'مرة واحد بخيل اشترى ساعة بايظة، سألوه ليه؟ قال: عشان تضبط مرتين في اليوم.',
      'مرة تلميذ اتأخر على المدرسة، المدرس سأله ليه؟ قاله: كان فيه لافتة مكتوب عليها المدرسة قدام، امشي ببطء.',
      'قال واحد لصاحبه: أنا هعمل رجيم. صاحبه: امتى؟ قاله: بعد العزومة.',
      'ليه الكمبيوتر سخن؟ لأنه فتح ويندوز كتير.',
      'واحد سأل صاحبه: تعرف تسبح؟ قاله: أيوه. قاله: طب انزل في الترعة. قاله: لأ، لسه ما جبتش المايوه!']);
  ELSIF p_intent = 'compliment' THEN
    RETURN private.prime_pick(ARRAY['ميرسي' || v_who || '، ده من ذوقك!', 'تسلم' || v_who || '، كلامك بيشجعني!', 'أنا بحاول أكون عند حسن ظنك 😄', 'يا سلام عليك، إنت اللي جامد.']);
  ELSIF p_intent = 'mild_insult' THEN
    RETURN private.prime_pick(ARRAY['معلش' || v_who || '، لو مفهمتش قصدك قولي بطريقة تانية وأنا أحاول تاني.', 'أنا لسه بتعلم، وكل سؤال بتسأله بيخليني أحسن. جرب تقولها بكلمات تانية.']);
  ELSIF p_intent = 'sorry' THEN
    RETURN private.prime_pick(ARRAY['ولا يهمك' || v_who || '، مفيش داعي للأسف.', 'معلش، كله يتصلح. أقدر أساعدك في إيه؟']);
  ELSIF p_intent = 'bored' THEN
    RETURN private.prime_pick(ARRAY['ولا يهمك' || v_who || '! تحب أحكيلك نكتة؟ قولي نكتة وأنا أضحكك.', 'الزهق ده بيروح بسرعة! جرب تسألني نكتة، أو اتفرج على الخدمات اللي عندنا.']);
  ELSIF p_intent = 'hungry' THEN
    RETURN private.prime_pick(ARRAY['يا ساتر! اللهم صلي على النبي، الجوع وحش 😄. ممكن تلاقي أكل بيتي من قسم الطبخ المنزلي على وصلة.', 'أنا روبوت مباكلش للأسف، بس لو جعان دور على الطبخ المنزلي في وصلة.']);
  ELSIF p_intent = 'weather' THEN
    RETURN private.prime_pick(ARRAY['معنديش نشرة جوية للأسف 😄، بص من الشباك أحسن! بس أقدر أساعدك في أي خدمة، تكييف أو سخان مثلا.', 'الجو مش في اختصاصي، بس لو التكييف أو السخان محتاج صيانة اسألني.']);
  ELSIF p_intent = 'congrats' THEN
    RETURN private.prime_pick(ARRAY['الله يبارك فيك' || v_who || '! ألف مبروك، وعقبال كل الفرح.', 'مبروك مقدما وفعلا! وعقبال ما نفرح بيك دايما.']);
  ELSIF p_intent = 'love' THEN
    RETURN private.prime_pick(ARRAY['ده من ذوقك' || v_who || '! أنا بحبك في الله وبحب أخدمك 😄', 'ميرسي أوي! أنا كمان بحب شغلي معاك.']);
  ELSIF p_intent = 'time_ask' THEN
    RETURN 'الساعة دلوقتي ' || to_char(v_now, 'HH12:MI') || ' ' || CASE WHEN v_h < 12 THEN 'صباحا' ELSE 'مساء' END || ' بتوقيت القاهرة.';
  ELSIF p_intent = 'date_ask' THEN
    RETURN 'النهارده ' || v_days[v_dow + 1] || ' ' || to_char(v_now, 'DD/MM/YYYY') || '.' || v_tail;
  ELSIF p_intent = 'occasion_greet' THEN
    IF v_occ_greet IS NOT NULL THEN
      RETURN 'وانت طيب' || v_who || E' وبخير! \n' || v_occ_greet;
    ELSIF v_dow = 5 THEN
      RETURN 'جمعة مباركة عليك' || v_who || ' وعلى كل اللي بتحبهم.';
    ELSE
      RETURN 'وانت طيب' || v_who || '، وكل سنة وإنت بخير ومعاك كل اللي بتتمناه!';
    END IF;
  ELSIF p_intent = 'occasion_when' THEN
    v_code := CASE WHEN v_s ~ 'رمضان|ramadan' THEN 'ramadan' WHEN v_s ~ 'اضحي|اضحى|adha' THEN 'eid_adha' WHEN v_s ~ 'فطر|fitr' THEN 'eid_fitr' ELSE 'eid' END;
    SELECT o.code, o.starts_on, o.is_estimate INTO v_code, v_start, v_est
    FROM private.prime_occasions o
    WHERE o.ends_on >= v_now::date AND (o.code = v_code OR (v_code = 'eid' AND o.code IN ('eid_fitr','eid_adha')))
    ORDER BY o.starts_on LIMIT 1;
    IF v_start IS NULL THEN RETURN 'مش لاقي ميعاده عندي دلوقتي، هتحدث الجدول قريب.'; END IF;
    SELECT o.name_ar INTO v_ans FROM private.prime_occasions o WHERE o.code = v_code AND o.starts_on = v_start;
    IF v_start <= v_now::date THEN
      RETURN 'احنا فيه دلوقتي! ' || v_ans || ' ' || coalesce(v_occ_greet, '');
    END IF;
    v_n := v_start - v_now::date;
    RETURN 'باقي ' || v_n || ' يوم على ' || v_ans || ' (يوم ' || v_days[extract(dow FROM v_start)::integer + 1] || ' ' || to_char(v_start, 'DD/MM/YYYY') || ').' ||
           CASE WHEN v_est THEN ' والميعاد تقريبي لحد ما دار الإفتاء تعلن الرؤية.' ELSE '' END;
  END IF;
  RETURN NULL;
END;
$function$;

CREATE OR REPLACE FUNCTION public.prime_answer(p_message text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid := (SELECT auth.uid());
  v_msg text := btrim(coalesce(p_message, ''));
  v_stem text;
  v_padded text;
  v_role text;
  v_name text;
  v_perms text[] := ARRAY[]::text[];
  v_is_admin boolean := false;
  v_intent text;
  v_service_id uuid;
  v_service_name text;
  v_city_id uuid;
  v_city_name text;
  v_cat_id uuid;
  v_cat_name text;
  v_answer text;
  v_sugg jsonb;
  v_matched boolean := true;
  v_n integer;
  v_min numeric; v_max numeric;
  v_lines text;
  v_words text[];
  v_kb text;
  v_stop text[] := ARRAY['ايه','ازاي','عايز','عاوز','هل','لو','في','من','علي','الي','عن','ده','دي','انا','انت','ممكن','لي','لى','كيف','ما','هو','هي'];
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501'; END IF;
  IF v_msg = '' THEN RAISE EXCEPTION 'Empty message' USING ERRCODE = '22023'; END IF;
  IF char_length(v_msg) > 500 THEN RAISE EXCEPTION 'Message too long' USING ERRCODE = '22023'; END IF;

  -- who is asking
  SELECT p.role, split_part(btrim(coalesce(p.full_name,'')), ' ', 1) INTO v_role, v_name
  FROM public.profiles p WHERE p.id = v_uid AND p.status = 'active';
  IF v_role IS NULL THEN RAISE EXCEPTION 'Account not active' USING ERRCODE = '42501'; END IF;
  v_is_admin := private.is_active_admin();
  IF private.is_active_owner() THEN v_role := 'owner';
  ELSIF v_is_admin THEN v_role := 'admin'; END IF;
  IF v_role IN ('owner','admin') THEN
    v_perms := ARRAY['dashboard.view','customers.view','customers.manage','providers.view','providers.review','requests.view','requests.manage',
                     'services.view','services.manage','categories.view','categories.manage','messages.view','payments.view','payments.manage',
                     'reports.view','ads.view','ads.manage','settings.view','settings.manage','support.view','support.manage'];
  ELSIF v_role = 'staff' THEN
    SELECT coalesce(array_agg(DISTINCT k), ARRAY[]::text[]) INTO v_perms
    FROM public.staff_permissions sp, unnest(sp.permissions) k WHERE sp.user_id = v_uid AND sp.is_active;
  END IF;
  IF v_role NOT IN ('customer','provider','staff','admin','owner') THEN v_role := 'customer'; END IF;

  v_stem := private.prime_stem(v_msg);
  v_padded := ' ' || v_stem || ' ';

  -- intent: highest summed phrase length (in words), then fixed priority
  SELECT s.canonical INTO v_intent
  FROM private.prime_synonyms s
  WHERE s.kind = 'intent' AND s.is_active AND position(' ' || s.phrase_norm || ' ' IN v_padded) > 0
  GROUP BY s.canonical
  ORDER BY sum(array_length(string_to_array(s.phrase_norm, ' '), 1)) DESC,
           array_position(ARRAY['complaint','wallet','order_track','cancel','price','register_provider','payment','contact','staff_orders','what_is','order_new','help','thanks','greeting'], s.canonical)
  LIMIT 1;

  -- service entity: longest match among service names and synonyms
  SELECT x.id, x.name_ar INTO v_service_id, v_service_name FROM (
    SELECT sv.id, sv.name_ar, length(private.prime_stem(sv.name_ar)) AS l
    FROM public.services sv
    WHERE sv.is_active AND position(' ' || private.prime_stem(sv.name_ar) || ' ' IN v_padded) > 0
    UNION ALL
    SELECT sv.id, sv.name_ar, length(s.phrase_norm)
    FROM private.prime_synonyms s
    JOIN public.services sv ON private.prime_stem(sv.name_ar) = private.prime_stem(s.canonical) AND sv.is_active
    WHERE s.kind = 'service' AND s.is_active AND position(' ' || s.phrase_norm || ' ' IN v_padded) > 0
    UNION ALL
    SELECT sv.id, sv.name_ar, length(private.prime_normalize(sv.name_en))
    FROM public.services sv
    WHERE sv.is_active AND sv.name_en IS NOT NULL AND length(private.prime_normalize(sv.name_en)) >= 4
      AND position(' ' || private.prime_normalize(sv.name_en) || ' ' IN v_padded) > 0
  ) x ORDER BY x.l DESC, x.name_ar LIMIT 1;

  -- city entity
  SELECT x.id, x.name_ar INTO v_city_id, v_city_name FROM (
    SELECT c.id, c.name_ar, length(private.prime_stem(c.name_ar)) AS l
    FROM private.geo_cities c
    WHERE c.is_active AND position(' ' || private.prime_stem(c.name_ar) || ' ' IN v_padded) > 0
    UNION ALL
    SELECT c.id, c.name_ar, length(s.phrase_norm)
    FROM private.prime_synonyms s
    JOIN private.geo_cities c ON private.prime_stem(c.name_ar) = private.prime_stem(s.canonical) AND c.is_active
    WHERE s.kind = 'city' AND s.is_active AND position(' ' || s.phrase_norm || ' ' IN v_padded) > 0
    UNION ALL
    SELECT a.city_id, c2.name_ar, length(a.stripped)
    FROM (SELECT ga.city_id, private.prime_stem(regexp_replace(ga.name_ar, '^(قسم|مركز|مدينة|اول|أول|ثان|ثاني|ثالث)[[:space:]]+', '')) AS stripped
          FROM private.geo_areas ga WHERE ga.is_active) a
    JOIN private.geo_cities c2 ON c2.id = a.city_id AND c2.is_active
    WHERE length(a.stripped) >= 5 AND position(' ' || a.stripped || ' ' IN v_padded) > 0
  ) x ORDER BY x.l DESC, x.name_ar LIMIT 1;

  -- category entity
  SELECT x.id, x.name_ar INTO v_cat_id, v_cat_name FROM (
    SELECT ct.id, ct.name_ar, length(private.prime_stem(ct.name_ar)) AS l
    FROM public.categories ct
    WHERE ct.is_active AND ct.name_ar NOT LIKE '%تجرب%' AND position(' ' || private.prime_stem(ct.name_ar) || ' ' IN v_padded) > 0
    UNION ALL
    SELECT ct.id, ct.name_ar, length(s.phrase_norm)
    FROM private.prime_synonyms s
    JOIN public.categories ct ON private.prime_stem(ct.name_ar) = private.prime_stem(s.canonical) AND ct.is_active AND ct.name_ar NOT LIKE '%تجرب%'
    WHERE s.kind = 'category' AND s.is_active AND position(' ' || s.phrase_norm || ' ' IN v_padded) > 0
  ) x ORDER BY x.l DESC, x.name_ar LIMIT 1;

  -- suggestion buttons by role
  SELECT coalesce(jsonb_agg(g.label ORDER BY g.sort_order), '[]'::jsonb) INTO v_sugg
  FROM private.prime_suggestions g
  WHERE g.is_active AND v_role = ANY(g.roles) AND (g.required_permission IS NULL OR g.required_permission = ANY(v_perms));

  -- actions that belong to a role only: other roles never get them, and the question is treated as not understood
  IF v_intent IN ('order_new','cancel','register_provider') AND v_role <> 'customer' THEN v_intent := NULL; END IF;
  IF v_intent = 'wallet' AND v_role <> 'customer' THEN v_intent := NULL; END IF;
  IF v_intent = 'staff_orders' AND NOT (v_role IN ('staff','admin','owner') AND 'requests.view' = ANY(v_perms)) THEN v_intent := NULL; END IF;
  IF v_intent = 'complaint' AND v_role IN ('staff','admin','owner') AND NOT ('support.view' = ANY(v_perms)) THEN v_intent := NULL; END IF;
  IF v_intent = 'order_track' AND v_role IN ('staff','admin','owner') AND NOT ('requests.view' = ANY(v_perms)) THEN v_intent := NULL; END IF;

  -- 1) service asked about
  IF v_service_id IS NOT NULL AND (v_intent IS NULL OR v_intent IN ('price','order_new','help','greeting')) THEN
    IF v_intent = 'price' THEN
      SELECT min(ps.price), max(ps.price), count(*) INTO v_min, v_max, v_n
      FROM public.provider_services ps WHERE ps.service_id = v_service_id AND ps.is_active AND ps.price > 0;
      IF v_n > 0 THEN
        v_answer := 'أسعار خدمة ' || v_service_name || ' عند مزودي الخدمة بتبدأ من ' || trim(to_char(v_min, 'FM999999990.##')) ||
                    ' EGP لحد ' || trim(to_char(v_max, 'FM999999990.##')) || ' EGP، والسعر النهائي بيتحدد حسب تفاصيل طلبك.';
      ELSE
        v_answer := 'لسه مفيش أسعار معلنة لخدمة ' || v_service_name || '. ' || CASE WHEN v_role = 'customer' THEN ' ابعت طلبك بالتفاصيل وهتوصلك عروض الأسعار من مزودي الخدمة.' ELSE '' END;
      END IF;
    ELSE
      SELECT count(DISTINCT ps.provider_id) INTO v_n
      FROM public.provider_services ps
      WHERE ps.service_id = v_service_id AND ps.is_active
        AND (v_city_id IS NULL OR EXISTS (SELECT 1 FROM public.provider_service_areas a WHERE a.provider_profile_id = ps.provider_id AND a.city_id = v_city_id));
      v_answer := 'خدمة ' || v_service_name || ' متاحة على وصلة' || CASE WHEN v_city_id IS NOT NULL THEN ' في ' || v_city_name ELSE '' END ||
                  CASE WHEN v_n > 0 THEN '، وفيه ' || v_n || ' مزود خدمة بيقدمها.' ELSE '، بس مفيش مزود خدمة مسجل ليها دلوقتي.' END ||
                  CASE WHEN v_role = 'customer' THEN ' اختار الخدمة من الصفحة الرئيسية واكتب تفاصيل طلبك.' ELSE '' END;
    END IF;
    RETURN jsonb_build_object('answer', v_answer, 'suggestions', v_sugg, 'intent', coalesce(v_intent,'service'), 'matched', true);
  END IF;

  -- 1b) a whole section asked about: list its services
  IF v_cat_id IS NOT NULL AND v_service_id IS NULL AND (v_intent IS NULL OR v_intent IN ('price','order_new','help')) THEN
    SELECT string_agg(t.name_ar, '، ' ORDER BY t.name_ar) INTO v_lines
    FROM (SELECT sv.name_ar FROM public.services sv WHERE sv.category_id = v_cat_id AND sv.is_active ORDER BY sv.name_ar LIMIT 12) t;
    IF v_lines IS NOT NULL THEN
      RETURN jsonb_build_object('answer', 'قسم ' || v_cat_name || ' فيه الخدمات دي: ' || v_lines || '. قولي الخدمة اللي محتاجها وأساعدك.',
                                'suggestions', v_sugg, 'intent', 'category', 'matched', true);
    END IF;
  END IF;

  -- 1c) personality: greetings, small talk, time and occasions (Africa/Cairo)
  v_answer := private.prime_personality(v_intent, v_stem, v_name, v_role);
  IF v_answer IS NOT NULL THEN
    RETURN jsonb_build_object('answer', v_answer, 'suggestions', v_sugg, 'intent', v_intent, 'matched', true);
  END IF;

  -- 2) intents
  IF v_intent = 'greeting' THEN
    v_answer := 'أهلا' || CASE WHEN v_name <> '' THEN ' يا ' || v_name ELSE '' END || '، أنا PRIME. أقدر أساعدك في إيه النهارده؟';
  ELSIF v_intent = 'thanks' THEN
    v_answer := 'العفو، أنا في خدمتك دايما.';
  ELSIF v_intent = 'what_is' THEN
    v_answer := 'وصلة منصة خدمات بتوصّلك بمزودي خدمة في أقسام كتير زي الصيانة والتنظيف والسيارات والتعليم. تطلب الخدمة وتتابع طلبك وتدفع من مكان واحد.';
  ELSIF v_intent = 'help' THEN
    v_answer := 'أقدر أساعدك في: الأسعار، متابعة طلباتك، المحفظة، الشكاوى، وأي سؤال عن وصلة. اسألني بأي صيغة.';
  ELSIF v_intent = 'order_track' THEN
    IF v_role = 'customer' THEN
      SELECT count(*) INTO v_n FROM public.service_requests r WHERE r.customer_id = v_uid;
      IF v_n = 0 THEN v_answer := 'مفيش طلبات على حسابك لسه.';
      ELSE
        SELECT string_agg('- ' || coalesce(nullif(btrim(t.title), ''), 'طلب') || ': ' ||
                 CASE t.status WHEN 'pending' THEN 'في انتظار مزود خدمة' WHEN 'accepted' THEN 'اتقبل' WHEN 'in_progress' THEN 'جاري التنفيذ'
                               WHEN 'completed' THEN 'اتنفذ' WHEN 'cancelled' THEN 'اتلغى' ELSE t.status END, E'\n' ORDER BY t.created_at DESC)
        INTO v_lines FROM (SELECT r.title, r.status, r.created_at FROM public.service_requests r WHERE r.customer_id = v_uid ORDER BY r.created_at DESC LIMIT 3) t;
        v_answer := 'آخر طلباتك:' || E'\n' || v_lines;
      END IF;
    ELSIF v_role = 'provider' THEN
      SELECT count(*) FILTER (WHERE r.status = 'accepted'), count(*) FILTER (WHERE r.status = 'in_progress'), count(*) FILTER (WHERE r.status = 'completed')
      INTO v_n, v_min, v_max
      FROM public.service_requests r JOIN public.provider_profiles pp ON pp.id = r.provider_id WHERE pp.user_id = v_uid;
      v_answer := 'طلباتك: ' || v_n || ' مقبولة، ' || v_min::integer || ' جاري تنفيذها، ' || v_max::integer || ' منفذة.';
    ELSIF 'requests.view' = ANY(v_perms) THEN
      v_intent := 'staff_orders';
    ELSE
      v_answer := 'مفيش عندك صلاحية لعرض الطلبات.';
    END IF;
  ELSIF v_intent = 'wallet' THEN
    IF v_role = 'customer' THEN
      SELECT w.balance INTO v_min FROM public.customer_wallets w WHERE w.customer_id = v_uid;
      v_answer := 'رصيد محفظتك: ' || trim(to_char(coalesce(v_min, 0), 'FM999999990.00')) || ' EGP. الرصيد بيتضاف لما شكوى تتحل بتعويض.';
    ELSE
      v_answer := 'المحفظة متاحة لحسابات العملاء.';
    END IF;
  ELSIF v_intent = 'complaint' THEN
    IF v_role = 'customer' THEN
      SELECT count(*) INTO v_n FROM public.complaints c WHERE c.customer_id = v_uid;
      IF v_n = 0 THEN
        v_answer := 'لو عندك مشكلة في طلب، ابعت لنا تفاصيلها والإدارة هتراجعها وترد عليك.';
      ELSE
        SELECT string_agg('- ' || CASE c.status WHEN 'open' THEN 'مفتوحة' WHEN 'in_review' THEN 'تحت المراجعة' WHEN 'escalated' THEN 'تحت المراجعة'
                                               WHEN 'resolved' THEN 'اتحلت' WHEN 'rejected' THEN 'اترفضت' ELSE c.status END, E'\n' ORDER BY c.created_at DESC)
        INTO v_lines FROM (SELECT cc.status, cc.created_at FROM public.complaints cc WHERE cc.customer_id = v_uid ORDER BY cc.created_at DESC LIMIT 3) c;
        v_answer := 'آخر شكاويك:' || E'\n' || v_lines;
      END IF;
    ELSIF v_role = 'provider' THEN
      v_answer := 'شكاوى العملاء بتتراجع من الإدارة، ولو فيه شكوى على طلب عندك هتتواصل معاك الإدارة.';
    ELSIF 'support.view' = ANY(v_perms) OR v_is_admin THEN
      SELECT count(*) INTO v_n FROM public.complaints c WHERE c.status IN ('open','in_review','escalated');
      v_answer := 'الشكاوى المفتوحة دلوقتي: ' || v_n || '.';
    ELSE
      v_answer := 'مفيش عندك صلاحية لعرض الشكاوى.';
    END IF;
  ELSIF v_intent = 'cancel' THEN
    v_answer := 'تقدر تلغي طلبك من صفحة الطلب، ولازم تكتب سبب الإلغاء (5 حروف على الأقل).';
  ELSIF v_intent = 'payment' THEN
    v_answer := 'تفاصيل الدفع بتظهر في صفحة طلبك.';
  ELSIF v_intent = 'contact' THEN
    v_answer := 'التواصل بيتم من جوه المنصة، وفريق الدعم بيرد عليك من خلال الشكاوى والرسائل.';
  ELSIF v_intent = 'register_provider' THEN
    v_answer := 'تقدر تسجل كمزود خدمة من شاشة التسجيل بواتساب صحيح، وبعدها الإدارة بتراجع حسابك.';
  ELSIF v_intent = 'price' THEN
    v_answer := 'قولي اسم الخدمة اللي عايز تعرف سعرها، مثلا: سعر السباكة.';
  ELSIF v_intent = 'order_new' THEN
    v_answer := 'من الصفحة الرئيسية اختار الخدمة واكتب تفاصيل طلبك، وهيوصل لمزودي الخدمة المتاحين. قولي الخدمة اللي محتاجها وأقولك المتاح.';
  END IF;

  IF v_intent = 'staff_orders' AND v_answer IS NULL THEN
    IF 'requests.view' = ANY(v_perms) OR v_is_admin THEN
      SELECT count(*) FILTER (WHERE status = 'pending'), count(*) FILTER (WHERE status = 'accepted'), count(*) FILTER (WHERE status = 'in_progress')
      INTO v_n, v_min, v_max FROM public.service_requests;
      v_answer := 'الطلبات دلوقتي: ' || v_n || ' في الانتظار، ' || v_min::integer || ' مقبولة، ' || v_max::integer || ' جاري تنفيذها.';
    ELSE
      v_answer := 'مفيش عندك صلاحية لعرض الطلبات.';
    END IF;
  END IF;

  IF v_answer IS NOT NULL THEN
    RETURN jsonb_build_object('answer', v_answer, 'suggestions', v_sugg, 'intent', coalesce(v_intent,'general'), 'matched', true);
  END IF;

  -- 3) knowledge base (same role and permission rules as the existing retrieval)
  SELECT coalesce(array_agg(w), ARRAY[]::text[]) INTO v_words
  FROM (SELECT DISTINCT w FROM unnest(string_to_array(v_stem, ' ')) w WHERE char_length(w) >= 3 AND NOT (w = ANY(v_stop))) q;
  IF cardinality(v_words) > 0 THEN
    SELECT left(x.content, 700) INTO v_kb FROM (
      SELECT c.content,
             (SELECT count(*) FROM unnest(v_words) w WHERE position(w IN private.prime_normalize(d.title || ' ' || c.content)) > 0) AS hits
      FROM private.ai_knowledge_chunks c
      JOIN private.ai_knowledge_documents d ON d.id = c.document_id
      JOIN private.ai_knowledge_releases r ON r.id = c.release_id
      JOIN private.ai_knowledge_access a ON a.role_name = v_role AND a.category = d.category AND a.is_active
      WHERE r.is_current = true AND r.status = 'published' AND c.document_version = d.document_version AND d.status = 'approved'
        AND coalesce(a.required_permissions, ARRAY[]::text[]) <@ v_perms
        AND coalesce(d.required_permissions, ARRAY[]::text[]) <@ v_perms
    ) x WHERE x.hits >= least(2, cardinality(v_words)) ORDER BY x.hits DESC LIMIT 1;
  END IF;
  IF v_kb IS NOT NULL THEN
    RETURN jsonb_build_object('answer', v_kb, 'suggestions', v_sugg, 'intent', 'knowledge', 'matched', true);
  END IF;

  -- 4) could not answer: log it so we know what to add
  INSERT INTO private.prime_unanswered (norm_key, question, role_name)
  VALUES (md5(v_stem), left(v_msg, 250), v_role)
  ON CONFLICT (norm_key) DO UPDATE SET asked_count = private.prime_unanswered.asked_count + 1, last_asked_at = now(), resolved = false;
  RETURN jsonb_build_object(
    'answer', 'مقدرتش أفهم سؤالك بالظبط. جرب تكتبه بكلمات تانية، أو اختار من الأسئلة الجاهزة تحت. وسجلت سؤالك عشان أتعلمه.',
    'suggestions', v_sugg, 'intent', 'unknown', 'matched', false);
END;
$function$;

REVOKE ALL ON FUNCTION public.prime_answer(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.prime_answer(text) TO authenticated;
REVOKE ALL ON FUNCTION private.prime_pick(text[]), private.prime_personality(text, text, text, text) FROM PUBLIC, anon, authenticated;

COMMIT;
