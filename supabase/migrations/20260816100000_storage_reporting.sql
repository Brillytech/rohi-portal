-- Storage lifecycle, part 3 of 3: reporting.
--
-- storage.objects is not exposed over the REST API, so the dashboard cannot
-- measure usage or find orphans on its own. These security definer functions
-- give admins exactly those two answers and nothing else.


-- ---------------------------------------------------------------------------
-- Per-bucket usage. metadata->>'size' is the byte count storage records at
-- upload time.
-- ---------------------------------------------------------------------------
create or replace function public.get_storage_usage()
returns table (
  bucket text,
  object_count bigint,
  total_bytes bigint,
  largest_bytes bigint,
  is_public boolean
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Admins only.';
  end if;

  return query
  select
    b.id::text,
    count(o.id),
    coalesce(sum((o.metadata->>'size')::bigint), 0),
    coalesce(max((o.metadata->>'size')::bigint), 0),
    b.public
  from storage.buckets b
  left join storage.objects o on o.bucket_id = b.id
  group by b.id, b.public
  order by 3 desc;
end;
$$;

grant execute on function public.get_storage_usage() to authenticated;


-- ---------------------------------------------------------------------------
-- Objects with no owning row anywhere in the schema.
--
-- Catches everything orphaned before the triggers existed, and anything the
-- triggers cannot see (a file uploaded but never recorded because the insert
-- failed halfway).
--
-- Objects newer than an hour are excluded: an upload in progress has no
-- referencing row yet, and sweeping it would delete a file the user is in the
-- middle of attaching.
-- ---------------------------------------------------------------------------
create or replace function public.find_unreferenced_objects()
returns table (
  bucket text,
  path text,
  size_bytes bigint,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Admins only.';
  end if;

  return query
  select
    o.bucket_id::text,
    o.name::text,
    coalesce((o.metadata->>'size')::bigint, 0),
    o.created_at
  from storage.objects o
  where o.created_at < now() - interval '1 hour'
    and (
      (o.bucket_id = 'student-photos' and not exists (
        select 1 from public.profiles p where p.photo_path = o.name))
      or
      (o.bucket_id = 'timetables' and not exists (
        select 1 from public.class_timetables t where t.file_path = o.name))
      or
      (o.bucket_id = 'exam-images' and not exists (
        select 1 from public.exam_questions q where q.image_url = o.name))
      or
      (o.bucket_id = 'site-media' and not exists (
        select 1 from public.site_gallery g
         where g.thumb_path = o.name or g.full_path = o.name)
        and not exists (
        select 1 from public.public_announcements a where a.cover_image_path = o.name))
    )
  order by 3 desc;
end;
$$;

grant execute on function public.find_unreferenced_objects() to authenticated;


-- ---------------------------------------------------------------------------
-- Marks queued rows as cleared once the dashboard has actually removed them
-- through the storage API. Kept rather than deleted, so there is a record of
-- what was reclaimed and when.
-- ---------------------------------------------------------------------------
create or replace function public.mark_storage_orphans_deleted(
  p_bucket text, p_paths text[]
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  affected integer;
begin
  if not public.is_admin() then
    raise exception 'Admins only.';
  end if;

  update public.storage_orphans
     set deleted_at = now()
   where bucket = p_bucket
     and path = any(p_paths)
     and deleted_at is null;

  get diagnostics affected = row_count;
  return affected;
end;
$$;

grant execute on function public.mark_storage_orphans_deleted(text, text[]) to authenticated;
