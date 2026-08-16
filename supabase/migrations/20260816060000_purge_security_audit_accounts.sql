-- Removes the throwaway accounts created during the security audit.
--
-- Deleting a public.profiles row does NOT remove the underlying auth.users
-- row — the admin dashboard says as much on its confirm dialog — so the audit
-- logins stayed able to authenticate after their profiles were gone. This
-- clears the auth records too.
--
-- Scoped to the audit's own naming (zzaudit* emails and the three throwaway
-- students created against "ZZ Audit" classes). Nothing belonging to a real
-- student, teacher or admin matches.
delete from auth.users
 where email like 'zzaudit%@example.invalid'
    or email in (
      'student.26.0054@students.rohi-portal.local',
      'student.26.0055@students.rohi-portal.local',
      'student.26.0056@students.rohi-portal.local',
      'student.26.0057@students.rohi-portal.local',
      'student.26.0058@students.rohi-portal.local'
    );

-- The audit burned portal numbers 0054-0058; wind the counter back so the
-- next real registration continues from where the school actually left off.
update public.student_counters
   set last_number = 53
 where year = '26' and last_number between 54 and 58;
