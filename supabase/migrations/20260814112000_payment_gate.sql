-- Payment gate on result visibility.
--
-- A student may read their own result for a term only when it is published
-- AND their payment for that term is settled in full (status = 'paid') or an
-- admin has flagged override_allowed. 'partial' does NOT unlock viewing.
--
-- This is enforced in RLS rather than only in the page, because the anon key
-- ships in the page source and the student holds a valid JWT — a UI-only
-- check is bypassable from devtools in about ten seconds.
--
-- It restricts ONLY the student reading their own row. The admin and teacher
-- policies on results are untouched, so both continue to see every result for
-- their classes/subjects regardless of any student's payment state.

drop policy if exists "results student select own published" on public.results;

create policy "results student select own published and paid" on public.results
  for select using (
    student_id = auth.uid()
    and published
    and exists (
      select 1 from public.payments pay
      where pay.student_id = auth.uid()
        and pay.term_id = results.term_id
        and (pay.status = 'paid' or pay.override_allowed)
    )
  );
