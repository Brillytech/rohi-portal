-- Splits the "exam" portion of a result into two parts, matching how
-- report cards actually get filled out at this school:
--   - objective_score: auto-filled the moment a student finishes a
--     published CBT exam for that subject/term (see submit_exam_attempt
--     below) — this is the one part that genuinely can be automated.
--   - theory_score: always entered manually by the subject teacher, since
--     it's handwritten/essay work a machine can't grade.
-- ca_score (continuous assessment) stays as before, also manual.
-- total_score is still a generated column, now summing all three.

alter table public.exams
  add column objective_max_score numeric not null default 30 check (objective_max_score > 0);

-- Existing test rows had a flat "exam_score" (manually entered, not
-- CBT-linked) — folding those into theory_score on rename is the closest
-- honest mapping; objective_score starts at 0 for them since no CBT was
-- ever tied to those entries.
alter table public.results drop column total_score;
alter table public.results rename column exam_score to theory_score;
alter table public.results add column objective_score numeric not null default 0 check (objective_score >= 0);
alter table public.results add constraint results_score_bounds check (ca_score + objective_score + theory_score <= 100);
alter table public.results add column total_score numeric generated always as (ca_score + objective_score + theory_score) stored;

-- Re-grade + auto-fill the objective score into that subject's result row
-- for this term, scaled to the exam's configured objective_max_score.
-- Preserves any CA/theory marks already entered (only objective_score is
-- touched), and deliberately leaves an already-published result alone — an
-- admin released it on purpose, so a late CBT completion shouldn't quietly
-- change what a student is already seeing.
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
  where e.id = p_exam_id and e.status = 'published' and e.class_name = my_class;
  if exam_row.id is null then
    raise exception 'Exam not found or not available to you.';
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
