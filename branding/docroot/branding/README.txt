These files map to Dataverse installation settings (see branding/branding.env):

  custom-header.html    -> :HeaderCustomizationFile
  custom-footer.html    -> :FooterCustomizationFile
  custom-stylesheet.css -> :StyleCustomizationFile
  custom-homepage.html  -> :HomePageCustomizationFile (replaces entire homepage — optional)

In the container they are served from /dv/docroot/branding/... (Compose bind-mounts this directory).

Splash hero image: ../logos/navbar/splash-hero.png -> /logos/navbar/splash-hero.png

Hero + footer carry demo disclaimers; featured placeholder copy is client-safe; configure curated PIDs
in homepage-enhance.js (not shown to visitors).

Explore by topic: currently disabled on the homepage (section#explore-topics has class
dv-demo-section--explore-off and hidden). Remove both to show the topic grid again.

Featured + Recently added: two-column split (~50/50 from 900px up); cards stack in each column.

Sign up links use Dataverse 6 account creation:
  /dataverseuser.xhtml?editMode=CREATE&redirectPage=%2Fdataverse.xhtml
If your installation uses a different :SignUpUrl, update custom-homepage.html to match the navbar
“Sign Up” target.

Navbar: ../logos/navbar/navbar-enhance.js is loaded from custom-footer.html and custom-header.html (same
URL; only one run). custom-header.html is script-only (no HTML banner). The script (1) replaces the top-level “Search” link/dropdown with an inline GET form to
/dataverse.xhtml?q=…, (2) renames/restyles “Support” as “Get Support” (orange button), (3) orders search
then Get Support. If you still see plain “Search ▼” and “Support” links, the script is not running: confirm
:FooterCustomizationFile and :HeaderCustomizationFile are set (see branding.env + apply-branding.sh), open
http(s)://<host>/logos/navbar/navbar-enhance.js in the browser (must be 200), and check the console for
“[Notch8 demo] Navbar enhancements applied” or the warning after ~8s.
On viewports ≥768px it sets --dv-demo-nav-chrome-height/--dv-demo-nav-chrome-max from the logo (floor/cap);
search field + buttons use --dv-demo-nav-control-height (40px). Optional SUPPORT_HREF and SEARCH_PLACEHOLDER
at top of the script. Dropdown menu typography is in :StyleCustomizationFile.

Optional homepage behavior: ../logos/navbar/homepage-enhance.js loads dataset counts + “Recently added”
from /api/search. Edit featuredIds at the top of that file for curated featured cards. Verify
/dataset.xhtml?ownerId=1 matches your root dataverse database id if “Try publishing” should open
create-dataset in root.

Topic tiles use subject facet URLs in custom-homepage.html; change those hrefs for client-specific
collections or searches (see marketing handoff open items).

#dataverse-header-block uses padding-top: --dv-demo-navbar-offset so #content clears the fixed navbar.

Log in UI: Dataverse uses loginpage.xhtml (not login.xhtml). The same :StyleCustomizationFile,
:HeaderCustomizationFile, and :FooterCustomizationFile apply there; extra layout/button styling for
the form lives under #login-container in custom-stylesheet.css.

Layout: #content.container is widened for the custom homepage/login so backgrounds can go edge to edge.
Main text columns use the same max-widths as the navbar’s Bootstrap 3 .container (750px / 970px / 1170px
+ 15px gutters) via .dv-demo-section-inner and .dv-demo-hero__inner.

The hero is full width of the main column (.dv-demo-hero); .dv-demo-hero__inner uses the same widths as the navbar .container (no 100vw on the hero — that skewed alignment vs the nav when scrollbars are present).
