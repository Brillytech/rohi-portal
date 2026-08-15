-- Lets a class teacher maintain the profile details (gender, date of birth,
-- passport photo) of students in the class they are the class teacher of —
-- in practice they are the ones who actually collect this from the child.
--
-- Same reasoning as update_my_profile: profiles is NOT given a broader
-- UPDATE policy, because RLS is row-level and any such policy would also let
-- a teacher rewrite a student's role, class or portal number. The only new
-- write path is this security-definer RPC, restricted to three columns and
-- to students the caller is actually responsible for.

create or replace function public.can_manage_student_profile(p_student_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    public.is_admin()
    or exists (
      select 1
      from public.profiles s
      join public.classes c on c.name = s.class
      where s.id = p_student_id
        and s.role = 'student'
        and c.class_teacher_id = auth.uid()
    );
$$;

grant execute on function public.can_manage_student_profile(uuid) to authenticated;


-- Keys absent from p_changes are left untouched; a key present with null
-- clears that field.
create or replace function public.update_student_profile(p_student_id uuid, p_changes jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  new_gender text;
begin
  if not public.can_manage_student_profile(p_student_id) then
    raise exception 'You can only edit students in the class you are the class teacher of.';
  end if;

  if p_changes ? 'gender' then
    new_gender := nullif(p_changes ->> 'gender', '');
    if new_gender is not null and new_gender not in ('M', 'F') then
      raise exception 'Gender must be M or F.';
    end if;
  end if;

  update public.profiles
     set gender = case when p_changes ? 'gender'
                       then nullif(p_changes ->> 'gender', '') else gender end,
         date_of_birth = case when p_changes ? 'date_of_birth'
                              then (nullif(p_changes ->> 'date_of_birth', ''))::date else date_of_birth end,
         photo_path = case when p_changes ? 'photo_path'
                           then nullif(p_changes ->> 'photo_path', '') else photo_path end
   where id = p_student_id
     and role = 'student';
end;
$$;

grant execute on function public.update_student_profile(uuid, jsonb) to authenticated;

-- The existing profiles_log_tracked_changes trigger already records who
-- changed what, so teacher edits land in profile_change_log automatically
-- alongside the student's own edits and admin overrides.


-- ---------------------------------------------------------------------------
-- Storage: a class teacher may also replace/remove that student's photo
-- ---------------------------------------------------------------------------
-- Objects live at "{student_id}/photo.jpg", so the owning student is the
-- first path segment. upsert:true issues an UPDATE when the object already
-- exists, so replacing needs INSERT *and* UPDATE.

create policy "student photos insert by class teacher" on storage.objects
  for insert with check (
    bucket_id = 'student-photos'
    and public.can_manage_student_profile(((storage.foldername(name))[1])::uuid)
  );

create policy "student photos update by class teacher" on storage.objects
  for update
  using (
    bucket_id = 'student-photos'
    and public.can_manage_student_profile(((storage.foldername(name))[1])::uuid)
  )
  with check (
    bucket_id = 'student-photos'
    and public.can_manage_student_profile(((storage.foldername(name))[1])::uuid)
  );

create policy "student photos delete by class teacher" on storage.objects
  for delete using (
    bucket_id = 'student-photos'
    and public.can_manage_student_profile(((storage.foldername(name))[1])::uuid)
  );
