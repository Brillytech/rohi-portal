-- Students may edit their own age (date of birth), gender and photo.
--
-- Deliberately NO student UPDATE policy is added to profiles. RLS is
-- row-level, not column-level: `for update using (id = auth.uid())` would
-- let a student PATCH their own row and set role = 'admin', or change class,
-- approved, or portal_number. Column-level GRANTs can't help either, because
-- admins and students share the `authenticated` Postgres role.
--
-- Instead the only student write path is the security-definer RPC below,
-- which touches exactly three columns on exactly the caller's own row.
-- Admin keeps its existing broad "admins update all profiles" policy.

create table public.profile_change_log (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.profiles(id) on delete cascade,
  changed_by uuid references public.profiles(id) on delete set null,
  field text not null,
  old_value text,
  new_value text,
  changed_at timestamptz not null default now()
);

create index profile_change_log_student_idx on public.profile_change_log (student_id, changed_at desc);

alter table public.profile_change_log enable row level security;

create policy "profile log admin select" on public.profile_change_log
  for select using (public.is_admin());

create policy "profile log student select own" on public.profile_change_log
  for select using (student_id = auth.uid());

-- No INSERT/UPDATE/DELETE policy for anyone: rows are written only by the
-- security-definer trigger below, which makes the log append-only and
-- impossible to doctor from either dashboard.


-- Logging lives in a trigger rather than in the RPC so that it also captures
-- admin overrides — every write path is covered and none can skip it.
create or replace function public.log_profile_changes()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.gender is distinct from old.gender then
    insert into public.profile_change_log (student_id, changed_by, field, old_value, new_value)
    values (new.id, auth.uid(), 'gender', old.gender, new.gender);
  end if;

  if new.date_of_birth is distinct from old.date_of_birth then
    insert into public.profile_change_log (student_id, changed_by, field, old_value, new_value)
    values (new.id, auth.uid(), 'date_of_birth', old.date_of_birth::text, new.date_of_birth::text);
  end if;

  if new.photo_path is distinct from old.photo_path then
    insert into public.profile_change_log (student_id, changed_by, field, old_value, new_value)
    values (new.id, auth.uid(), 'photo_path', old.photo_path, new.photo_path);
  end if;

  return new;
end;
$$;

create trigger profiles_log_tracked_changes
after update on public.profiles
for each row execute function public.log_profile_changes();


-- Keys absent from p_changes are left untouched; a key present with null
-- clears that field. This lets a student remove their photo without the call
-- also wiping their gender.
create or replace function public.update_my_profile(p_changes jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  me uuid := auth.uid();
  new_gender text;
begin
  if not exists (select 1 from public.profiles where id = me and role = 'student') then
    raise exception 'Only a student can update their own profile.';
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
   where id = me;
end;
$$;

grant execute on function public.update_my_profile(jsonb) to authenticated;


-- ---------------------------------------------------------------------------
-- Storage: let a student manage their own photo
-- ---------------------------------------------------------------------------
-- Files live at "{student_id}/filename", so the owning student is read
-- straight out of the path. upload(..., { upsert: true }) issues an UPDATE
-- when the object already exists, so replacing a photo needs an UPDATE policy
-- as well as INSERT — including for admin, which had none, meaning admin
-- photo replacement was silently failing.

create policy "student photos insert own" on storage.objects
  for insert with check (
    bucket_id = 'student-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "student photos update own" on storage.objects
  for update
  using (
    bucket_id = 'student-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'student-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "student photos delete own" on storage.objects
  for delete using (
    bucket_id = 'student-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "student photos update for admin" on storage.objects
  for update
  using (
    bucket_id = 'student-photos'
    and exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin')
  )
  with check (
    bucket_id = 'student-photos'
    and exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin')
  );
