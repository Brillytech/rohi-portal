// Shared Supabase client + constants for build-time data fetching.
//
// The anon key is public by design (it is already in every portal page) and
// RLS is what actually protects the data: only published, non-future
// announcements are readable without a session.
const { createClient } = require("@supabase/supabase-js");

const SUPABASE_URL = "https://qxlskkxtvucebacqdivi.supabase.co";
const SUPABASE_ANON_KEY =
  "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InF4bHNra3h0dnVjZWJhY3FkaXZpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQyMzcwNDQsImV4cCI6MjA5OTgxMzA0NH0.9yO82WLR9SzMmTv8GPlb2C4oDALqpdAm6tGvys-2gX0";

const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

function publicMediaUrl(path) {
  if (!path) return null;
  // Posts imported from the old Netlify CMS still point at files in /img/,
  // which Eleventy passes through. Anything else is a site-media object key.
  if (path.startsWith("/") || path.startsWith("http")) return path;
  return `${SUPABASE_URL}/storage/v1/object/public/site-media/${path}`;
}

module.exports = { supabase, SUPABASE_URL, SUPABASE_ANON_KEY, publicMediaUrl };
