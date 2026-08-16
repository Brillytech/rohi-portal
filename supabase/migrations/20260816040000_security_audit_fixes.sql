-- Security audit fixes.
--
-- Found by actively attacking the live system with throwaway accounts:
--
-- 1. Both edge functions create accounts without checking the caller. Anyone
--    holding the anon key — which ships in every page's source — could POST to
--    /functions/v1/register-teacher and get a role='teacher' account, then sign
--    in with the shared staff password. Fixed in the function code; this
--    migration closes what that account could still reach if one exists.
--
-- 2. `approved` was enforced only by the dashboard's own redirect. Over the
--    REST API an unapproved teacher could still read every class roster
--    (names, gender, date_of_birth, photo_path for real students) and INSERT
--    exams against real classes. RLS never checked the flag.
--
-- 3. get_students_in_classes let ANY teacher read ANY class's roster, which is
--    broader than its own stated intent ("classes they're assigned a subject
--    for, and classes they're class teacher of").


-- ---------------------------------------------------------------------------
-- An approved teacher. Security definer because profiles is not readable by
-- teachers (portal_number doubles as a password), so an inline EXISTS against
-- profiles inside a policy evaluates false for everyone.
-- ---------------------------------------------------------------------------
create or replace function public.is_approved_teacher()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = auth.uid()
      and p.role = 'teacher'
      and p.approved
  );
$$;

grant execute on function public.is_approved_teacher() to authenticated;


-- ---------------------------------------------------------------------------
-- Roster access, scoped to the classes a teacher actually has business with:
-- one they are class teacher of, or one whose curriculum includes a subject
-- they are assigned to teach. Admins keep full access.
-- ---------------------------------------------------------------------------
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
    and (
      public.is_admin()
      or (
        public.is_approved_teacher()
        and exists (
          select 1
          from public.classes c
          where c.name = p.class
            and (
              c.class_teacher_id = auth.uid()
              or exists (
                select 1
                from public.subject_teachers st
                join public.subjects s on s.id = st.subject_id
                where st.teacher_id = auth.uid()
                  and s.category = any (public.subject_categories_for_level(c.level_key))
              )
            )
        )
      )
    );
$$;

grant execute on function public.get_students_in_classes(text[]) to authenticated;


-- ---------------------------------------------------------------------------
-- Exams: an unapproved account could publish an exam to a real class.
-- ---------------------------------------------------------------------------
drop policy if exists "exams teacher manage own" on public.exams;

create policy "exams teacher manage own" on public.exams
  for all
  using (teacher_id = auth.uid() and public.is_approved_teacher())
  with check (teacher_id = auth.uid() and public.is_approved_teacher());


-- ---------------------------------------------------------------------------
-- Defence in depth on the rest of the teacher surface. These were already
-- effectively closed (an unapproved teacher has no subject_teachers rows and
-- is nobody's class teacher), but the flag belongs in the policy rather than
-- being an accident of the data.
-- ---------------------------------------------------------------------------
drop policy if exists "results teacher manage own unpublished" on public.results;

create policy "results teacher manage own unpublished" on public.results
  for all
  using (
    teacher_id = auth.uid()
    and not published
    and public.is_approved_teacher()
    and (
      exists (
        select 1 from public.subject_teachers st
        where st.subject_id = results.subject_id and st.teacher_id = auth.uid()
      )
      or public.teaches_whole_class(results.class_at_entry)
    )
  )
  with check (
    teacher_id = auth.uid()
    and not published
    and public.is_approved_teacher()
    and (
      exists (
        select 1 from public.subject_teachers st
        where st.subject_id = results.subject_id and st.teacher_id = auth.uid()
      )
      or public.teaches_whole_class(results.class_at_entry)
    )
  );


-- A class teacher must be approved before they can mark a register or write
-- end-of-term remarks.
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
    join public.profiles me on me.id = auth.uid()
    where s.id = p_student
      and c.class_teacher_id = auth.uid()
      and me.role = 'teacher'
      and me.approved
  );
$$;

create or replace function public.teaches_whole_class(p_class text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.classes c
    join public.profiles me on me.id = auth.uid()
    where c.name = p_class
      and c.class_teacher_id = auth.uid()
      and me.role = 'teacher'
      and me.approved
      and (
        c.level_key ilike 'Nursery%'
        or c.level_key ilike 'Kindergarten%'
        or c.level_key ilike 'KG%'
        or c.level_key ilike 'Primary%'
      )
  );
$$;
