-- Fields needed for the full report card header: gender/age/photo on the
-- student, and school-calendar facts on the term (days school opened this
-- term, when it ended, when the next one begins).
alter table public.profiles add column gender text check (gender in ('M', 'F'));
alter table public.profiles add column date_of_birth date;
alter table public.profiles add column photo_path text;

alter table public.terms add column days_opened integer check (days_opened is null or days_opened >= 0);
alter table public.terms add column term_ended date;
alter table public.terms add column next_term_begins date;

-- Attendance is entered as one aggregate per student per term (not a full
-- daily register) — days_opened already lives on terms as a single
-- school-wide fact, so only "days present" needs to be per student;
-- "days absent" is computed as the difference, never entered separately.
alter table public.student_term_remarks add column days_present integer check (days_present is null or days_present >= 0);
