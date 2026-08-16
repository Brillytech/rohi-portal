-- Storage lifecycle, part 2 of 3: hard caps the database enforces.
--
-- Two of the four buckets accepted files of any size and any type. Limits
-- belong where they cannot be bypassed by a direct API call.
--
-- The gallery's 12-per-album cap is deliberately NOT here: it already exists
-- as enforce_gallery_cap() / trigger site_gallery_cap, added in
-- 20260815110000_public_site_content.sql. Re-creating it was an error on my
-- part — it was only ever missing from the client-side grep, not from the
-- database.


-- ---------------------------------------------------------------------------
-- Bucket limits. student-photos and timetables were capped during the
-- security round; these are the two that were left open.
-- ---------------------------------------------------------------------------
update storage.buckets
   set allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp'],
       file_size_limit = 2097152    -- 2 MB: question images are re-encoded
                                    -- client-side before upload, so anything
                                    -- larger means compression was skipped
 where id = 'exam-images';

update storage.buckets
   set allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp'],
       file_size_limit = 5242880    -- 5 MB, for full-size gallery renditions
 where id = 'site-media';


-- ---------------------------------------------------------------------------
-- At most 40 images on one exam — one per question on a full paper. Guards
-- against an upload loop quietly filling the bucket.
-- ---------------------------------------------------------------------------
create or replace function public.tg_exam_image_cap()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  n integer;
begin
  if new.image_url is null then
    return new;
  end if;

  select count(*) into n
    from public.exam_questions q
   where q.exam_id = new.exam_id
     and q.image_url is not null
     and q.id <> new.id;

  if n >= 40 then
    raise exception 'This exam already has 40 question images, which is the limit.';
  end if;
  return new;
end;
$$;

drop trigger if exists exam_questions_image_cap on public.exam_questions;

create trigger exam_questions_image_cap
before insert or update on public.exam_questions
for each row execute function public.tg_exam_image_cap();
