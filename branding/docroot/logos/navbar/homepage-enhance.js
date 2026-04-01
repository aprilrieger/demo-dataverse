// ============================================================================
/* DataverseUp — navbar-enhance.js */
// Simple helper for navbar polish
// ============================================================================

console.log('homepage-enhance loaded');

(function () {
  function updateNavbarBrand() {
    var brandImg = document.querySelector('.navbar-brand img');
    if (brandImg) {
      brandImg.alt = 'DataverseUp';
      brandImg.style.maxHeight = '42px';
      brandImg.style.width = 'auto';
    }
  }

  function apply() {
    updateNavbarBrand();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', apply);
  } else {
    apply();
  }
})();