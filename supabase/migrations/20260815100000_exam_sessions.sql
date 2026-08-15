-- Anchors the exam clock on the server.
--
-- The countdown previously lived only in the browser's localStorage, which
-- left three ways to get the full time back: open the exam and close it
-- before touching anything (the deadline was only written once an answer was
-- picked), clear site data, or simply reopen on another phone.
--
-- The moment a student first opens an exam, the start is recorded here. From
-- then on the remaining time is computed from that row, so the clock keeps
-- counting no matter what the student does to their browser or device.

create table public.exam_sessions (
  id uuid primary key default gen_random_uuid(),
  exam_id uuid not null references public.exams(id) on delete cascade,
  student_id uuid not null references public.profiles(id) on delete cascade,
  started_at timestamptz not null default now(),
  unique (exam_id, student_id)
);

create index exam_sessions_student_idx on public.exam_sessions (student_id);

alter table public.exam_sessions enable row level security;

create policy "exam_sessions admin full access" on public.exam_sessions
  for all using (public.is_admin()) with check (public.is_admin());

create policy "exam_sessions student select own" on public.exam_sessions
  for select using (student_id = auth.uid());

-- A teacher can see when their own exam was started, for invigilation.
create policy "exam_sessions teacher select own exam" on public.exam_sessions
  for select using (
    exists (select 1 from public.exams e where e.id = exam_sessions.exam_id and e.teacher_id = auth.uid())
  );

-- Rows are written only by the security-definer RPC below, so there is
-- deliberately no INSERT/UPDATE policy: a student cannot reset their own
-- start time by calling the table directly.


-- Idempotent: the first call records the start, every later call returns the
-- time left against that same start. Returns seconds rather than a timestamp
-- so a wrong clock on the student's phone cannot change how long they get.
create or replace function public.start_exam_session(p_exam_id uuid)
returns table (seconds_remaining integer, duration_minutes integer, started_at timestamptz)
language plpgsql
security definer
set search_path = public
as $$
declare
  my_class text;
  exam_row public.exams;
  s_started timestamptz;
begin
  select p.class into my_class from public.profiles p where p.id = auth.uid() and p.role = 'student';
  if my_class is null then
    raise exception 'Only students can start an exam.';
  end if;

  select * into exam_row from public.exams e
  where e.id = p_exam_id
    and e.status = 'published'
    and e.class_name = my_class
    and (e.available_from is null or now() >= e.available_from)
    and (e.available_until is null or now() <= e.available_until);
  if exam_row.id is null then
    raise exception 'Exam not found or not available to you right now.';
  end if;

  insert into public.exam_sessions (exam_id, student_id)
  values (p_exam_id, auth.uid())
  on conflict (exam_id, student_id) do nothing;

  select es.started_at into s_started
  from public.exam_sessions es
  where es.exam_id = p_exam_id and es.student_id = auth.uid();

  return query
  select
    greatest(0, ceil(extract(epoch from
      (s_started + make_interval(mins => exam_row.duration_minutes)) - now())))::integer,
    exam_row.duration_minutes,
    s_started;
end;
$$;

grant execute on function public.start_exam_session(uuid) to authenticated;
