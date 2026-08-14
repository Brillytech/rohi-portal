-- Teachers could already post to their own class and delete their own
-- posts, but had no way to fix a typo without deleting and re-posting.
-- Same scope as the existing delete policy: only their own announcements.
create policy "announcements update own by teacher" on public.announcements
  for update
  using (created_by = auth.uid())
  with check (created_by = auth.uid());
