-- classes/subjects/subject_teachers predate this session's migrations, so
-- their existing RLS was unknown. They're low-sensitivity reference data
-- (school structure, not personal records), and the teacher/student
-- dashboards built in this pass need to read them:
--   - classes: to populate class pickers, and for a student's own class name
--   - subjects: to show "my subjects" / "registered subjects"
--   - subject_teachers: to know which subjects a teacher is assigned to
-- These are additive SELECT policies — Postgres RLS policies are OR'd
-- together, so this can only grant additional read access, never remove
-- any existing policy's access.
--
-- This also fixes a real bug, not just a UI gap: the "results teacher
-- manage own submissions" policy (see 20260813223047) checks
-- `exists (select 1 from subject_teachers where ...)` as the calling
-- teacher's role — that subquery is itself subject to subject_teachers'
-- RLS, so without a read policy there, the check would silently see zero
-- rows and block every teacher submission regardless of the UI.
create policy "classes select for authenticated" on public.classes
  for select using (auth.role() = 'authenticated');

create policy "subjects select for authenticated" on public.subjects
  for select using (auth.role() = 'authenticated');

create policy "subject_teachers select for authenticated" on public.subject_teachers
  for select using (auth.role() = 'authenticated');
