-- Students have no RLS access to other profiles (correctly — that's how
-- portal_number-as-password stays private), but the result sheet needs to
-- show which teacher owns each subject score. A teacher's name isn't
-- sensitive (it's already shown in admin/teacher UIs), so this returns
-- only id + full_name for the given teacher ids — nothing else from their
-- profile row.
create or replace function public.get_teacher_names(p_teacher_ids uuid[])
returns table (id uuid, full_name text)
language sql
security definer
set search_path = public
stable
as $$
  select id, full_name from public.profiles where id = any(p_teacher_ids) and role = 'teacher';
$$;

grant execute on function public.get_teacher_names(uuid[]) to authenticated;
