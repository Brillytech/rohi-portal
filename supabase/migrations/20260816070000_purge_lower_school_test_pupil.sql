-- Removes the auth account for the throwaway pupil used to verify the
-- lower-school "class teacher takes every subject" flow end to end.
--
-- Deleting public.profiles does not remove auth.users (the admin dashboard
-- says so on its confirm dialog), so the login would otherwise survive.
delete from auth.users
 where email = 'student.26.0059@students.rohi-portal.local'
    or (
      email like 'student.26.00%@students.rohi-portal.local'
      and id not in (select id from public.profiles)
    );

-- Give back the portal number the test consumed.
update public.student_counters
   set last_number = 53
 where year = '26' and last_number > 53;
