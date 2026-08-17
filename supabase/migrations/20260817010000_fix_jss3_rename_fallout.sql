-- Repairs the fallout from renaming the JSS3 class to "JSS3 Red".
--
-- profiles.class holds a class NAME as free text, not a foreign key, so
-- renaming a row in public.classes does not carry its students with it. The
-- 22 students registered into "JSS3" kept that value while the class itself
-- became "JSS3 Red", leaving them pointing at a class that no longer exists —
-- present on the Students and Payments pages, absent everywhere that joins
-- against classes.
--
-- Nobody is deleted here. The students are simply moved onto the new name.

update public.profiles
   set class = 'JSS3 Red'
 where role = 'student'
   and class = 'JSS3';

-- The renamed row was the old armless JSS3, so it kept arm = null while its
-- sibling JSS3 Blue carries arm = 'Blue'. The arm-aware promotion planner
-- matches JSS2 Red -> JSS3 Red on this column, so a null here would make the
-- class unreachable when promoting.
update public.classes
   set arm = 'Red'
 where name = 'JSS3 Red'
   and arm is null;

-- Any payment or result snapshot still naming the old class should follow it.
-- These columns are deliberately historical, but "JSS3" was never a class the
-- school actually ran under that name, so leaving it would only be confusing.
update public.payments
   set class_at_payment = 'JSS3 Red'
 where class_at_payment = 'JSS3';

update public.results
   set class_at_entry = 'JSS3 Red'
 where class_at_entry = 'JSS3';

update public.attendance
   set class_at_entry = 'JSS3 Red'
 where class_at_entry = 'JSS3';
