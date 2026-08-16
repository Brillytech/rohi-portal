-- Storage lifecycle, part 1 of 3: a deletion queue fed by triggers.
--
-- Nothing in this project ever cleaned up storage. Several paths orphan files
-- permanently — deleting an exam cascades its questions away, taking every
-- reference to their images with it, so the files become unfindable garbage
-- that still counts against the 1 GB quota.
--
-- WHY A QUEUE RATHER THAN DELETING IN SQL:
-- Removing a row from storage.objects does NOT delete the underlying file. It
-- drops the metadata and leaves an invisible object still consuming quota.
-- Real deletion has to go through the storage API. So SQL finds and queues;
-- the admin dashboard drains the queue through the API.
--
-- WHY TRIGGERS RATHER THAN CLIENT CODE:
-- A row-level DELETE trigger fires even when the delete arrived through
-- ON DELETE CASCADE. Client code never sees cascaded rows — that is exactly
-- how the exam-image leak happens — but a trigger does. Triggers also cover
-- direct API calls that bypass the dashboard entirely.


create table public.storage_orphans (
  id uuid primary key default gen_random_uuid(),
  bucket text not null,
  path text not null,
  reason text not null,
  queued_at timestamptz not null default now(),
  deleted_at timestamptz,
  unique (bucket, path)
);

create index storage_orphans_pending_idx
  on public.storage_orphans (queued_at) where deleted_at is null;

alter table public.storage_orphans enable row level security;

create policy "storage orphans admin only" on public.storage_orphans
  for all using (public.is_admin()) with check (public.is_admin());


-- Central enqueue. Ignores nulls and blanks, and is idempotent: re-queuing a
-- path that is already pending is a no-op, while re-queuing one that was
-- already deleted resets it (the file came back and went again).
create or replace function public.queue_storage_orphan(
  p_bucket text, p_path text, p_reason text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_path is null or btrim(p_path) = '' then
    return;
  end if;

  insert into public.storage_orphans (bucket, path, reason)
  values (p_bucket, p_path, p_reason)
  on conflict (bucket, path) do update
    set reason = excluded.reason,
        queued_at = now(),
        deleted_at = null;
end;
$$;


-- ---------------------------------------------------------------------------
-- exam_questions — the cascade case. Deleting an exam removes its questions
-- via ON DELETE CASCADE; this fires for each of those rows.
-- ---------------------------------------------------------------------------
create or replace function public.tg_exam_question_storage()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    perform public.queue_storage_orphan('exam-images', old.image_url, 'exam_question_deleted');
    return old;
  end if;

  -- Image swapped for a different one: the old object is now unreferenced.
  if old.image_url is distinct from new.image_url then
    perform public.queue_storage_orphan('exam-images', old.image_url, 'exam_question_image_replaced');
  end if;
  return new;
end;
$$;

create trigger exam_questions_storage_cleanup
after update or delete on public.exam_questions
for each row execute function public.tg_exam_question_storage();


-- ---------------------------------------------------------------------------
-- public_announcements — news cover images. Paths are timestamped, so every
-- replacement leaves the previous file behind.
-- ---------------------------------------------------------------------------
create or replace function public.tg_public_announcement_storage()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    perform public.queue_storage_orphan('site-media', old.cover_image_path, 'news_post_deleted');
    return old;
  end if;

  if old.cover_image_path is distinct from new.cover_image_path then
    perform public.queue_storage_orphan('site-media', old.cover_image_path, 'news_cover_replaced');
  end if;
  return new;
end;
$$;

create trigger public_announcements_storage_cleanup
after update or delete on public.public_announcements
for each row execute function public.tg_public_announcement_storage();


-- ---------------------------------------------------------------------------
-- site_gallery — two renditions per photo. The dashboard already removes both
-- on delete; this covers any other route in.
-- ---------------------------------------------------------------------------
create or replace function public.tg_site_gallery_storage()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.queue_storage_orphan('site-media', old.thumb_path, 'gallery_photo_deleted');
  perform public.queue_storage_orphan('site-media', old.full_path, 'gallery_photo_deleted');
  return old;
end;
$$;

create trigger site_gallery_storage_cleanup
after delete on public.site_gallery
for each row execute function public.tg_site_gallery_storage();


-- ---------------------------------------------------------------------------
-- profiles — passport photos.
--
-- The UPDATE branch is the "delete the photo when a student leaves" rule. A
-- student reaches a terminal class three different ways: the "Mark left
-- school" button, the inline class dropdown on the students table, and bulk
-- promotion, which moves the highest class to Graduated. Doing this in
-- JavaScript would mean patching all three and still missing direct API
-- calls; one trigger covers every route.
--
-- photo_path is nulled at the same time so the report card immediately falls
-- back to its PHOTO placeholder rather than pointing at a file that is about
-- to disappear.
-- ---------------------------------------------------------------------------
create or replace function public.tg_profile_storage()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'DELETE' then
    perform public.queue_storage_orphan('student-photos', old.photo_path, 'student_deleted');
    return old;
  end if;

  -- Photo replaced with a different path (normally it is overwritten in place,
  -- so this only fires if the naming scheme ever changes).
  if old.photo_path is distinct from new.photo_path and old.photo_path is not null then
    perform public.queue_storage_orphan('student-photos', old.photo_path, 'student_photo_replaced');
  end if;

  return new;
end;
$$;

create trigger profiles_storage_cleanup
after update or delete on public.profiles
for each row execute function public.tg_profile_storage();


-- Separate BEFORE trigger for the leaver rule, because it has to modify the
-- row (null photo_path) rather than just observe it.
create or replace function public.tg_profile_left_school_photo()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.role = 'student'
     and new.class in ('Graduated', 'Left School')
     and old.class is distinct from new.class
     and new.photo_path is not null
  then
    perform public.queue_storage_orphan('student-photos', new.photo_path, 'student_left_school');
    new.photo_path := null;
  end if;
  return new;
end;
$$;

create trigger profiles_left_school_photo
before update on public.profiles
for each row execute function public.tg_profile_left_school_photo();


-- ---------------------------------------------------------------------------
-- Backfill: students already sitting in a terminal class keep their photos
-- today. Queue those now so the first Reconcile clears the existing backlog.
-- ---------------------------------------------------------------------------
do $$
declare r record;
begin
  for r in
    select id, photo_path from public.profiles
    where role = 'student'
      and class in ('Graduated', 'Left School')
      and photo_path is not null
  loop
    perform public.queue_storage_orphan('student-photos', r.photo_path, 'student_left_school_backfill');
    update public.profiles set photo_path = null where id = r.id;
  end loop;
end;
$$;
