-- Fix "class teacher of this student" checks in RLS.
--
-- profiles deliberately has no blanket SELECT for authenticated users, because
-- portal_number doubles as a student's password (see get_students_in_classes).
-- A policy expression like
--
--   exists (select 1 from public.profiles s join public.classes c on c.name = s.class
--           where s.id = <table>.student_id and c.class_teacher_id = auth.uid())
--
-- is evaluated as the calling user, so profiles' own RLS filters those rows
-- away and the EXISTS is always false. The policy therefore denies the class
-- teacher it was written to allow.
--
-- This affected the new attendance table and — already, before this change —
-- student_term_remarks, meaning class teachers could not actually save
-- end-of-term remarks at all.
--
-- The check moves into a security definer function so it can see profiles,
-- exactly as is_admin() and get_students_in_classes() already do.

create or replace function public.is_class_teacher_of(p_student uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.profiles s
    join public.classes c on c.name = s.class
    where s.id = p_student
      and c.class_teacher_id = auth.uid()
  );
$$;

grant execute on function public.is_class_teacher_of(uuid) to authenticated;


-- ---- attendance -----------------------------------------------------------
drop policy if exists "attendance class teacher manage own class students" on public.attendance;

create policy "attendance class teacher manage own class students" on public.attendance
  for all
  using (public.is_class_teacher_of(attendance.student_id))
  with check (public.is_class_teacher_of(attendance.student_id));


-- ---- student_term_remarks -------------------------------------------------
drop policy if exists "remarks class teacher manage own class students" on public.student_term_remarks;

create policy "remarks class teacher manage own class students" on public.student_term_remarks
  for all
  using (public.is_class_teacher_of(student_term_remarks.student_id))
  with check (public.is_class_teacher_of(student_term_remarks.student_id));
