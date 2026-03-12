module.exports = {
  layout: "layouts/post.njk",
  tags: ["posts"],
  permalink: (data) => `/news/${data.page.fileSlug}/`,
};