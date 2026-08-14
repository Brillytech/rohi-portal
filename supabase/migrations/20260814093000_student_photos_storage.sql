-- Storage bucket for student passport photos (report card header). Not
-- public. Uploaded/removed by admin only. Readable by admin/teachers
-- (routine school use) or by the student viewing their own — never by an
-- arbitrary other student. Files are stored at "{student_id}/filename" so
-- the self-access check can read the id straight out of the path.
insert into storage.buckets (id, name, public)
values ('student-photos', 'student-photos', false)
on conflict (id) do nothing;

create policy "student photos select for admin/teacher or self" on storage.objects
  for select using (
    bucket_id = 'student-photos'
    and (
      (storage.foldername(name))[1] = auth.uid()::text
      or exists (select 1 from public.profiles p where p.id = auth.uid() and p.role in ('teacher', 'admin'))
    )
  );

create policy "student photos insert for admin" on storage.objects
  for insert with check (
    bucket_id = 'student-photos'
    and exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin')
  );

create policy "student photos delete for admin" on storage.objects
  for delete using (
    bucket_id = 'student-photos'
    and exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin')
  );
