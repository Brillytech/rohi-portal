-- Reverses student profile self-editing.
--
-- Students may no longer change their own age, gender or photo. This is the
-- real lock, not a hidden button: update_my_profile is dropped outright, so
-- the endpoint stops existing rather than merely being unreachable from the
-- dashboard. Anyone calling it directly now gets "function does not exist".
--
-- Deliberately left in place:
--   * profile_change_log and its trigger — the history stays readable, and
--     admin/class-teacher edits continue to be recorded.
--   * update_student_profile / can_manage_student_profile — admin and class
--     teacher editing is unaffected.
--   * profiles RLS — students never had an UPDATE policy in the first place
--     (that was the whole reason the RPC existed), so there is nothing to
--     revoke there.

drop function if exists public.update_my_profile(jsonb);


-- Storage: students could upload/replace/delete their own photo. Those three
-- self-service policies go; the admin and class-teacher policies remain, as
-- does the student's ability to SELECT (view) their own photo.
drop policy if exists "student photos insert own" on storage.objects;
drop policy if exists "student photos update own" on storage.objects;
drop policy if exists "student photos delete own" on storage.objects;
