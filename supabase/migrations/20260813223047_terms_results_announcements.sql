-- Terms (minimal academic session/term model)
create table public.terms (
  id uuid primary key default gen_random_uuid(),
  session text not null,
  name text not null,
  is_current boolean not null default false,
  created_at timestamptz not null default now()
);

-- Only one term can be "current" at a time
create unique index terms_one_current_idx on public.terms (is_current) where is_current;

alter table public.terms enable row level security;

create policy "terms admin full access" on public.terms
  for all
  using (public.is_admin())
  with check (public.is_admin());

create policy "terms select for authenticated" on public.terms
  for select
  using (auth.role() = 'authenticated');


-- Results
create table public.results (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.profiles(id) on delete cascade,
  subject_id uuid not null references public.subjects(id) on delete cascade,
  term_id uuid not null references public.terms(id) on delete cascade,
  teacher_id uuid references public.profiles(id) on delete set null,
  class_at_entry text,
  ca_score numeric not null default 0 check (ca_score >= 0),
  exam_score numeric not null default 0 check (exam_score >= 0),
  total_score numeric generated always as (ca_score + exam_score) stored,
  status text not null default 'submitted' check (status in ('submitted', 'published')),
  remark text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (student_id, subject_id, term_id),
  check (ca_score + exam_score <= 100)
);

create index results_student_idx on public.results (student_id);
create index results_term_idx on public.results (term_id);
create index results_subject_term_idx on public.results (subject_id, term_id);
create index results_teacher_idx on public.results (teacher_id);

create or replace function public.set_results_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

create trigger results_set_updated_at
before update on public.results
for each row execute function public.set_results_updated_at();

alter table public.results enable row level security;

create policy "results admin full access" on public.results
  for all
  using (public.is_admin())
  with check (public.is_admin());

-- Teachers can insert/update/delete their own results while still in "submitted"
-- status, and only for subjects they're assigned to teach. Once a result is
-- published, this policy no longer matches (status check fails), so only an
-- admin can amend it after that point.
create policy "results teacher manage own submissions" on public.results
  for all
  using (
    teacher_id = auth.uid()
    and status = 'submitted'
    and exists (
      select 1 from public.subject_teachers st
      where st.subject_id = results.subject_id and st.teacher_id = auth.uid()
    )
  )
  with check (
    teacher_id = auth.uid()
    and status = 'submitted'
    and exists (
      select 1 from public.subject_teachers st
      where st.subject_id = results.subject_id and st.teacher_id = auth.uid()
    )
  );

-- Teachers can still see their own results after publishing (read-only by then)
create policy "results teacher select own" on public.results
  for select
  using (teacher_id = auth.uid());

-- Students can only see their own results once published
create policy "results student select own published" on public.results
  for select
  using (student_id = auth.uid() and status = 'published');


-- Announcements
create table public.announcements (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  body text not null,
  audience text not null default 'all',
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

create index announcements_created_at_idx on public.announcements (created_at desc);

alter table public.announcements enable row level security;

create policy "announcements admin full access" on public.announcements
  for all
  using (public.is_admin())
  with check (public.is_admin());

-- audience is one of: 'all', 'teachers', 'students', or an exact class name
-- (matching classes.name / profiles.class, same free-text convention used
-- elsewhere in this schema).
create policy "announcements select for audience" on public.announcements
  for select
  using (
    audience = 'all'
    or (audience = 'teachers' and exists (
      select 1 from public.profiles p where p.id = auth.uid() and p.role = 'teacher'
    ))
    or (audience = 'students' and exists (
      select 1 from public.profiles p where p.id = auth.uid() and p.role = 'student'
    ))
    or exists (
      select 1 from public.profiles p
      where p.id = auth.uid() and p.role = 'student' and p.class = announcements.audience
    )
  );
