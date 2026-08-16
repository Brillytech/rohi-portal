-- Both profile triggers fire on the same UPDATE when a student leaves: the
-- BEFORE trigger queues the photo as 'student_left_school' and nulls
-- photo_path, then the AFTER trigger sees old.photo_path <> new.photo_path
-- (new being null) and re-queues the same file as 'student_photo_replaced',
-- overwriting the more accurate reason.
--
-- The file was still deleted correctly — only the label was wrong — but the
-- admin panel shows that reason as "why it can go", so it needs to be true.
-- The AFTER trigger now stands down when the BEFORE trigger has already
-- claimed the row.
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

  -- Leaving school is handled by tg_profile_left_school_photo, which has
  -- already queued this path with the correct reason.
  if new.class in ('Graduated', 'Left School')
     and old.class is distinct from new.class then
    return new;
  end if;

  if old.photo_path is distinct from new.photo_path and old.photo_path is not null then
    perform public.queue_storage_orphan('student-photos', old.photo_path, 'student_photo_replaced');
  end if;

  return new;
end;
$$;
