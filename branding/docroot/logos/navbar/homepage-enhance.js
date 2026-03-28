/**
 * Homepage metrics + recent datasets (same-origin Search/Dataset API).
 * Featured row: set persistent IDs here after seed data exists, e.g.:
 *   var featuredIds = ["doi:10.5072/FK2/ABCDEF"];
 */
(function () {
  var featuredIds = [];

  function byName(fields, typeName) {
    if (!fields || !fields.length) return null;
    for (var i = 0; i < fields.length; i++) {
      if (fields[i].typeName === typeName) return fields[i];
    }
    return null;
  }

  function esc(s) {
    if (!s) return "";
    return String(s)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/"/g, "&quot;");
  }

  function datasetUrl(globalId) {
    if (!globalId) return "/dataverse.xhtml";
    return "/dataset.xhtml?persistentId=" + encodeURIComponent(globalId);
  }

  function renderCard(item, opts) {
    opts = opts || {};
    var title = item.name || "Untitled dataset";
    var gid = item.global_id || item.globalId || "";
    var authors = item.authors;
    var authorStr = "";
    if (authors && authors.join) authorStr = authors.join("; ");
    else if (typeof authors === "string") authorStr = authors;
    var subjects = item.subject || item.subjects;
    var chips = "";
    if (subjects && subjects.length) {
      var slice = subjects.slice(0, 5);
      var parts = [];
      for (var c = 0; c < slice.length; c++) {
        parts.push('<span class="dv-demo-chip">' + esc(slice[c]) + "</span>");
      }
      chips = parts.join("");
    }
    var stats = [];
    if (item.fileCount != null) stats.push(esc(String(item.fileCount)) + " files");
    if (item.sizeInBytes != null && item.sizeInBytes > 0) {
      var mb = (item.sizeInBytes / (1024 * 1024)).toFixed(1);
      stats.push(esc(mb) + " MB");
    }
    if (item.downloads != null) stats.push(esc(String(item.downloads)) + " downloads");
    var statsRow = stats.length ? '<p class="dv-demo-dataset-card__stats">' + stats.join(" · ") + "</p>" : "";
    var badge = opts.sampleBadge ? '<span class="dv-demo-badge">Sample</span>' : "";
    return (
      '<article class="dv-demo-dataset-card">' +
      badge +
      '<h3 class="dv-demo-dataset-card__title"><a href="' + esc(datasetUrl(gid)) + '">' + esc(title) + "</a></h3>" +
      (authorStr ? '<p class="dv-demo-dataset-card__authors">' + esc(authorStr) + "</p>" : "") +
      (gid ? '<p class="dv-demo-dataset-card__pid"><code>' + esc(gid) + "</code></p>" : "") +
      (chips ? '<div class="dv-demo-dataset-card__chips">' + chips + "</div>" : "") +
      statsRow +
      "</article>"
    );
  }

  function fetchJson(url) {
    return fetch(url, { credentials: "same-origin" }).then(function (r) {
      if (!r.ok) throw new Error("bad status");
      return r.json();
    });
  }

  function persistentIdFromDataset(ds) {
    if (!ds) return "";
    if (ds.persistentId) return ds.persistentId;
    if (ds.protocol && ds.authority && ds.identifier) {
      var sep = ds.separator != null ? ds.separator : "/";
      return ds.protocol + ":" + ds.authority + sep + ds.identifier;
    }
    return "";
  }

  function cardFromDatasetApi(ds) {
    var lv = ds.latestVersion;
    if (!lv) return null;
    var citation = (lv.metadataBlocks && lv.metadataBlocks.citation) || {};
    var fields = citation.fields || [];
    var titleF = byName(fields, "title");
    var title = titleF && titleF.value ? titleF.value : "";
    var authorF = byName(fields, "author");
    var authors = [];
    if (authorF && authorF.value && authorF.value.length) {
      for (var a = 0; a < authorF.value.length; a++) {
        var row = authorF.value[a];
        var name = row && row.authorName && row.authorName.value ? row.authorName.value : "";
        if (name) authors.push(name);
      }
    }
    var subjF = byName(fields, "subject");
    var subjects = [];
    if (subjF && subjF.value != null) {
      subjects = subjF.value instanceof Array ? subjF.value : [subjF.value];
    }
    var gid = persistentIdFromDataset(ds);
    return {
      name: title || "Dataset",
      global_id: gid,
      authors: authors,
      subject: subjects
    };
  }

  var featuredRoot = document.getElementById("dv-demo-featured-cards");
  var recentRoot = document.getElementById("dv-demo-recent-cards");
  var recentFallback = document.getElementById("dv-demo-recent-fallback");

  if (featuredRoot && featuredIds.length) {
    Promise.all(
      featuredIds.map(function (pid) {
        return fetchJson(
          "/api/datasets/:persistentId?persistentId=" + encodeURIComponent(pid)
        ).catch(function () {
          return null;
        });
      })
    ).then(function (results) {
      var html = "";
      for (var i = 0; i < results.length; i++) {
        var item = cardFromDatasetApi(results[i]);
        if (item && item.global_id) html += renderCard(item, {});
      }
      if (html) featuredRoot.innerHTML = html;
    });
  }

  if (recentRoot) {
    fetchJson("/api/search?q=*&type=dataset&sort=date&order=desc&per_page=6&start=0")
      .then(function (data) {
        var items = (data && data.items) || [];
        recentRoot.setAttribute("aria-busy", "false");
        if (recentFallback) recentFallback.remove();
        if (!items.length) {
          recentRoot.innerHTML =
            '<p class="dv-demo-cards-fallback">Nothing published yet—use <strong>Start a dataset</strong> above or browse collections.</p>';
          return;
        }
        var skip = {};
        for (var f = 0; f < featuredIds.length; f++) skip[featuredIds[f]] = true;
        var shown = [];
        for (var j = 0; j < items.length && shown.length < 3; j++) {
          var it = items[j];
          var gid0 = it.global_id || it.globalId;
          if (gid0 && skip[gid0]) continue;
          shown.push(it);
        }
        if (!shown.length) shown = items.slice(0, 3);
        var parts = [];
        for (var k = 0; k < shown.length; k++) {
          parts.push(renderCard(shown[k], {}));
        }
        recentRoot.innerHTML = parts.join("");
      })
      .catch(function () {
        recentRoot.setAttribute("aria-busy", "false");
        if (recentFallback) {
          recentFallback.textContent =
            "Could not load recent datasets for this demo. Use Search or Browse in the header.";
        }
      });
  }
})();
