-- Returns the calling student's own rank within their class for a given
-- term, without exposing any classmate's individual scores — RLS on
-- `results` deliberately only lets a student see their own rows, so ranking
-- has to happen server-side via a security-definer function, the same
-- pattern already used by resolve_login_email().
create or replace function public.get_class_rank(p_term_id uuid)
returns table (my_total numeric, my_rank bigint, class_size bigint, class_average numeric)
language plpgsql
security definer
set search_path = public
as $$
declare
  my_class text;
begin
  select class into my_class from public.profiles where id = auth.uid() and role = 'student';
  if my_class is null then
    return;
  end if;

  return query
  with totals as (
    select p.id as student_id, sum(r.total_score) as total
    from public.profiles p
    join public.results r on r.student_id = p.id and r.term_id = p_term_id and r.status = 'published'
    where p.role = 'student' and p.class = my_class
    group by p.id
  ),
  ranked as (
    select student_id, total, rank() over (order by total desc) as rnk
    from totals
  )
  select
    (select total from ranked where student_id = auth.uid()),
    (select rnk from ranked where student_id = auth.uid()),
    (select count(*) from ranked),
    (select round(avg(total), 1) from ranked);
end;
$$;

grant execute on function public.get_class_rank(uuid) to authenticated;
