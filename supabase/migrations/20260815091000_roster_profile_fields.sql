-- Adds the report-card profile fields to the class roster so a class teacher
-- can see each student's photo and prefill the profile editor without a
-- second round trip per student.
--
-- portal_number is still deliberately excluded: it doubles as the student's
-- login password, so it stays restricted to the student themself and admins.
-- gender / date_of_birth / photo_path are ordinary report-card facts that
-- teachers already read off the register.
--
-- CREATE OR REPLACE cannot change a function's return columns, so this has
-- to drop first.
drop function if exists public.get_students_in_classes(text[]);

create function public.get_students_in_classes(p_classes text[])
returns table (
  id uuid,
  full_name text,
  surname text,
  class text,
  gender text,
  date_of_birth date,
  photo_path text
)
language sql
security definer
set search_path = public
stable
as $$
  select p.id, p.full_name, p.surname, p.class, p.gender, p.date_of_birth, p.photo_path
  from public.profiles p
  where p.role = 'student'
    and p.class = any(p_classes)
    and exists (
      select 1 from public.profiles caller
      where caller.id = auth.uid() and caller.role in ('teacher', 'admin')
    );
$$;

grant execute on function public.get_students_in_classes(text[]) to authenticated;
