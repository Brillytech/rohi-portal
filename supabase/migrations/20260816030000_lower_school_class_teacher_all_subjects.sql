-- Nursery, Kindergarten and Primary are taught by one class teacher who takes
-- every subject for that class. Secondary is subject-specialist, so that keeps
-- working off subject_teachers.
--
-- Without this, a Primary 3 class teacher would need 13 separate
-- subject_teachers rows before they could record a single mark, and adding a
-- subject to the curriculum would silently lock them out of it.

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
    where c.name = p_class
      and c.class_teacher_id = auth.uid()
      and (
        c.level_key ilike 'Nursery%'
        or c.level_key ilike 'Kindergarten%'
        or c.level_key ilike 'KG%'
        or c.level_key ilike 'Primary%'
      )
  );
$$;

grant execute on function public.teaches_whole_class(text) to authenticated;


-- Same shape as before, with the lower-school case added as an alternative to
-- the subject_teachers check. The teacher_id and not-published conditions are
-- unchanged, so a published row still locks to admin-only.
drop policy if exists "results teacher manage own unpublished" on public.results;

create policy "results teacher manage own unpublished" on public.results
  for all
  using (
    teacher_id = auth.uid()
    and not published
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
    and (
      exists (
        select 1 from public.subject_teachers st
        where st.subject_id = results.subject_id and st.teacher_id = auth.uid()
      )
      or public.teaches_whole_class(results.class_at_entry)
    )
  );


-- public.exams is deliberately left alone: its policy is already just
-- teacher_id = auth.uid(), so a lower-school class teacher can already create
-- a CBT for any subject. Only the dashboard's subject dropdown needed widening.
