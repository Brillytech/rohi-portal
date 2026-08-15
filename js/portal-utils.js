/* ==========================================================================
   Shared portal helpers — plain globals, no build step, loaded with a
   <script src> before each page's own inline script.
   ========================================================================== */

/* --------------------------------------------------------------------------
   Passport photo compression.

   A photo straight off a phone is 2–6 MB. Supabase's free tier gives 1 GB of
   file storage, so ~500 students at 3 MB each would be ~1.5 GB — over the
   limit before the whole school is even enrolled. A report-card passport
   photo is displayed at roughly 60x70 CSS px, so full resolution buys
   nothing. Downscaling to 480x600 and encoding JPEG at 0.82 lands around
   40–60 KB: the same 500 students then cost ~25 MB, about 2.5% of the tier.

   Everything is normalised to .jpg so a replacement always overwrites the
   same object. Keying the path on the *source* extension leaves photo.png
   AND photo.jpg behind for the same student, quietly doubling usage.
-------------------------------------------------------------------------- */
const PHOTO_MAX_W = 480;
const PHOTO_MAX_H = 600;
const PHOTO_QUALITY = 0.82;
const PHOTO_SOURCE_LIMIT_MB = 25; // reject absurd inputs before decoding

function photoPathFor(studentId) {
  return `${studentId}/photo.jpg`;
}

function compressPhoto(file) {
  return new Promise((resolve, reject) => {
    if (!file) return reject(new Error("No file selected."));
    if (!/^image\//.test(file.type)) return reject(new Error("That file is not an image."));
    if (file.size > PHOTO_SOURCE_LIMIT_MB * 1024 * 1024) {
      return reject(new Error(`That image is very large (${(file.size / 1048576).toFixed(1)} MB). Please choose one under ${PHOTO_SOURCE_LIMIT_MB} MB.`));
    }

    const reader = new FileReader();
    reader.onerror = () => reject(new Error("Could not read that file."));
    reader.onload = () => {
      const img = new Image();
      img.onerror = () => reject(new Error("That image could not be opened."));
      img.onload = () => {
        // Contain within the target box, never upscale a small photo.
        const scale = Math.min(PHOTO_MAX_W / img.width, PHOTO_MAX_H / img.height, 1);
        const w = Math.max(1, Math.round(img.width * scale));
        const h = Math.max(1, Math.round(img.height * scale));

        const canvas = document.createElement("canvas");
        canvas.width = w;
        canvas.height = h;
        const ctx = canvas.getContext("2d");
        ctx.imageSmoothingQuality = "high";
        // JPEG has no alpha; without this, transparent PNGs come out black.
        ctx.fillStyle = "#ffffff";
        ctx.fillRect(0, 0, w, h);
        ctx.drawImage(img, 0, 0, w, h);

        canvas.toBlob((blob) => {
          if (!blob) return reject(new Error("Could not process that image."));
          resolve(blob);
        }, "image/jpeg", PHOTO_QUALITY);
      };
      img.src = reader.result;
    };
    reader.readAsDataURL(file);
  });
}

/* --------------------------------------------------------------------------
   Signed URLs for many photos at once.

   One signed-URL request per student would be dozens of round trips on a
   class list, so use the batch endpoint and return a path -> url map.
-------------------------------------------------------------------------- */
async function signedPhotoUrls(client, paths, expiresIn = 3600) {
  const clean = [...new Set((paths || []).filter(Boolean))];
  const map = {};
  if (!clean.length) return map;
  const { data, error } = await client.storage.from("student-photos").createSignedUrls(clean, expiresIn);
  if (error || !data) return map;
  data.forEach((row) => {
    if (row && row.signedUrl && !row.error) map[row.path] = row.signedUrl;
  });
  return map;
}

/* Avatar that shows the real photo when there is one, initials otherwise. */
function initialsOf(name) {
  return (name || "").trim().split(/\s+/).slice(0, 2).map((p) => p[0]).join("").toUpperCase() || "?";
}

function avatarHtml(profile, photoUrl, opts = {}) {
  const size = opts.size || 32;
  const cls = opts.className || "";
  const style = `width:${size}px;height:${size}px;font-size:${Math.round(size * 0.36)}px;${opts.style || ""}`;
  if (photoUrl) {
    return `<span class="avatar-chip has-photo ${cls}" style="${style}"><img src="${photoUrl}" alt="" loading="lazy" /></span>`;
  }
  return `<span class="avatar-chip ${cls}" style="${style}">${initialsOf(profile && profile.full_name)}</span>`;
}

/* --------------------------------------------------------------------------
   Auto-fitting figures.

   A stat card shows "56" one term and "₦20,800,000" the next. Rather than
   letting a long figure overflow (or wrap, which is unreadable for money),
   step the font size down until it fits its box.
-------------------------------------------------------------------------- */
function fitFigure(el, opts = {}) {
  if (!el) return;
  const max = opts.max || parseFloat(el.dataset.fitMax || "") || null;
  const min = opts.min || 11;

  // Remember the design size once, so repeated calls don't ratchet downwards.
  if (!el.dataset.fitBase) {
    el.dataset.fitBase = String(max || parseFloat(getComputedStyle(el).fontSize) || 24);
  }
  const base = parseFloat(el.dataset.fitBase);

  el.style.fontSize = base + "px";
  const available = el.clientWidth;
  if (!available) return;

  let size = base;
  // scrollWidth > clientWidth means the text is wider than the box.
  while (size > min && el.scrollWidth > available) {
    size -= 1;
    el.style.fontSize = size + "px";
  }
}

function autoFitFigures(root = document, selector = ".stat-value, .js-fit") {
  (root.querySelectorAll ? root : document).querySelectorAll(selector).forEach((el) => fitFigure(el));
}

// Re-fit on resize/orientation change, coalesced into one frame.
let __fitTimer = null;
window.addEventListener("resize", () => {
  clearTimeout(__fitTimer);
  __fitTimer = setTimeout(() => autoFitFigures(), 120);
});
