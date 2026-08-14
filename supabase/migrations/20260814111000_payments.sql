-- Per-student, per-term payment tracking. REPLACES fee_status, which held
-- the same paid/owing/part_payment idea with no amounts. Both tables would
-- be two sources of truth for "has this student paid" — and the result
-- visibility gate reads one of them — so fee_status is migrated and dropped.

create table public.payments (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.profiles(id) on delete cascade,
  term_id uuid not null references public.terms(id) on delete cascade,
  -- Snapshot of the class at the time of payment. Without it, revenue-by-class
  -- for a past term silently changes when students are promoted — the same
  -- reason results.class_at_entry exists.
  class_at_payment text,
  amount_expected numeric(12,2) not null default 0 check (amount_expected >= 0),
  amount_paid numeric(12,2) not null default 0 check (amount_paid >= 0),
  -- Generated, so it can never contradict the amounts. amount_expected = 0
  -- means "not configured yet" and deliberately does NOT read as paid, so an
  -- unconfigured record leaves the result gate closed rather than open.
  status text generated always as (
    case
      when amount_expected > 0 and amount_paid >= amount_expected then 'paid'
      when amount_paid > 0 then 'partial'
      else 'owing'
    end
  ) stored,
  -- Admin escape hatch: lets a specific student view results for this term
  -- despite not being paid in full.
  override_allowed boolean not null default false,
  note text,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id) on delete set null,
  unique (student_id, term_id)
);

create index payments_term_idx on public.payments (term_id);
create index payments_student_idx on public.payments (student_id);

create or replace function public.set_payments_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger payments_set_updated_at
before update on public.payments
for each row execute function public.set_payments_updated_at();

alter table public.payments enable row level security;

create policy "payments admin full access" on public.payments
  for all using (public.is_admin()) with check (public.is_admin());

-- Students read only their own — needed so the results page can explain why
-- a result is locked instead of just showing nothing. Teachers get no access.
create policy "payments student select own" on public.payments
  for select using (student_id = auth.uid());


-- ---------------------------------------------------------------------------
-- Migrate fee_status -> payments, then drop it
-- ---------------------------------------------------------------------------
-- fee_status carried no amounts, so there is nothing honest to put in
-- amount_expected/amount_paid. A student previously marked 'paid' therefore
-- migrates as override_allowed = true: an admin had explicitly decided they
-- were settled, which is exactly what the override flag means. Amounts stay
-- 0 until an admin enters the real figures.
insert into public.payments (student_id, term_id, class_at_payment, override_allowed, note)
select f.student_id,
       f.term_id,
       p.class,
       (f.status = 'paid'),
       'Migrated from fee_status (status: ' || f.status || '); amounts were not recorded in the old table.'
from public.fee_status f
join public.profiles p on p.id = f.student_id
on conflict (student_id, term_id) do nothing;

drop table public.fee_status;
