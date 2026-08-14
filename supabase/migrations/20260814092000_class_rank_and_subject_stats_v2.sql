-- Replaces get_class_rank with a richer version distinguishing "class
-- section" (the student's exact class, e.g. JSS2 Red) from "entire class"
-- (the whole grade level across every arm, e.g. all of JSS2) — the report
-- card shows both as separate stats. Also adds highest/lowest average
-- among section classmates. Same privacy shape as before: only the
-- caller's own rank/stats come back, never a classmate's raw scores.
drop function if exists public.get_class_rank(uuid);

create function public.get_class_rank(p_term_id uuid)
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
    join public.results r on r.student_id = p.id and r.term_id = p_term_id and r.status = 'published'
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
    join public.results r on r.student_id = p.id and r.term_id = p_term_id and r.status = 'published'
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

-- Per-subject class average/highest/lowest among section classmates, for
-- just the subjects the caller themself has a published result in. Never
-- exposes an individual classmate's score, only the aggregate.
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
  where p.role = 'student' and p.class = my_class and r.term_id = p_term_id and r.status = 'published'
    and r.subject_id in (
      select subject_id from public.results where student_id = auth.uid() and term_id = p_term_id and status = 'published'
    )
  group by r.subject_id;
end;
$$;

grant execute on function public.get_my_subject_stats(uuid) to authenticated;
