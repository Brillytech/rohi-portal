/* ==========================================================================
   Portal PWA glue — registration + install prompt.

   Loaded only by portal pages. take-exam.html deliberately does NOT include
   this file, and the worker itself refuses to handle the exam route, so the
   exam flow is untouched from both ends.

   Nothing here changes auth, RLS or any data path; it is purely additive.
   ========================================================================== */
(function () {
  "use strict";

  // Defence in depth: even if this file were pulled onto the wrong page, it
  // registers nothing outside the portal's own routes.
  var PORTAL_PAGES = [
    "/portal.html", "/student.html", "/student-results.html",
    "/teacher-dashboard.html", "/admin-dashboard.html",
    "/class-roster.html", "/payment-record.html",
  ];
  var path = window.location.pathname;
  if (PORTAL_PAGES.indexOf(path) === -1) return;

  /* Styles are injected rather than added to each of the six portal
     stylesheets, so this stays a single self-contained file. */
  var css = document.createElement("style");
  css.textContent = [
    ".pwa-install-bar{position:fixed;left:50%;bottom:18px;transform:translate(-50%,140%);",
    "display:flex;align-items:center;gap:10px;z-index:2000;",
    "background:linear-gradient(135deg,#590694,#2a0450);color:#fff;",
    "padding:11px 14px;border-radius:14px;box-shadow:0 14px 34px rgba(12,2,26,.4);",
    "font-family:'Inter',system-ui,sans-serif;font-size:.85rem;",
    "max-width:calc(100vw - 32px);transition:transform .25s ease,opacity .25s ease;opacity:0}",
    ".pwa-install-bar.show{transform:translate(-50%,0);opacity:1}",
    ".pwa-install-bar i{font-size:1.05rem;color:#ffb347;flex:none}",
    ".pwa-install-bar span{flex:1;min-width:0;line-height:1.35}",
    ".pwa-install-yes{background:#fff;color:#590694;border:none;border-radius:9px;",
    "padding:7px 14px;font-weight:700;font-size:.8rem;cursor:pointer;flex:none}",
    ".pwa-install-no{background:transparent;border:none;color:rgba(255,255,255,.75);",
    "font-size:1.25rem;line-height:1;cursor:pointer;padding:0 4px;flex:none}",
    "@media (prefers-reduced-motion: reduce){.pwa-install-bar{transition:none}}",
  ].join("");
  document.head.appendChild(css);

  /* ---- Service worker ---------------------------------------------------- */
  if ("serviceWorker" in navigator) {
    window.addEventListener("load", function () {
      navigator.serviceWorker.register("/sw-portal.js").catch(function () {
        // A failed registration must never break the portal — it just means
        // no offline shell this session.
      });
    });
  }

  /* ---- Install prompt ----------------------------------------------------
     Chrome/Edge fire beforeinstallprompt and let us defer it to our own
     button. iOS Safari fires nothing and has no programmatic install, so
     there we show a short "Share -> Add to Home Screen" hint instead, once.
  ------------------------------------------------------------------------- */
  var deferred = null;
  var DISMISS_KEY = "rohi.pwa.dismissed";

  function alreadyInstalled() {
    return window.matchMedia("(display-mode: standalone)").matches ||
           window.navigator.standalone === true;
  }

  function dismissed() {
    try { return localStorage.getItem(DISMISS_KEY) === "1"; } catch (e) { return false; }
  }

  function remember() {
    try { localStorage.setItem(DISMISS_KEY, "1"); } catch (e) {}
  }

  function makeBar(html) {
    var bar = document.createElement("div");
    bar.className = "pwa-install-bar";
    bar.innerHTML = html;
    document.body.appendChild(bar);
    requestAnimationFrame(function () { bar.classList.add("show"); });
    return bar;
  }

  function close(bar) {
    bar.classList.remove("show");
    setTimeout(function () { bar.remove(); }, 250);
  }

  window.addEventListener("beforeinstallprompt", function (e) {
    e.preventDefault();
    deferred = e;
    if (alreadyInstalled() || dismissed()) return;

    var bar = makeBar(
      '<i class="bi bi-download"></i>' +
      '<span>Install the portal for quicker access</span>' +
      '<button type="button" class="pwa-install-yes">Install</button>' +
      '<button type="button" class="pwa-install-no" aria-label="Dismiss">&times;</button>'
    );

    bar.querySelector(".pwa-install-yes").addEventListener("click", function () {
      close(bar);
      if (!deferred) return;
      deferred.prompt();
      deferred.userChoice.finally(function () { deferred = null; });
    });
    bar.querySelector(".pwa-install-no").addEventListener("click", function () {
      remember();
      close(bar);
    });
  });

  window.addEventListener("appinstalled", function () { remember(); deferred = null; });

  // iOS: no install event exists, so offer the manual route once.
  var isIOS = /iphone|ipad|ipod/i.test(navigator.userAgent);
  var isSafari = /^((?!chrome|android|crios|fxios).)*safari/i.test(navigator.userAgent);
  if (isIOS && isSafari && !alreadyInstalled() && !dismissed()) {
    window.addEventListener("load", function () {
      setTimeout(function () {
        var bar = makeBar(
          '<i class="bi bi-box-arrow-up"></i>' +
          '<span>Add to Home Screen: tap Share, then "Add to Home Screen"</span>' +
          '<button type="button" class="pwa-install-no" aria-label="Dismiss">&times;</button>'
        );
        bar.querySelector(".pwa-install-no").addEventListener("click", function () {
          remember();
          close(bar);
        });
      }, 2500);
    });
  }
})();
