-- Removes the throwaway account used to verify that a CSV import can create a
-- new arm class and place a student in it.
--
-- Deleting public.profiles does not remove auth.users, so the login would
-- otherwise survive its profile.
delete from auth.users
 where email like 'student.26.%@students.rohi-portal.local'
   and id not in (select id from public.profiles);

-- Give back the portal number the test consumed, so the next real
-- registration continues from RHS/26/0054 rather than skipping it.
update public.student_counters
   set last_number = 53
 where year = '26' and last_number > 53;
