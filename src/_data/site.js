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

// ---------------------------------------------------------------------------
// Canonical site identity. Every absolute URL on the public site — og:url,
// canonical, sitemap entries, the robots.txt Sitemap line and the schema.org
// block — derives from `url`, so changing domain is a one-line edit here.
// ---------------------------------------------------------------------------
const url = "https://rohischools.com";

const school = {
  name: "Rohi Group of Schools",
  shortName: "Rohi Schools",
  legalName: "Rohi Group of Schools",
  tagline: "Raising principled leaders through sound education.",
  description:
    "Rohi Group of Schools, Abeokuta — a Kindergarten to Senior Secondary school in Ogun State " +
    "offering strong academics, character formation and practical skills across two campuses.",
  founded: "2007",
  street: "B4/9 Federal Housing Estate, Olomore",
  city: "Abeokuta",
  region: "Ogun State",
  country: "NG",
  phone: ["+2348032408415", "+2347031362416"],
  email: "rohicollegeogunradio@gmail.com",
  facebook: "https://www.facebook.com/profile.php?id=100063597926687",
  whatsapp: "https://wa.me/2347031362416",
  ogImage: "/img/og-image.png",
};

module.exports = { supabase, SUPABASE_URL, SUPABASE_ANON_KEY, publicMediaUrl, url, school };
