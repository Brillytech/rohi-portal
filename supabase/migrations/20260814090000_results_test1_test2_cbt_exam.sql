-- Restructures scoring to match the school's actual report card format:
-- Test 1 (15) + Test 2 (15) + CBT (40, auto-filled from a CBT exam) +
-- Exam (30, manual/theory) = 100. This replaces the earlier
-- CA/Objective/Theory model with the real 4-part breakdown the school uses.
alter table public.results drop column total_score; -- generated, must drop before restructuring source columns

alter table public.results rename column ca_score to test1_score;
alter table public.results rename column objective_score to cbt_score;
alter table public.results rename column theory_score to exam_score;
alter table public.results add column test2_score numeric not null default 0 check (test2_score >= 0);

alter table public.results drop constraint if exists results_score_bounds;
alter table public.results add constraint results_score_bounds
  check (test1_score + test2_score + cbt_score + exam_score <= 100);

alter table public.results add column total_score numeric
  generated always as (test1_score + test2_score + cbt_score + exam_score) stored;

-- Matches the reference report's CBT column, out of 40 by default.
alter table public.exams rename column objective_max_score to cbt_max_score;
alter table public.exams alter column cbt_max_score set default 40;

-- Re-point the auto-fill at cbt_score instead of objective_score. Same
-- signature, same safety behavior (won't touch an already-published
-- result) — only the target column and the exam column name change.
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
  scaled_cbt numeric;
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
    scaled_cbt := round((computed_score::numeric / question_count) * exam_row.cbt_max_score, 1);
    insert into public.results (student_id, subject_id, term_id, teacher_id, class_at_entry, cbt_score, status)
    values (my_student_id, exam_row.subject_id, exam_row.term_id, exam_row.teacher_id, my_class, scaled_cbt, 'submitted')
    on conflict (student_id, subject_id, term_id) do update
      set cbt_score = excluded.cbt_score,
          status = 'submitted'
      where public.results.status <> 'published';
  end if;

  return query select computed_score, question_count;
end;
$$;
