// ============================================================================
/* DataverseUp — homepage-enhance.js */
// Optional enhancement hooks for the custom homepage
// ============================================================================

console.log('navbar-enhance loaded');

(function () {
  function smoothAnchorLinks() {
    var links = document.querySelectorAll('a[href^="#"]');
    for (var i = 0; i < links.length; i++) {
      links[i].addEventListener('click', function (e) {
        var targetId = this.getAttribute('href');
        if (!targetId || targetId === '#') return;

        var target = document.querySelector(targetId);
        if (!target) return;

        e.preventDefault();
        target.scrollIntoView({ behavior: 'smooth', block: 'start' });
      });
    }
  }

  function apply() {
    smoothAnchorLinks();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', apply);
  } else {
    apply();
  }
})();
