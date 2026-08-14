-- profiles.portal_number doubles as a student's login password, so it must
-- stay restricted to the student themself and admins (unlike
-- classes/subjects, this table should NOT get a blanket authenticated
-- SELECT policy). But teachers legitimately need class rosters — to enter
-- results (any class they're assigned a subject for) and to see students in
-- classes they're the class teacher of. This function returns only the
-- non-sensitive columns needed for that, and only to callers who are
-- themselves teachers or admins — never portal_number, never to a student.
create or replace function public.get_students_in_classes(p_classes text[])
returns table (id uuid, full_name text, surname text, class text)
language sql
security definer
set search_path = public
stable
as $$
  select p.id, p.full_name, p.surname, p.class
  from public.profiles p
  where p.role = 'student'
    and p.class = any(p_classes)
    and exists (
      select 1 from public.profiles caller
      where caller.id = auth.uid() and caller.role in ('teacher', 'admin')
    );
$$;

grant execute on function public.get_students_in_classes(text[]) to authenticated;
