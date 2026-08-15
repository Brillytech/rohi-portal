// Build-time fetch of published public announcements.
//
// Static output keeps /news/ and each post indexable by search engines, which
// is the traffic that actually matters for a school ("Rohi Schools admission
// 2026"). The trade-off is that a scheduled post only appears once a build
// runs — the admin panel fires a build hook on publish, and a daily build
// picks up anything scheduled.
const { supabase, publicMediaUrl } = require("./site.js");

module.exports = async function () {
  const { data, error } = await supabase
    .from("public_announcements")
    .select("*")
    .eq("status", "published")
    .lte("publish_at", new Date().toISOString())
    .order("publish_at", { ascending: false });

  if (error) {
    // Never fail the whole build because the network blipped — an empty news
    // section is far better than a broken deploy.
    console.warn("[announcements] could not load from Supabase:", error.message);
    return [];
  }

  return (data || []).map((row) => ({
    ...row,
    url: `/news/${row.slug}/`,
    coverUrl: publicMediaUrl(row.cover_image_path),
    dateObj: new Date(row.publish_at),
  }));
};
