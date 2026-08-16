/* ==========================================================================
   Scroll reveal — ~40 lines, no dependency.

   The hidden state is applied by adding .js-reveal to <html>, and only after
   confirming IntersectionObserver exists. If this file never runs, is blocked,
   or the browser is too old, nothing is hidden and the page reads normally.
   That ordering is deliberate: content must never depend on JS to become
   visible.
   ========================================================================== */
(function () {
  "use strict";

  var reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  if (reduced || !("IntersectionObserver" in window)) return;

  document.documentElement.classList.add("js-reveal");

  function start() {
    var targets = document.querySelectorAll(".reveal, .reveal-stagger");
    if (!targets.length) return;

    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (!entry.isIntersecting) return;
        entry.target.classList.add("is-in");
        io.unobserve(entry.target); // reveal once; no re-hiding on scroll back
      });
    }, {
      // Fire slightly before the element reaches the viewport so the motion
      // finishes as it arrives rather than starting late.
      rootMargin: "0px 0px -8% 0px",
      threshold: 0.08,
    });

    targets.forEach(function (el) { io.observe(el); });

    // Anything already on screen at load reveals immediately, so the first
    // paint is never a blank hero.
    requestAnimationFrame(function () {
      targets.forEach(function (el) {
        var r = el.getBoundingClientRect();
        if (r.top < window.innerHeight && r.bottom > 0) {
          el.classList.add("is-in");
          io.unobserve(el);
        }
      });
    });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", start);
  } else {
    start();
  }
})();
