-- A class teacher can post an announcement scoped to the one class they're
-- the class teacher of, and delete only announcements they themselves
-- posted (never an admin's or another teacher's). Admin authorship/deletion
-- is unaffected — this only adds narrowly-scoped permissions for teachers.
create policy "announcements insert for class teacher" on public.announcements
  for insert
  with check (
    created_by = auth.uid()
    and exists (
      select 1 from public.classes c
      where c.class_teacher_id = auth.uid() and c.name = announcements.audience
    )
  );

create policy "announcements delete own by teacher" on public.announcements
  for delete
  using (created_by = auth.uid());
