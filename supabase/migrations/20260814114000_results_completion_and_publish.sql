-- Replaces the per-result approval queue with completion tracking plus a
-- single publish action scoped to a class/term.

-- There is no class->subject mapping table in use (subject_assignments
-- exists but is empty), so "subjects offered" is derived from the class's
-- curriculum category. Senior Secondary spans four category variants and a
-- student takes a subset of them, so for SSS this returns the full senior
-- catalogue — the admin UI labels it as a curriculum total for that reason.
create or replace function public.subject_categories_for_level(p_level text)
returns text[]
language sql
stable
set search_path = public
as $$
  select case
    when p_level ilike 'Nursery%' then array['Nursery']
    when p_level ilike 'Kindergarten%' or p_level ilike 'KG%' then array['Kindergarten']
    when p_level ilike 'Primary%' then array['Primary']
    when p_level ilike 'JSS%' then array['Junior Secondary']
    when p_level ilike 'SS%' then
      coalesce((select array_agg(distinct s.category)
                from public.subjects s
                where s.category like 'Senior Secondary%'), array[]::text[])
    else array[]::text[]
  end;
$$;


-- One row per class for the selected term: how much of the marking is in,
-- how much is already visible to students, and how many students would be
-- blocked by the payment gate if results were published right now.
create or replace function public.get_results_completion(p_term_id uuid)
returns table (
  class_name text,
  subjects_expected bigint,
  subjects_entered bigint,
  subjects_published bigint,
  results_total bigint,
  results_unpublished bigint,
  students_total bigint,
  students_gated bigint
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Admins only.';
  end if;

  return query
  select
    c.name,
    (select count(*) from public.subjects s
      where s.category = any (public.subject_categories_for_level(c.level_key))),
    (select count(distinct r.subject_id) from public.results r
      where r.term_id = p_term_id and r.class_at_entry = c.name),
    (select count(distinct r.subject_id) from public.results r
      where r.term_id = p_term_id and r.class_at_entry = c.name and r.published),
    (select count(*) from public.results r
      where r.term_id = p_term_id and r.class_at_entry = c.name),
    (select count(*) from public.results r
      where r.term_id = p_term_id and r.class_at_entry = c.name and not r.published),
    (select count(*) from public.profiles p
      where p.role = 'student' and p.class = c.name),
    (select count(*) from public.profiles p
      where p.role = 'student' and p.class = c.name
        and not exists (
          select 1 from public.payments pay
          where pay.student_id = p.id and pay.term_id = p_term_id
            and (pay.status = 'paid' or pay.override_allowed)
        ))
  from public.classes c
  order by c.name;
end;
$$;

grant execute on function public.get_results_completion(uuid) to authenticated;


-- Flips every result for one class/term to published in a single action.
-- Returns how many rows changed so the UI can report it honestly.
create or replace function public.publish_results_for_class(p_term_id uuid, p_class_name text)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  affected integer;
begin
  if not public.is_admin() then
    raise exception 'Admins only.';
  end if;

  update public.results
     set published = true
   where term_id = p_term_id
     and class_at_entry = p_class_name
     and not published;

  get diagnostics affected = row_count;
  return affected;
end;
$$;

grant execute on function public.publish_results_for_class(uuid, text) to authenticated;


create or replace function public.unpublish_results_for_class(p_term_id uuid, p_class_name text)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  affected integer;
begin
  if not public.is_admin() then
    raise exception 'Admins only.';
  end if;

  update public.results
     set published = false
   where term_id = p_term_id
     and class_at_entry = p_class_name
     and published;

  get diagnostics affected = row_count;
  return affected;
end;
$$;

grant execute on function public.unpublish_results_for_class(uuid, text) to authenticated;
