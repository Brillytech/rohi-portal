-- Simple per-term fee status (Paid / Owing / Part payment) — admin-managed,
-- not real payment processing, matching the school's actual current need.
create table public.fee_status (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.profiles(id) on delete cascade,
  term_id uuid not null references public.terms(id) on delete cascade,
  status text not null default 'owing' check (status in ('paid', 'owing', 'part_payment')),
  updated_at timestamptz not null default now(),
  unique (student_id, term_id)
);

alter table public.fee_status enable row level security;

create policy "fee_status admin full access" on public.fee_status
  for all using (public.is_admin()) with check (public.is_admin());

create policy "fee_status student select own" on public.fee_status
  for select using (student_id = auth.uid());

-- Affective/psychomotor skill ratings (1-5) plus the class teacher's and
-- principal's written comments — the standard end-of-term assessment
-- section on a Nigerian report card, alongside subject scores. Skill lists
-- are fixed/standard, so they're not admin-configurable, just rated.
create table public.student_term_remarks (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.profiles(id) on delete cascade,
  term_id uuid not null references public.terms(id) on delete cascade,
  affective jsonb not null default '{}',
  psychomotor jsonb not null default '{}',
  teacher_comment text,
  principal_comment text,
  updated_at timestamptz not null default now(),
  unique (student_id, term_id)
);

alter table public.student_term_remarks enable row level security;

create policy "remarks admin full access" on public.student_term_remarks
  for all using (public.is_admin()) with check (public.is_admin());

-- A class teacher can only rate students currently in the one class they're
-- the class teacher of.
create policy "remarks class teacher manage own class students" on public.student_term_remarks
  for all
  using (
    exists (
      select 1 from public.profiles s
      join public.classes c on c.name = s.class
      where s.id = student_term_remarks.student_id and c.class_teacher_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.profiles s
      join public.classes c on c.name = s.class
      where s.id = student_term_remarks.student_id and c.class_teacher_id = auth.uid()
    )
  );

create policy "remarks student select own" on public.student_term_remarks
  for select using (student_id = auth.uid());
