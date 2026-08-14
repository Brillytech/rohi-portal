-- Fixes a runtime error that made get_my_subject_stats fail on EVERY call,
-- so the report card's per-subject Class Average / Highest / Lowest columns
-- silently rendered as "—" for every student since the day they shipped.
--
-- Cause: the function RETURNS TABLE (subject_id uuid, ...), and a
-- RETURNS TABLE output column is also an in-scope PL/pgSQL variable. The
-- inner IN-subquery selected an UNqualified `subject_id`, which Postgres
-- could read as either that variable or results.subject_id:
--     ERROR 42702: column reference "subject_id" is ambiguous
-- The outer references were already table-qualified (r.subject_id), which
-- is why only the subquery tripped it.
--
-- Fix: alias the subquery's table and qualify the column. Renaming the OUT
-- params would work too, but that changes the response shape the client
-- reads, so qualifying is the smaller, safer change.
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
      select mine.subject_id
      from public.results mine
      where mine.student_id = auth.uid()
        and mine.term_id = p_term_id
        and mine.status = 'published'
    )
  group by r.subject_id;
end;
$$;

grant execute on function public.get_my_subject_stats(uuid) to authenticated;
