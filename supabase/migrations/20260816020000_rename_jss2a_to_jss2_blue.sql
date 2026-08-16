-- Data fix: "JSS2 A" was the old name for what is now "JSS2 Blue".
--
-- 33 students were registered under the old label, which was never a row in
-- public.classes. Class names are denormalised as text in several tables, so
-- anything holding the stale string has to move together — otherwise the
-- Payments page keeps grouping those students under a class that the Classes
-- page does not know about, which is exactly the ghost row that was showing.
--
-- Audited before writing this: only profiles.class and payments.class_at_payment
-- contain 'JSS2 A' (33 rows each). results.class_at_entry, attendance.class_at_entry,
-- exams.class_name, announcements.audience and class_timetables.class_name all
-- have zero rows for it, so no history is being rewritten.

update public.profiles
   set class = 'JSS2 Blue'
 where role = 'student'
   and class = 'JSS2 A';

update public.payments
   set class_at_payment = 'JSS2 Blue'
 where class_at_payment = 'JSS2 A';


-- While here: JSS2 Red is the only arm-bearing class with a null arm, which
-- would make it invisible to the arm-aware promotion planner in the admin
-- dashboard (it matches JSS1 Red -> JSS2 Red on the arm column). Its sibling
-- JSS2 Blue already carries arm = 'Blue'.
update public.classes
   set arm = 'Red'
 where name = 'JSS2 Red'
   and arm is null;
