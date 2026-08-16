const { DateTime } = require("luxon");

module.exports = function (eleventyConfig) {
  // ✅ Static assets pass-through
  eleventyConfig.addPassthroughCopy("css");
  eleventyConfig.addPassthroughCopy("img");
  eleventyConfig.addPassthroughCopy("js");

  // ✅ Standalone HTML pages outside /src
  eleventyConfig.addPassthroughCopy("portal.html");
  eleventyConfig.addPassthroughCopy("admin-dashboard.html");
  eleventyConfig.addPassthroughCopy("teacher-dashboard.html");
  eleventyConfig.addPassthroughCopy("student.html");
  eleventyConfig.addPassthroughCopy("student-results.html");
  eleventyConfig.addPassthroughCopy("take-exam.html");
  eleventyConfig.addPassthroughCopy("class-roster.html");

  // ✅ Date filter for Nunjucks: {{ post.date | date("MMMM dd, yyyy") }}
  eleventyConfig.addFilter("date", (dateObj, format = "MMMM dd, yyyy") => {
    if (!dateObj) return "";
    return DateTime.fromJSDate(dateObj, { zone: "Africa/Lagos" }).toFormat(format);
  });

  // ✅ Head filter: {{ collections.posts | head(3) }}
  eleventyConfig.addFilter("head", (arr, n = 1) => {
    if (!Array.isArray(arr)) return [];
    return arr.slice(0, n);
  });

  // News now comes from Supabase at build time (src/_data/announcements.js),
  // so there is no markdown posts collection any more.

  return {
    dir: {
      input: "src",
      output: "_site",
    },
  };
};
