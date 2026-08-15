// Build-time fetch of the homepage gallery, grouped into the existing albums.
const { supabase, publicMediaUrl } = require("./site.js");

const ALBUMS = [
  { key: "class-projects", label: "Class Projects" },
  { key: "cultural-day", label: "Cultural Day" },
  { key: "daily-moments", label: "Daily Moments" },
];

module.exports = async function () {
  const { data, error } = await supabase
    .from("site_gallery")
    .select("*")
    .order("sort_order", { ascending: true })
    .order("created_at", { ascending: true });

  if (error) {
    console.warn("[gallery] could not load from Supabase:", error.message);
    return { albums: ALBUMS.map((a) => ({ ...a, images: [] })), total: 0 };
  }

  const rows = data || [];
  return {
    albums: ALBUMS.map((a) => ({
      ...a,
      images: rows
        .filter((r) => r.album === a.key)
        .map((r) => ({
          thumb: publicMediaUrl(r.thumb_path),
          full: publicMediaUrl(r.full_path),
          alt: r.alt_text || a.label,
        })),
    })),
    total: rows.length,
  };
};
