-- Lets a teacher restrict an exam to a specific open/close window, so
-- students can't access it before or after it's meant to run. Both bounds
-- are optional (null = no restriction on that side). Enforced server-side
-- in the same two functions that already gate CBT access — a teacher's UI
-- hiding a closed exam is a courtesy, not the actual security boundary.
alter table public.exams
  add column available_from timestamptz,
  add column available_until timestamptz,
  add constraint exams_availability_order check (
    available_from is null or available_until is null or available_from < available_until
  );

-- Optional image attached to a question's stem (a diagram, graph, or figure
-- that genuinely can't be typed) — see the storage bucket migration for
-- where these get uploaded to.
alter table public.exam_questions add column image_url text;

-- Postgres won't let CREATE OR REPLACE change a function's return columns
-- (adding image_url), so the old signature has to be dropped first.
drop function if exists public.get_exam_for_taking(uuid);

create function public.get_exam_for_taking(p_exam_id uuid)
returns table (
  exam_id uuid, title text, duration_minutes integer,
  question_id uuid, question_text text, image_url text,
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
  where e.id = p_exam_id and e.status = 'published' and e.class_name = my_class
    and (e.available_from is null or now() >= e.available_from)
    and (e.available_until is null or now() <= e.available_until);
  if exam_row.id is null then
    return;
  end if;

  if exists (select 1 from public.exam_attempts a where a.exam_id = p_exam_id and a.student_id = auth.uid()) then
    return;
  end if;

  return query
    select exam_row.id, exam_row.title, exam_row.duration_minutes,
           q.id, q.question_text, q.image_url, q.option_a, q.option_b, q.option_c, q.option_d, q.sort_order
    from public.exam_questions q
    where q.exam_id = p_exam_id
    order by q.sort_order, q.created_at;
end;
$$;

create or replace function public.submit_exam_attempt(p_exam_id uuid, p_answers jsonb)
returns table (score integer, total_questions integer)
language plpgsql
security definer
set search_path = public
as $$
declare
  my_class text;
  my_student_id uuid := auth.uid();
  exam_row public.exams;
  q record;
  computed_score integer := 0;
  question_count integer := 0;
  chosen text;
  scaled_objective numeric;
begin
  select class into my_class from public.profiles where id = my_student_id and role = 'student';
  if my_class is null then
    raise exception 'Only students can submit exam attempts.';
  end if;

  select * into exam_row from public.exams e
  where e.id = p_exam_id and e.status = 'published' and e.class_name = my_class
    and (e.available_from is null or now() >= e.available_from)
    and (e.available_until is null or now() <= e.available_until);
  if exam_row.id is null then
    raise exception 'Exam not found or not available to you right now.';
  end if;

  if exists (select 1 from public.exam_attempts a where a.exam_id = p_exam_id and a.student_id = my_student_id) then
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
  values (p_exam_id, my_student_id, computed_score, question_count, p_answers);

  if question_count > 0 then
    scaled_objective := round((computed_score::numeric / question_count) * exam_row.objective_max_score, 1);
    insert into public.results (student_id, subject_id, term_id, teacher_id, class_at_entry, objective_score, status)
    values (my_student_id, exam_row.subject_id, exam_row.term_id, exam_row.teacher_id, my_class, scaled_objective, 'submitted')
    on conflict (student_id, subject_id, term_id) do update
      set objective_score = excluded.objective_score,
          status = 'submitted'
      where public.results.status <> 'published';
  end if;

  return query select computed_score, question_count;
end;
$$;
