-- Removes the per-result admin review step.
--
-- results.status only ever held 'submitted' | 'published', which is exactly
-- a boolean. It is REPLACED by `published` rather than kept alongside one:
-- two sources of truth for "can the student see this" would inevitably
-- drift, and the payment gate reads this flag.
--
-- A teacher's submission now writes straight to results with
-- published = false. Nothing is "awaiting approval"; publishing is a
-- separate bulk action an admin takes per class/term.

alter table public.results add column published boolean not null default false;
update public.results set published = (status = 'published');

-- Both policies reference status, so they have to go before the column can.
drop policy if exists "results teacher manage own submissions" on public.results;
drop policy if exists "results student select own published" on public.results;

alter table public.results drop column status;

create index if not exists results_term_published_idx on public.results (term_id, published);

-- Teachers keep full control of their own rows until the moment they are
-- published, then the row locks to them (admin can still amend).
create policy "results teacher manage own unpublished" on public.results
  for all
  using (
    teacher_id = auth.uid()
    and not published
    and exists (
      select 1 from public.subject_teachers st
      where st.subject_id = results.subject_id and st.teacher_id = auth.uid()
    )
  )
  with check (
    teacher_id = auth.uid()
    and not published
    and exists (
      select 1 from public.subject_teachers st
      where st.subject_id = results.subject_id and st.teacher_id = auth.uid()
    )
  );

-- Deliberately the plain version — the payment-gate migration replaces this
-- policy with the fee-aware one once the payments table exists.
create policy "results student select own published" on public.results
  for select using (student_id = auth.uid() and published);


-- ---------------------------------------------------------------------------
-- Functions that filtered on status = 'published'
-- ---------------------------------------------------------------------------

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
    insert into public.results (student_id, subject_id, term_id, teacher_id, class_at_entry, cbt_score, published)
    values (my_student_id, exam_row.subject_id, exam_row.term_id, exam_row.teacher_id, my_class, scaled_cbt, false)
    on conflict (student_id, subject_id, term_id) do update
      set cbt_score = excluded.cbt_score
      where not public.results.published;
  end if;

  return query select computed_score, question_count;
end;
$$;


create or replace function public.get_class_rank(p_term_id uuid)
returns table (
  my_total numeric,
  my_average numeric,
  my_rank bigint,
  class_size bigint,
  class_average numeric,
  highest_average numeric,
  lowest_average numeric,
  position_entire bigint,
  class_size_entire bigint
)
language plpgsql
security definer
set search_path = public
as $$
declare
  my_class text;
  my_level text;
begin
  select p.class into my_class from public.profiles p where p.id = auth.uid() and p.role = 'student';
  if my_class is null then
    return;
  end if;

  select c.level_key into my_level from public.classes c where c.name = my_class limit 1;

  return query
  with section_totals as (
    select p.id as student_id, sum(r.total_score) as total, avg(r.total_score) as average
    from public.profiles p
    join public.results r on r.student_id = p.id and r.term_id = p_term_id and r.published
    where p.role = 'student' and p.class = my_class
    group by p.id
  ),
  section_ranked as (
    select student_id, total, average, rank() over (order by total desc) as rnk
    from section_totals
  ),
  entire_totals as (
    select p.id as student_id, sum(r.total_score) as total
    from public.profiles p
    join public.classes c on c.name = p.class
    join public.results r on r.student_id = p.id and r.term_id = p_term_id and r.published
    where p.role = 'student' and c.level_key = my_level
    group by p.id
  ),
  entire_ranked as (
    select student_id, total, rank() over (order by total desc) as rnk
    from entire_totals
  )
  select
    (select total from section_ranked where student_id = auth.uid()),
    (select round(average, 2) from section_ranked where student_id = auth.uid()),
    (select rnk from section_ranked where student_id = auth.uid()),
    (select count(*) from section_ranked),
    (select round(avg(average), 2) from section_ranked),
    (select round(max(average), 2) from section_ranked),
    (select round(min(average), 2) from section_ranked),
    (select rnk from entire_ranked where student_id = auth.uid()),
    (select count(*) from entire_ranked);
end;
$$;

grant execute on function public.get_class_rank(uuid) to authenticated;


create or replace function public.get_my_subject_stats(p_term_id uuid)
returns table (subject_id uuid, class_average numeric, highest_in_class numeric, lowest_in_class numeric)
language plpgsql
security definer
set search_path = public
as $$
declare
  my_class text;
begin
  select p.class into my_class from public.profiles p where p.id = auth.uid() and p.role = 'student';
  if my_class is null then
    return;
  end if;

  return query
  select r.subject_id,
         round(avg(r.total_score), 2) as class_average,
         max(r.total_score) as highest_in_class,
         min(r.total_score) as lowest_in_class
  from public.results r
  join public.profiles p on p.id = r.student_id
  where p.role = 'student' and p.class = my_class and r.term_id = p_term_id and r.published
    and r.subject_id in (
      select mine.subject_id
      from public.results mine
      where mine.student_id = auth.uid() and mine.term_id = p_term_id and mine.published
    )
  group by r.subject_id;
end;
$$;

grant execute on function public.get_my_subject_stats(uuid) to authenticated;
