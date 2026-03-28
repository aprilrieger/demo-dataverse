/**
 * Navbar enhancements (custom-stylesheet.css):
 * 1) Replace top-level "Search" menu (link or dropdown) with an inline search bar → /dataverse.xhtml?q=
 * 2) Move "Support" to end and restyle as "Get Support" (orange button)
 * 3) Place the search bar immediately before Get Support (end of nav)
 * 4) Desktop: set --dv-demo-nav-chrome-height/--dv-demo-nav-chrome-max from the logo (clamped to floor/cap)
 *    so the logo and text links share one row height. Search + Get Support use fixed height in CSS
 *    (--dv-demo-nav-control-height), not this sync.
 *
 * Loaded from custom-footer.html and/or custom-header.html (only one boot runs).
 * If Search/Support stay as plain links, this file is not loading — check :FooterCustomizationFile /
 * :HeaderCustomizationFile and GET /logos/navbar/navbar-enhance.js (200).
 *
 * Optional: SUPPORT_HREF for Get Support target (e.g. "https://notch8.com/contact").
 */
(function () {
  if (window.__dvNavbarEnhanceScheduled) return;
  window.__dvNavbarEnhanceScheduled = true;

  var SUPPORT_LABEL = "Get Support";
  var SUPPORT_HREF = null;
  var SEARCH_PLACEHOLDER = "Search datasets…";

  function normalizeNavLabel(text) {
    return (text || "")
      .replace(/\s+/g, " ")
      .replace(/[\u25bc\u25be\u25b8▼▾▸]/g, "")
      .trim();
  }

  /** Dataverse uses a dropdown <li class="dropdown"> with a.toggle; label may be "Search" or "Search ▼" etc. */
  function labelIsSearch(t) {
    var s = normalizeNavLabel(t).toLowerCase();
    if (s === "search") return true;
    if (/^search\b/.test(s) && s.length < 48) return true;
    return false;
  }

  function labelIsSupport(t) {
    var s = normalizeNavLabel(t).toLowerCase();
    if (s === "support") return true;
    if (/^support\b/.test(s) && s.length < 48) return true;
    return false;
  }

  function findSearchLi(ul) {
    var children = ul.children;
    for (var j = 0; j < children.length; j++) {
      var li = children[j];
      if (!li || li.tagName !== "LI") continue;
      if (li.classList.contains("dv-demo-nav-search-item")) continue;
      var a = li.firstElementChild;
      if (!a || a.tagName !== "A") continue;
      var t = normalizeNavLabel(a.textContent);
      if (labelIsSearch(t)) {
        return { li: li, nav: ul };
      }
    }
    return null;
  }

  function replaceSearchWithBar() {
    if (document.querySelector("#navbarFixed .dv-demo-nav-search-item")) return true;
    var uls = document.querySelectorAll("#navbarFixed ul.nav.navbar-nav");
    for (var u = 0; u < uls.length; u++) {
      var hit = findSearchLi(uls[u]);
      if (!hit) continue;

      var li = hit.li;
      li.className = "dv-demo-nav-search-item";
      while (li.firstChild) li.removeChild(li.firstChild);

      var form = document.createElement("form");
      form.className = "dv-demo-nav-search-form";
      form.setAttribute("action", "/dataverse.xhtml");
      form.setAttribute("method", "get");
      form.setAttribute("role", "search");

      var label = document.createElement("label");
      label.className = "dv-demo-nav-search-sr";
      label.setAttribute("for", "dv-demo-nav-search-q");
      label.textContent = "Search";

      var group = document.createElement("div");
      group.className = "input-group dv-demo-nav-search-inputgroup";

      var input = document.createElement("input");
      input.type = "search";
      input.name = "q";
      input.id = "dv-demo-nav-search-q";
      input.className = "form-control dv-demo-nav-search-input";
      input.setAttribute("placeholder", SEARCH_PLACEHOLDER);
      input.setAttribute("autocomplete", "off");

      var btnWrap = document.createElement("span");
      btnWrap.className = "input-group-btn";

      var btn = document.createElement("button");
      btn.type = "submit";
      btn.className = "btn btn-default dv-demo-nav-search-submit";
      btn.setAttribute("aria-label", "Search");
      var icon = document.createElement("span");
      icon.className = "glyphicon glyphicon-search";
      icon.setAttribute("aria-hidden", "true");
      var sr = document.createElement("span");
      sr.className = "sr-only";
      sr.textContent = "Search";
      btn.appendChild(icon);
      btn.appendChild(sr);

      btnWrap.appendChild(btn);
      group.appendChild(input);
      group.appendChild(btnWrap);

      form.appendChild(label);
      form.appendChild(group);
      li.appendChild(form);
      return true;
    }
    return false;
  }

  function findSupportInNav(ul) {
    var children = ul.children;
    for (var j = 0; j < children.length; j++) {
      var li = children[j];
      if (!li || li.tagName !== "LI") continue;
      if (li.classList.contains("dv-demo-nav-search-item")) continue;
      var a = li.firstElementChild;
      if (!a || a.tagName !== "A") continue;
      var t = normalizeNavLabel(a.textContent);
      if (labelIsSupport(t)) {
        return { li: li, link: a, nav: ul };
      }
    }
    return null;
  }

  function findSupportLi() {
    var uls = document.querySelectorAll("#navbarFixed ul.nav.navbar-nav");
    for (var u = 0; u < uls.length; u++) {
      var hit = findSupportInNav(uls[u]);
      if (hit) return hit;
    }
    return null;
  }

  function enhanceSupport() {
    if (document.querySelector("#navbarFixed .dv-demo-nav-support-item")) return true;
    var found = findSupportLi();
    if (!found) return false;
    found.li.classList.add("dv-demo-nav-support-item");
    found.link.classList.add("dv-demo-nav-support-btn");
    found.link.textContent = SUPPORT_LABEL;
    if (SUPPORT_HREF) found.link.setAttribute("href", SUPPORT_HREF);
    found.nav.appendChild(found.li);
    return true;
  }

  /** Order: … other links … → inline search → Get Support */
  function moveSearchBeforeSupportButton() {
    var searchLi = document.querySelector("#navbarFixed .dv-demo-nav-search-item");
    var supportLi = document.querySelector("#navbarFixed .dv-demo-nav-support-item");
    if (!searchLi || !supportLi) return;
    var ul = supportLi.parentNode;
    if (!ul || ul.tagName !== "UL") return;
    if (searchLi.nextElementSibling === supportLi) return;
    ul.insertBefore(searchLi, supportLi);
  }

  var logoChromeResizeTimer;
  var logoChromeWinBound;
  /** Minimum row height when the logo renders shorter — keeps links/search/support from looking squeezed */
  var DESKTOP_NAV_CHROME_FLOOR_PX = 56;
  /** Must match --dv-demo-nav-chrome-max default in custom-stylesheet.css (:root desktop) */
  var DESKTOP_NAV_CHROME_CAP_PX = 76;

  function clearForcedNavChromeHeights() {
    var nav = document.getElementById("navbarFixed");
    var root = document.documentElement;
    if (nav) {
      ["#dv-demo-nav-search-q", ".dv-demo-nav-search-submit", "a.dv-demo-nav-support-btn"].forEach(function (sel) {
        var el = nav.querySelector(sel);
        if (!el) return;
        el.style.removeProperty("height");
        el.style.removeProperty("min-height");
        el.style.removeProperty("max-height");
        el.style.removeProperty("box-sizing");
      });
      nav.style.removeProperty("--dv-demo-nav-chrome-height");
      nav.style.removeProperty("--dv-demo-nav-chrome-max");
    }
    root.style.removeProperty("--dv-demo-nav-chrome-height");
    root.style.removeProperty("--dv-demo-nav-chrome-max");
  }

  /**
   * Used height after CSS max-width/max-height (matches what you see). Inline !important beats
   * Bootstrap/PrimeFaces rules that ignore our custom property alone.
   */
  function readLogoUsedHeightPx(img) {
    var h = 0;
    try {
      h = parseFloat(window.getComputedStyle(img).height) || 0;
    } catch (e) {
      h = 0;
    }
    if (!h || h < 8) {
      h = img.offsetHeight || Math.round(img.getBoundingClientRect().height) || 0;
    }
    return Math.round(h);
  }

  /** Sync logo + link row chrome only (search / Get Support use --dv-demo-nav-control-height in CSS). */
  function applyNavChromePx(px) {
    var nav = document.getElementById("navbarFixed");
    if (!nav) return;
    var pxStr = px + "px";
    nav.style.setProperty("--dv-demo-nav-chrome-height", pxStr);
    nav.style.setProperty("--dv-demo-nav-chrome-max", pxStr);
    document.documentElement.style.setProperty("--dv-demo-nav-chrome-height", pxStr);
    document.documentElement.style.setProperty("--dv-demo-nav-chrome-max", pxStr);
  }

  function syncNavChromeHeightToLogo() {
    if (typeof window.matchMedia === "function" && !window.matchMedia("(min-width: 768px)").matches) {
      clearForcedNavChromeHeights();
      return;
    }
    var img = document.querySelector("#navbarFixed img.navbar-brand.custom-logo");
    if (!img) {
      clearForcedNavChromeHeights();
      return;
    }
    var raw = readLogoUsedHeightPx(img);
    if (raw < 12 || raw > 120) {
      clearForcedNavChromeHeights();
      return;
    }
    var h = Math.min(Math.max(raw, DESKTOP_NAV_CHROME_FLOOR_PX), DESKTOP_NAV_CHROME_CAP_PX);
    applyNavChromePx(h);
  }

  function bindLogoChromeSync() {
    var img = document.querySelector("#navbarFixed img.navbar-brand.custom-logo");
    if (!img || img.getAttribute("data-dv-nav-chrome-bound") === "1") return;
    img.setAttribute("data-dv-nav-chrome-bound", "1");
    img.addEventListener("load", syncNavChromeHeightToLogo);
    if (typeof ResizeObserver !== "undefined") {
      new ResizeObserver(function () {
        syncNavChromeHeightToLogo();
      }).observe(img);
    }
    if (!logoChromeWinBound) {
      logoChromeWinBound = true;
      window.addEventListener("resize", function () {
        clearTimeout(logoChromeResizeTimer);
        logoChromeResizeTimer = setTimeout(syncNavChromeHeightToLogo, 100);
      });
      function onWinLoad() {
        syncNavChromeHeightToLogo();
        setTimeout(syncNavChromeHeightToLogo, 100);
        setTimeout(syncNavChromeHeightToLogo, 400);
      }
      if (document.readyState === "complete") {
        onWinLoad();
      } else {
        window.addEventListener("load", onWinLoad);
      }
    }
  }

  function scheduleNavChromeSync() {
    bindLogoChromeSync();
    syncNavChromeHeightToLogo();
    if (typeof requestAnimationFrame === "function") {
      requestAnimationFrame(syncNavChromeHeightToLogo);
    }
    [0, 50, 150, 400, 800, 1600, 3200].forEach(function (ms) {
      setTimeout(syncNavChromeHeightToLogo, ms);
    });
  }

  function tick() {
    replaceSearchWithBar();
    var ok = enhanceSupport();
    moveSearchBeforeSupportButton();
    bindLogoChromeSync();
    syncNavChromeHeightToLogo();
    return ok;
  }

  function boot() {
    function afterNavReady() {
      scheduleNavChromeSync();
    }
    if (tick()) {
      if (typeof console !== "undefined" && console.info) {
        console.info("[Notch8 demo] Navbar enhancements applied (inline search + Get Support).");
      }
      afterNavReady();
      return;
    }
    var obs = new MutationObserver(function () {
      if (tick()) {
        if (typeof console !== "undefined" && console.info) {
          console.info("[Notch8 demo] Navbar enhancements applied (inline search + Get Support).");
        }
        obs.disconnect();
        afterNavReady();
      }
    });
    var root = document.getElementById("navbarFixed") || document.body;
    obs.observe(root, { childList: true, subtree: true });
    setTimeout(function () {
      obs.disconnect();
      afterNavReady();
      if (!document.querySelector("#navbarFixed .dv-demo-nav-search-item") && typeof console !== "undefined" && console.warn) {
        console.warn(
          "[Notch8 demo] Inline search not found — is navbar-enhance.js loading? Set :FooterCustomizationFile and :HeaderCustomizationFile; open /logos/navbar/navbar-enhance.js in the browser (expect 200)."
        );
      }
    }, 8000);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", boot);
  } else {
    boot();
  }
})();
