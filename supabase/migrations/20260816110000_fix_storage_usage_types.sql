-- sum() over bigint returns numeric in Postgres, not bigint, so the declared
-- RETURNS TABLE type did not match what the query produced and every call
-- failed with "structure of query does not match function result type".
-- Cast the aggregate explicitly.
create or replace function public.get_storage_usage()
returns table (
  bucket text,
  object_count bigint,
  total_bytes bigint,
  largest_bytes bigint,
  is_public boolean
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
    b.id::text,
    count(o.id)::bigint,
    coalesce(sum((o.metadata->>'size')::bigint), 0)::bigint,
    coalesce(max((o.metadata->>'size')::bigint), 0)::bigint,
    b.public
  from storage.buckets b
  left join storage.objects o on o.bucket_id = b.id
  group by b.id, b.public
  order by 3 desc;
end;
$$;

grant execute on function public.get_storage_usage() to authenticated;
