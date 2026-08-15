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

function compressPhoto(file, opts = {}) {
  const maxW = opts.maxW || PHOTO_MAX_W;
  const maxH = opts.maxH || PHOTO_MAX_H;
  const quality = opts.quality || PHOTO_QUALITY;
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
        const scale = Math.min(maxW / img.width, maxH / img.height, 1);
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
        }, "image/jpeg", quality);
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

/* --------------------------------------------------------------------------
   Auto-fit, applied portal-wide.

   Calling autoFitFigures() by hand after every render meant it only ever ran
   where someone remembered to add the call. A observer catches every figure
   on every page instead — including ones drawn later by a re-render.

   Only childList/characterData are observed, never attributes: fitFigure
   writes style.fontSize, so observing attributes would re-trigger itself.
-------------------------------------------------------------------------- */
let __fitPending = null;
function scheduleAutoFit() {
  if (__fitPending) return;
  __fitPending = requestAnimationFrame(() => {
    __fitPending = null;
    autoFitFigures();
  });
}

function installAutoFit() {
  autoFitFigures();
  new MutationObserver(scheduleAutoFit)
    .observe(document.body, { childList: true, subtree: true, characterData: true });
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", installAutoFit);
} else {
  installAutoFit();
}

/* ==========================================================================
   Drafts / auto-save

   Losing a screen of typing because a phone rang is the single most annoying
   thing a portal can do. Work in progress is mirrored to localStorage as it
   is typed, and restored on the next visit.

   Keys are namespaced per signed-in user, so a shared staff phone never shows
   one person's draft to the next. Drafts expire so they cannot resurface
   months later and be mistaken for current data, and are cleared on both
   successful submit and logout.
   ========================================================================== */
const DRAFT_PREFIX = "rohi.draft.";
const DRAFT_TTL_MS = 7 * 24 * 60 * 60 * 1000; // a week
let __draftUser = "anon";

function setDraftUser(userId) {
  __draftUser = userId || "anon";
}

function draftKey(key) {
  return `${DRAFT_PREFIX}${__draftUser}.${key}`;
}

function saveDraft(key, data) {
  try {
    localStorage.setItem(draftKey(key), JSON.stringify({ at: Date.now(), data }));
  } catch (e) {
    // Quota or private mode — losing autosave must never break the page.
  }
}

function loadDraft(key) {
  try {
    const raw = localStorage.getItem(draftKey(key));
    if (!raw) return null;
    const parsed = JSON.parse(raw);
    if (!parsed || typeof parsed.at !== "number") return null;
    if (Date.now() - parsed.at > DRAFT_TTL_MS) {
      localStorage.removeItem(draftKey(key));
      return null;
    }
    return parsed.data;
  } catch (e) {
    return null;
  }
}

function clearDraft(key) {
  try { localStorage.removeItem(draftKey(key)); } catch (e) {}
}

function clearAllDrafts() {
  try {
    Object.keys(localStorage)
      .filter((k) => k.startsWith(DRAFT_PREFIX))
      .forEach((k) => localStorage.removeItem(k));
  } catch (e) {}
}

function draftAge(key) {
  try {
    const raw = localStorage.getItem(draftKey(key));
    if (!raw) return null;
    const at = JSON.parse(raw).at;
    const mins = Math.round((Date.now() - at) / 60000);
    if (mins < 1) return "just now";
    if (mins < 60) return `${mins} minute${mins === 1 ? "" : "s"} ago`;
    const hrs = Math.round(mins / 60);
    if (hrs < 24) return `${hrs} hour${hrs === 1 ? "" : "s"} ago`;
    const days = Math.round(hrs / 24);
    return `${days} day${days === 1 ? "" : "s"} ago`;
  } catch (e) { return null; }
}

/* A small "Draft saved" pill so the user can see it is working. */
function draftStatus(el, text, tone = "saved") {
  if (!el) return;
  el.textContent = text;
  el.className = `draft-status draft-${tone}` + (text ? " show" : "");
}

/* --------------------------------------------------------------------------
   autosaveForm — wires a whole <form> in one line.

   Reads and writes every named control by id (falling back to name), skipping
   passwords and file inputs, which cannot be meaningfully restored.
-------------------------------------------------------------------------- */
function formControls(form) {
  return [...form.querySelectorAll("input, select, textarea")].filter((el) => {
    if (el.type === "password" || el.type === "file" || el.type === "submit" || el.type === "button") return false;
    return !!(el.id || el.name);
  });
}

function readForm(form) {
  const out = {};
  formControls(form).forEach((el) => {
    const k = el.id || el.name;
    out[k] = el.type === "checkbox" ? el.checked : el.value;
  });
  return out;
}

function writeForm(form, data) {
  if (!data) return false;
  let restoredSomething = false;
  formControls(form).forEach((el) => {
    const k = el.id || el.name;
    if (!(k in data)) return;
    const v = data[k];
    if (el.type === "checkbox") {
      if (el.checked !== !!v) { el.checked = !!v; restoredSomething = true; }
    } else if (v !== "" && el.value !== v) {
      el.value = v;
      restoredSomething = true;
    }
  });
  return restoredSomething;
}

function hasContent(data) {
  return !!data && Object.values(data).some((v) => v !== "" && v !== false && v != null);
}

/**
 * @param form      the <form> element
 * @param key       stable draft key
 * @param opts.statusEl  element to show "Draft saved" in
 * @param opts.onRestore  called after a draft is restored
 */
function autosaveForm(form, key, opts = {}) {
  if (!form) return;
  const statusEl = opts.statusEl || null;

  const existing = loadDraft(key);
  if (hasContent(existing) && writeForm(form, existing)) {
    draftStatus(statusEl, `Unsaved draft restored from ${draftAge(key) || "earlier"}`, "restored");
    if (opts.onRestore) opts.onRestore(existing);
  }

  let t = null;
  const persist = () => {
    clearTimeout(t);
    t = setTimeout(() => {
      const data = readForm(form);
      if (hasContent(data)) {
        saveDraft(key, data);
        draftStatus(statusEl, "Draft saved", "saved");
      } else {
        clearDraft(key);
        draftStatus(statusEl, "", "saved");
      }
    }, 400);
  };

  form.addEventListener("input", persist);
  form.addEventListener("change", persist);
  // A successful submit means the draft has served its purpose.
  form.addEventListener("submit", () => {
    clearDraft(key);
    draftStatus(statusEl, "", "saved");
  });

  return { clear: () => { clearDraft(key); draftStatus(statusEl, "", "saved"); } };
}
