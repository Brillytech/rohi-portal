-- Timetables, daily attendance, and per-user settings/notification state.
--
-- Three features that arrived together but stay independent: a class
-- timetable is an uploaded file, attendance is a daily register that feeds
-- the report card's existing days_present field, and user_settings holds the
-- notification preferences plus the "seen" marker the bell counts against.


-- ===========================================================================
-- 1. CLASS TIMETABLES
--
-- The school already produces timetables as a printed/exported document, so
-- this stores the file rather than modelling periods. One live timetable per
-- class: re-uploading replaces it, which is what "update the timetable"
-- means in practice and avoids a pile of stale versions.
-- ===========================================================================
create table public.class_timetables (
  id uuid primary key default gen_random_uuid(),
  class_name text not null unique,
  file_path text not null,
  mime_type text,
  original_name text,
  uploaded_by uuid references public.profiles(id) on delete set null,
  uploaded_at timestamptz not null default now()
);

alter table public.class_timetables enable row level security;

create policy "timetables admin full access" on public.class_timetables
  for all using (public.is_admin()) with check (public.is_admin());

-- The class teacher owns their own class's timetable.
create policy "timetables class teacher manage own class" on public.class_timetables
  for all
  using (
    exists (
      select 1 from public.classes c
      where c.name = class_timetables.class_name and c.class_teacher_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.classes c
      where c.name = class_timetables.class_name and c.class_teacher_id = auth.uid()
    )
  );

-- A student sees their own class's timetable; any teacher can look one up,
-- which is routine (cover lessons, scheduling).
create policy "timetables select for own class or staff" on public.class_timetables
  for select using (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and (p.role = 'teacher' or (p.role = 'student' and p.class = class_timetables.class_name))
    )
  );


-- Storage for the uploaded file itself. Not public — served through signed
-- URLs like student-photos. A timetable is not confidential within the
-- school, so any signed-in user may read; only staff may write.
insert into storage.buckets (id, name, public)
values ('timetables', 'timetables', false)
on conflict (id) do nothing;

create policy "timetables select for authenticated" on storage.objects
  for select using (
    bucket_id = 'timetables' and auth.role() = 'authenticated'
  );

create policy "timetables write for staff" on storage.objects
  for insert with check (
    bucket_id = 'timetables'
    and exists (select 1 from public.profiles p where p.id = auth.uid() and p.role in ('teacher', 'admin'))
  );

create policy "timetables update for staff" on storage.objects
  for update using (
    bucket_id = 'timetables'
    and exists (select 1 from public.profiles p where p.id = auth.uid() and p.role in ('teacher', 'admin'))
  );

create policy "timetables delete for staff" on storage.objects
  for delete using (
    bucket_id = 'timetables'
    and exists (select 1 from public.profiles p where p.id = auth.uid() and p.role in ('teacher', 'admin'))
  );


-- ===========================================================================
-- 2. DAILY ATTENDANCE REGISTER
--
-- One row per student per school day, taken by the class teacher. 'late'
-- still counts as attending for the report card total — it marks punctuality,
-- not absence.
--
-- class_at_entry is denormalised the same way results.class_at_entry is, so a
-- mid-term class change does not rewrite history.
-- ===========================================================================
create table public.attendance (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.profiles(id) on delete cascade,
  term_id uuid not null references public.terms(id) on delete cascade,
  attendance_date date not null,
  status text not null check (status in ('present', 'absent', 'late')),
  class_at_entry text,
  marked_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (student_id, attendance_date)
);

create index attendance_term_date_idx on public.attendance (term_id, attendance_date);
create index attendance_class_date_idx on public.attendance (class_at_entry, attendance_date);
create index attendance_student_term_idx on public.attendance (student_id, term_id);

create trigger attendance_set_updated_at
before update on public.attendance
for each row execute function public.set_results_updated_at();

alter table public.attendance enable row level security;

create policy "attendance admin full access" on public.attendance
  for all using (public.is_admin()) with check (public.is_admin());

-- Mirrors the remarks policy: a class teacher may mark only the students
-- currently in the class they are class teacher of.
create policy "attendance class teacher manage own class students" on public.attendance
  for all
  using (
    exists (
      select 1 from public.profiles s
      join public.classes c on c.name = s.class
      where s.id = attendance.student_id and c.class_teacher_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.profiles s
      join public.classes c on c.name = s.class
      where s.id = attendance.student_id and c.class_teacher_id = auth.uid()
    )
  );

create policy "attendance student select own" on public.attendance
  for select using (student_id = auth.uid());


-- Keep student_term_remarks.days_present in step with the register.
--
-- days_present was typed by hand at term end and is already read by the
-- report card. Rather than change every reader, the register becomes its
-- source of truth: any write to attendance recomputes the term total. The
-- teacher-facing input becomes read-only in the UI to match.
--
-- security definer because the class teacher's own RLS grant on
-- student_term_remarks covers their class only, and this must also hold for
-- an admin correcting a register for a class they do not teach.
create or replace function public.sync_days_present()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_student uuid;
  v_term uuid;
  v_days integer;
begin
  v_student := coalesce(new.student_id, old.student_id);
  v_term := coalesce(new.term_id, old.term_id);

  select count(*) into v_days
    from public.attendance a
   where a.student_id = v_student
     and a.term_id = v_term
     and a.status in ('present', 'late');

  insert into public.student_term_remarks (student_id, term_id, days_present)
  values (v_student, v_term, v_days)
  on conflict (student_id, term_id)
    do update set days_present = excluded.days_present, updated_at = now();

  return null;
end;
$$;

create trigger attendance_sync_days_present
after insert or update or delete on public.attendance
for each row execute function public.sync_days_present();


-- Class register summary for a term: how many days each student attended
-- against how many days the register has actually been taken for the class.
-- days_opened on terms is the school's planned total and can differ, so both
-- numbers are reported rather than one being inferred from the other.
create or replace function public.get_attendance_summary(p_term_id uuid, p_class_name text)
returns table (
  student_id uuid,
  full_name text,
  days_present bigint,
  days_absent bigint,
  days_late bigint,
  days_marked bigint
)
language sql
stable
security definer
set search_path = public
as $$
  select
    p.id,
    p.full_name,
    count(*) filter (where a.status in ('present', 'late')),
    count(*) filter (where a.status = 'absent'),
    count(*) filter (where a.status = 'late'),
    count(a.id)
  from public.profiles p
  left join public.attendance a
    on a.student_id = p.id and a.term_id = p_term_id
  where p.role = 'student'
    and p.class = p_class_name
    and (
      public.is_admin()
      or exists (
        select 1 from public.classes c
        where c.name = p_class_name and c.class_teacher_id = auth.uid()
      )
    )
  group by p.id, p.full_name
  order by p.full_name;
$$;

grant execute on function public.get_attendance_summary(uuid, text) to authenticated;


-- ===========================================================================
-- 3. USER SETTINGS / NOTIFICATION STATE
--
-- The bell is derived rather than fanned out: there is no notifications
-- table, because every event it reports already exists as a row somewhere
-- (announcements, payments) and RLS already decides who may see it. This
-- table holds only the per-user preferences and the "seen" watermark the
-- unread count is measured against.
-- ===========================================================================
create table public.user_settings (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  notify_announcements boolean not null default true,
  notify_payments boolean not null default true,
  notifications_seen_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.user_settings enable row level security;

create policy "user settings manage own" on public.user_settings
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy "user settings admin select" on public.user_settings
  for select using (public.is_admin());

create trigger user_settings_set_updated_at
before update on public.user_settings
for each row execute function public.set_results_updated_at();
