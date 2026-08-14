-- Storage bucket for images attached to exam questions (diagrams, graphs,
-- figures — things that can't reasonably be typed as text or math). Not
-- public: only authenticated users can read (matches "you must be logged
-- into the portal to see this"), and only teachers/admins can upload or
-- remove images, mirroring the same role check used elsewhere.
insert into storage.buckets (id, name, public)
values ('exam-images', 'exam-images', false)
on conflict (id) do nothing;

create policy "exam images select for authenticated" on storage.objects
  for select using (bucket_id = 'exam-images' and auth.role() = 'authenticated');

create policy "exam images insert for teacher or admin" on storage.objects
  for insert with check (
    bucket_id = 'exam-images'
    and exists (select 1 from public.profiles p where p.id = auth.uid() and p.role in ('teacher', 'admin'))
  );

create policy "exam images delete for teacher or admin" on storage.objects
  for delete using (
    bucket_id = 'exam-images'
    and exists (select 1 from public.profiles p where p.id = auth.uid() and p.role in ('teacher', 'admin'))
  );
