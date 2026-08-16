/* ==========================================================================
   Rohi School Portal — service worker.

   SCOPE NOTE. The portal's pages live at the site root alongside the Eleventy
   marketing site, so this worker's scope is necessarily "/". It is registered
   ONLY from portal pages, and the fetch handler below returns without calling
   respondWith() for anything that is not a portal asset — so every marketing
   page, and every request this file does not explicitly claim, is handled by
   the browser exactly as if no service worker existed.

   WHAT IS NEVER CACHED, DELIBERATELY:
     - Supabase (all data: results, payments, exams, attendance, announcements,
       profiles). Cross-origin, and never intercepted at all.
     - take-exam.html and anything it needs. An exam must never be served from
       a cache, never look available offline, and never replay a stale paper.
     - Any non-GET request.
   ========================================================================== */

const VERSION = "rohi-portal-v1";
const SHELL_CACHE = `${VERSION}-shell`;
const ASSET_CACHE = `${VERSION}-assets`;
const OFFLINE_URL = "/portal-offline.html";

/* Portal HTML. take-exam.html is deliberately absent. */
const PORTAL_PAGES = [
  "/portal.html",
  "/student.html",
  "/student-results.html",
  "/teacher-dashboard.html",
  "/admin-dashboard.html",
  "/class-roster.html",
  "/payment-record.html",
];

/* Static assets safe to serve from cache. Versioned or rarely-changing. */
const PORTAL_ASSETS = [
  "/css/portal.css",
  "/css/students.css",
  "/css/teacher-dashboard.css",
  "/css/admin.css",
  "/css/student-results.css",
  "/css/class-roster.css",
  "/js/portal-utils.js",
  "/img/rohilo.jpg",
  "/img/icons/icon-192.png",
  "/img/icons/icon-512.png",
  "/favicon.ico",
];

/* The exam flow, excluded from every code path in this worker. */
const EXAM_PATHS = ["/take-exam.html"];

function isExam(url) {
  return EXAM_PATHS.some((p) => url.pathname === p || url.pathname.startsWith(p));
}

function isPortalPage(url) {
  return PORTAL_PAGES.includes(url.pathname);
}

/* A same-origin static asset the portal uses. Marketing-site CSS (site.css)
   is intentionally excluded so the public site is never touched. */
function isPortalAsset(url) {
  if (PORTAL_ASSETS.includes(url.pathname)) return true;
  if (url.pathname.startsWith("/img/icons/")) return true;
  return false;
}

self.addEventListener("install", (event) => {
  event.waitUntil((async () => {
    const shell = await caches.open(SHELL_CACHE);
    // addAll() is atomic — one 404 would abort the whole install, so add
    // individually and tolerate a missing file.
    await Promise.all(
      [OFFLINE_URL, ...PORTAL_PAGES, ...PORTAL_ASSETS].map((u) =>
        shell.add(new Request(u, { cache: "reload" })).catch(() => {})
      )
    );
    await self.skipWaiting();
  })());
});

self.addEventListener("activate", (event) => {
  event.waitUntil((async () => {
    const names = await caches.keys();
    await Promise.all(
      names.filter((n) => !n.startsWith(VERSION)).map((n) => caches.delete(n))
    );
    await self.clients.claim();
  })());
});

self.addEventListener("fetch", (event) => {
  const req = event.request;

  // Never touch anything but plain GETs.
  if (req.method !== "GET") return;

  let url;
  try { url = new URL(req.url); } catch (e) { return; }

  // Cross-origin (Supabase data, CDN, Google Fonts) — hands off entirely.
  if (url.origin !== self.location.origin) return;

  // The exam is off-limits to this worker in every respect.
  if (isExam(url)) return;

  const isNavigation =
    req.mode === "navigate" ||
    (req.headers.get("accept") || "").includes("text/html");

  if (isNavigation) {
    // Only portal pages are claimed. A marketing-site navigation falls through
    // to the browser, so the public site behaves as if no worker were present.
    if (!isPortalPage(url)) return;

    event.respondWith((async () => {
      try {
        // Network first: the portal must always render the current build.
        const fresh = await fetch(req);
        if (fresh && fresh.ok) {
          const shell = await caches.open(SHELL_CACHE);
          shell.put(req, fresh.clone());
        }
        return fresh;
      } catch (e) {
        // Offline. Serve the last good copy of this page if we have one, so a
        // teacher who loses signal still sees the shell rather than a dead tab.
        const cached = await caches.match(req, { ignoreSearch: true });
        if (cached) return cached;
        const offline = await caches.match(OFFLINE_URL);
        return offline || new Response("Offline", { status: 503, headers: { "Content-Type": "text/plain" } });
      }
    })());
    return;
  }

  // Static assets: cache-first, refreshed in the background.
  if (isPortalAsset(url)) {
    event.respondWith((async () => {
      const cached = await caches.match(req, { ignoreSearch: true });
      const network = fetch(req).then((res) => {
        if (res && res.ok) {
          caches.open(ASSET_CACHE).then((c) => c.put(req, res.clone()));
        }
        return res;
      }).catch(() => null);
      return cached || (await network) ||
        new Response("", { status: 504 });
    })());
    return;
  }

  // Everything else is left to the browser.
});

/* Lets a page force an update without the user hunting through devtools. */
self.addEventListener("message", (event) => {
  if (event.data === "skipWaiting") self.skipWaiting();
});
