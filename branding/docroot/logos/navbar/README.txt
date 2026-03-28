Navbar + splash assets (same bind-mount → /dv/docroot/logos/navbar).

  logo.png
    Navbar logo for :LogoCustomizationFile (/logos/navbar/logo.png).

    IMPORTANT — sharp on Retina / HiDPI:
    A tiny export (e.g. 160×50) is too small for a wide lockup (icon + NOTCH8 + divider + “Dataverse”):
    the browser scales it up and it looks blurry/soft.

    Recommended: 480×150 (3.2∶1) for a divider lockup on Retina. The demo theme caps display to
    Up to ~76px tall × ~192px wide (~58px / ~160px on narrow mobile); the bar has extra vertical padding so
    it does not feel cramped;
    use a sharp @2x/@3x PNG. custom-stylesheet.css targets img.navbar-brand.custom-logo (Dataverse
    puts those classes on the <img>, not on a wrapper). navbar-enhance.js syncs logo + link row height
    between a floor and cap; search field, search button, and Get Support use --dv-demo-nav-control-height
    (40px) in custom-stylesheet.css. Tune :root --dv-demo-nav-chrome-max and the JS cap to change bar height.

    Alternative: build the lockup with HTML/CSS + real SVG/PNG icon only (no full lockup raster), or
    use an SVG if your Dataverse build accepts it (official support varies; PNG @2x is the safe bet).

  splash-hero.png
    Full-bleed background for the custom homepage (CSS → /logos/navbar/splash-hero.png).
    Design with a clear left “safe” zone for headline/copy; shapes/art can sit on the right.
    ~1600×900 (16∶9) or wider works well; file must stay on this URL for the splash BG.

If logo.png is missing, remove LOGO_CUSTOMIZATION_FILE from branding/branding.env or add an image.
