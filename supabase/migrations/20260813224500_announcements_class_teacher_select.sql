-- A class teacher should also be able to see announcements targeted at the
-- specific class they teach (previously only students could match a
-- class-targeted announcement, via their own profiles.class).
create policy "announcements select for class teacher" on public.announcements
  for select
  using (
    exists (
      select 1 from public.classes c
      where c.class_teacher_id = auth.uid() and c.name = announcements.audience
    )
  );
