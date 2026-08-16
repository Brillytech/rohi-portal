-- Upload hardening (found in the security audit).
--
-- The timetable uploader only checked file size and the browser-supplied MIME
-- type, both of which the client controls. Arbitrary bytes could be stored.
--
-- Storage serves objects back with the content type declared at upload, so a
-- disguised file (SVG bytes declared image/png) renders as a broken image and
-- cannot execute. The real hole is an honestly-declared image/svg+xml: SVG can
-- carry <script>, and the page offers an "Open full size" link that navigates
-- straight to the object, which would run that script on the storage origin.
--
-- allowed_mime_types is enforced by storage itself, so it holds regardless of
-- what the page sends. SVG is deliberately excluded — a timetable is a scan or
-- an export, never a scripted vector.
update storage.buckets
   set allowed_mime_types = array[
         'image/png', 'image/jpeg', 'image/jpg', 'image/webp', 'image/heic', 'application/pdf'
       ],
       file_size_limit = 10485760  -- 10 MB, matching TIMETABLE_MAX_MB in the page
 where id = 'timetables';

-- Passport photos are always re-encoded to JPEG by compressPhoto() before
-- upload (it decodes through a canvas, so a non-image is rejected outright),
-- but pin the bucket down anyway so a direct API call cannot bypass the page.
update storage.buckets
   set allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp'],
       file_size_limit = 5242880   -- 5 MB
 where id = 'student-photos';
