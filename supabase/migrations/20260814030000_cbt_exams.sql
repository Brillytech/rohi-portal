-- Minimal CBT (computer-based test) system: a teacher builds a
-- multiple-choice exam for one of their subjects + a class + a term, then
-- publishes it; students in that class take it once and get an
-- auto-graded score.
--
-- Security shape: exam_questions.correct_option must never reach a
-- student's browser (it's the answer key), and a score must never be
-- trusted from the client (a student could just submit a fabricated
-- score). So students never SELECT exam_questions directly — RLS grants
-- them no policy on it at all — and instead go through two
-- security-definer functions: one that hands back questions with the
-- answer key stripped, and one that grades server-side from the real
-- correct_option values and writes the attempt itself. There is
-- deliberately no client-facing INSERT policy for students on
-- exam_attempts — the grading function is the only path that can create a
-- row, since it runs with elevated privileges.

create table public.exams (
  id uuid primary key default gen_random_uuid(),
  subject_id uuid not null references public.subjects(id) on delete cascade,
  term_id uuid not null references public.terms(id) on delete cascade,
  class_name text not null,
  teacher_id uuid not null references public.profiles(id) on delete cascade,
  title text not null,
  duration_minutes integer not null default 20 check (duration_minutes > 0),
  status text not null default 'draft' check (status in ('draft', 'published')),
  created_at timestamptz not null default now()
);

create table public.exam_questions (
  id uuid primary key default gen_random_uuid(),
  exam_id uuid not null references public.exams(id) on delete cascade,
  question_text text not null,
  option_a text not null,
  option_b text not null,
  option_c text not null,
  option_d text not null,
  correct_option text not null check (correct_option in ('a', 'b', 'c', 'd')),
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);

create table public.exam_attempts (
  id uuid primary key default gen_random_uuid(),
  exam_id uuid not null references public.exams(id) on delete cascade,
  student_id uuid not null references public.profiles(id) on delete cascade,
  score integer not null,
  total_questions integer not null,
  answers jsonb not null default '{}',
  submitted_at timestamptz not null default now(),
  unique (exam_id, student_id)
);

create index exams_teacher_idx on public.exams (teacher_id);
create index exams_class_status_idx on public.exams (class_name, status);
create index exam_questions_exam_idx on public.exam_questions (exam_id);
create index exam_attempts_exam_idx on public.exam_attempts (exam_id);
create index exam_attempts_student_idx on public.exam_attempts (student_id);

alter table public.exams enable row level security;
alter table public.exam_questions enable row level security;
alter table public.exam_attempts enable row level security;

-- exams
create policy "exams admin full access" on public.exams
  for all using (public.is_admin()) with check (public.is_admin());

create policy "exams teacher manage own" on public.exams
  for all using (teacher_id = auth.uid()) with check (teacher_id = auth.uid());

create policy "exams student select published for own class" on public.exams
  for select using (
    status = 'published'
    and exists (
      select 1 from public.profiles p
      where p.id = auth.uid() and p.role = 'student' and p.class = exams.class_name
    )
  );

-- exam_questions: admin + owning teacher only. No student policy at all —
-- students only ever reach questions via get_exam_for_taking().
create policy "exam_questions admin full access" on public.exam_questions
  for all using (public.is_admin()) with check (public.is_admin());

create policy "exam_questions teacher manage own exam" on public.exam_questions
  for all using (
    exists (select 1 from public.exams e where e.id = exam_questions.exam_id and e.teacher_id = auth.uid())
  )
  with check (
    exists (select 1 from public.exams e where e.id = exam_questions.exam_id and e.teacher_id = auth.uid())
  );

-- exam_attempts: admin full access; teacher read-only on their own exams'
-- attempts; student read-only on their own. No INSERT policy for students
-- — submit_exam_attempt() is the only path that can create a row.
create policy "exam_attempts admin full access" on public.exam_attempts
  for all using (public.is_admin()) with check (public.is_admin());

create policy "exam_attempts teacher select own exam" on public.exam_attempts
  for select using (
    exists (select 1 from public.exams e where e.id = exam_attempts.exam_id and e.teacher_id = auth.uid())
  );

create policy "exam_attempts student select own" on public.exam_attempts
  for select using (student_id = auth.uid());

-- Hands a student the questions for an exam they're eligible to take,
-- with the answer key stripped, and only if they haven't already
-- attempted it.
create or replace function public.get_exam_for_taking(p_exam_id uuid)
returns table (
  exam_id uuid, title text, duration_minutes integer,
  question_id uuid, question_text text,
  option_a text, option_b text, option_c text, option_d text, sort_order integer
)
language plpgsql
security definer
set search_path = public
as $$
declare
  my_class text;
  exam_row public.exams;
begin
  select class into my_class from public.profiles where id = auth.uid() and role = 'student';
  if my_class is null then
    return;
  end if;

  select * into exam_row from public.exams e
  where e.id = p_exam_id and e.status = 'published' and e.class_name = my_class;
  if exam_row.id is null then
    return;
  end if;

  if exists (select 1 from public.exam_attempts a where a.exam_id = p_exam_id and a.student_id = auth.uid()) then
    return;
  end if;

  return query
    select exam_row.id, exam_row.title, exam_row.duration_minutes,
           q.id, q.question_text, q.option_a, q.option_b, q.option_c, q.option_d, q.sort_order
    from public.exam_questions q
    where q.exam_id = p_exam_id
    order by q.sort_order, q.created_at;
end;
$$;

grant execute on function public.get_exam_for_taking(uuid) to authenticated;

-- Grades an attempt server-side against the real correct_option values and
-- records it. Raises if the exam isn't available to the caller or they've
-- already attempted it — this is the sole path that can write a row into
-- exam_attempts for a student, so a client can never fabricate a score.
create or replace function public.submit_exam_attempt(p_exam_id uuid, p_answers jsonb)
returns table (score integer, total_questions integer)
language plpgsql
security definer
set search_path = public
as $$
declare
  my_class text;
  exam_row public.exams;
  q record;
  computed_score integer := 0;
  question_count integer := 0;
  chosen text;
begin
  select class into my_class from public.profiles where id = auth.uid() and role = 'student';
  if my_class is null then
    raise exception 'Only students can submit exam attempts.';
  end if;

  select * into exam_row from public.exams e
  where e.id = p_exam_id and e.status = 'published' and e.class_name = my_class;
  if exam_row.id is null then
    raise exception 'Exam not found or not available to you.';
  end if;

  if exists (select 1 from public.exam_attempts a where a.exam_id = p_exam_id and a.student_id = auth.uid()) then
    raise exception 'You have already submitted this exam.';
  end if;

  for q in select * from public.exam_questions where exam_id = p_exam_id loop
    question_count := question_count + 1;
    chosen := p_answers ->> q.id::text;
    if chosen is not null and lower(chosen) = q.correct_option then
      computed_score := computed_score + 1;
    end if;
  end loop;

  insert into public.exam_attempts (exam_id, student_id, score, total_questions, answers)
  values (p_exam_id, auth.uid(), computed_score, question_count, p_answers);

  return query select computed_score, question_count;
end;
$$;

grant execute on function public.submit_exam_attempt(uuid, jsonb) to authenticated;
