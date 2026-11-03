(() => {
  const api = globalThis.browser || globalThis.chrome;
  const $ = id => document.getElementById(id);
  const params = new URL(location.href).searchParams;
  const id = params.get("id");
  let doc, preferences = GopherDocument.prefs(), saved = [];
  let matches = [], matchIndex = -1;
  const anchors = new Map();
  const elements = [];

  function element(tag, text, className) {
    const node = document.createElement(tag);
    if (text != null) node.textContent = text;
    if (className) node.className = className;
    return node;
  }
  async function request(type, data = {}) {
    const response = await api.runtime.sendMessage({type, ...data});
    if (!response?.ok) throw new Error(response?.error || "The extension could not complete this action. Try again.");
    return response;
  }
  function status(message = "") { $("status").textContent = message; }
  function error(message) {
    $("error").textContent = message;
    $("error").hidden = false;
    status();
  }
  function clearError() { $("error").hidden = true; $("error").textContent = ""; }
  function externalLink(url, text) {
    const link = element("a", text);
    const destination = GopherDocument.safeUrl(url);
    if (destination) link.href = destination;
    link.target = "_blank";
    link.rel = "noopener noreferrer";
    if (destination) link.addEventListener("click", event => {
      const target = new URL(destination), source = new URL(doc?.source.url || destination);
      if (target.origin === source.origin && target.pathname === source.pathname &&
          target.search === source.search && target.hash) {
        let fragment;
        try { fragment = decodeURIComponent(target.hash.slice(1)); } catch { return; }
        const node = anchors.get(fragment);
        if (node) { event.preventDefault(); node.scrollIntoView({block: "start"}); }
      }
    });
    return link;
  }
  function appendInlines(node, parts) {
    for (const part of parts || []) {
      const link = part.link && doc.links.find(item => item.id === part.link);
      if (link) {
        const anchor = externalLink(link.url, part.text);
        anchor.title = link.url;
        anchor.append(element("span", ` [${link.id}]`, "link-reference"));
        node.append(anchor);
      } else node.append(document.createTextNode(part.text || ""));
    }
  }
  function applyPreferences() {
    document.documentElement.dataset.theme = preferences.theme;
    document.documentElement.style.setProperty("--reading-size", `${preferences.fontSize}px`);
    $("reading").classList.toggle("nowrap", !preferences.wrap);
    $("wrap").setAttribute("aria-pressed", String(preferences.wrap));
    $("theme").value = preferences.theme;
    $("font-down").disabled = preferences.fontSize <= 14;
    $("font-up").disabled = preferences.fontSize >= 26;
    for (const button of document.querySelectorAll("[data-mode]")) {
      button.setAttribute("aria-pressed", String(button.dataset.mode === preferences.mode));
    }
  }
  function bookmarkState() {
    const active = saved.some(item => item.url === doc?.source.url);
    $("save").setAttribute("aria-pressed", String(active));
    $("save").textContent = active ? "Saved" : "Save page";
  }
  function render() {
    GopherDocument.validate(doc);
    document.title = `${doc.source.title} — Gopher Reader`;
    $("title").textContent = doc.source.title;
    $("title").dir = doc.source.dir;
    $("source").href = doc.source.url;
    $("source").textContent = new URL(doc.source.url).host + new URL(doc.source.url).pathname;
    $("original").href = doc.source.url;
    $("original").hidden = false;
    $("refresh").hidden = false;
    $("byline").textContent = doc.source.byline;
    $("byline").hidden = !doc.source.byline;
    const notices = [...(doc.notices || [])];
    if (preferences.mode === "article" && doc.article.fallback) notices.push("Showing the page’s readable text.");
    $("note").textContent = notices.join(" ");
    $("note").hidden = !notices.length;
    $("captured").textContent = `Reading copy from ${new Date(doc.source.capturedAt).toLocaleString()}`;
    $("link-count").textContent = `(${doc.links.length})`;
    $("reading").dir = doc.source.dir;
    $("content").lang = doc.source.lang;
    $("content").replaceChildren();
    anchors.clear(); elements.length = 0;
    if (preferences.mode === "links") {
      const list = element("ul", null, "link-index");
      for (const link of doc.links) {
        const row = element("li");
        row.append(externalLink(link.url, `[${link.id}] ${link.label}`), element("span", link.url, "destination"));
        list.append(row);
      }
      if (!doc.links.length) list.append(element("li", "This page has no web or Gopher links."));
      $("content").append(list);
    } else {
      const blocks = preferences.mode === "page" ? doc.page.blocks : doc.article.blocks;
      for (const block of blocks) {
        const ownText = block.inlines?.map(part => part.text).join("").trim();
        if (block.kind === "heading" && ownText === doc.source.title && !elements.length) {
          for (const sourceId of block.sourceIds || []) anchors.set(sourceId, $("title"));
          continue;
        }
        if (!elements.length && block.kind === "paragraph" && doc.source.byline &&
            ownText?.replace(/^by\s+/i, "").toLowerCase() === doc.source.byline.toLowerCase()) continue;
        let node;
        switch (block.kind) {
          case "pre": node = element("pre", block.text); break;
          case "image": node = element("p", `[Image: ${block.text}]`, "image-description"); break;
          case "table": {
            node = element("div", null, "table-scroll");
            const table = element("table");
            for (const row of block.rows || []) {
              const tr = element("tr");
              for (const cell of row) {
                const td = element(cell.header ? "th" : "td");
                if (cell.header) td.scope = "col";
                appendInlines(td, cell.inlines); tr.append(td);
              }
              table.append(tr);
            }
            node.append(table); break;
          }
          default: {
            const tag = block.kind === "heading" ? `h${Math.min(6, Math.max(2, block.level))}` : block.kind === "quote" ? "blockquote" : "p";
            node = element(tag, null, block.kind === "listItem" ? "list-item" : "paragraph");
            if (block.kind === "listItem") {
              node.style.setProperty("--depth", String(Math.min(8, Math.max(0, block.depth || 0))));
              node.append(document.createTextNode(block.prefix));
            }
            appendInlines(node, block.inlines);
          }
        }
        for (const sourceId of block.sourceIds || []) anchors.set(sourceId, node);
        elements.push(node); $("content").append(node);
      }
    }
    $("reading").hidden = false; $("toolbar").hidden = false;
    applyPreferences(); bookmarkState();
    if (!$("find-panel").hidden) highlight();
  }
  async function changePreferences(changes) {
    preferences = GopherDocument.prefs({...preferences, ...changes});
    render();
    try { await request("preferences", {value: preferences}); }
    catch (failure) { error(failure.message); }
  }
  function clearMarks() {
    for (const mark of $("content").querySelectorAll("mark")) mark.replaceWith(document.createTextNode(mark.textContent));
    $("content").normalize();
    matches = []; matchIndex = -1;
  }
  function highlight() {
    clearMarks();
    const query = $("find").value.trim();
    if (!query) { $("find-count").textContent = "0 matches"; return; }
    const pattern = new RegExp(query.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"), "giu");
    const walker = document.createTreeWalker($("content"), NodeFilter.SHOW_TEXT);
    const nodes = [];
    while (walker.nextNode()) nodes.push(walker.currentNode);
    let capped = false;
    for (const node of nodes) {
      if (matches.length >= 2000) { capped = true; break; }
      pattern.lastIndex = 0;
      const found = node.textContent.matchAll(pattern);
      const fragment = document.createDocumentFragment();
      let start = 0;
      for (const match of found) {
        if (matches.length >= 2000) { capped = true; break; }
        fragment.append(document.createTextNode(node.textContent.slice(start, match.index)));
        const mark = element("mark", match[0]);
        fragment.append(mark); matches.push(mark);
        start = match.index + match[0].length;
      }
      if (start) {
        fragment.append(document.createTextNode(node.textContent.slice(start)));
        node.replaceWith(fragment);
      }
    }
    $("find-count").textContent = `${matches.length}${capped ? "+" : ""} matches`;
    if (matches.length) { matchIndex = 0; matches[0].classList.add("current"); }
  }
  function moveMatch(direction) {
    if (!matches.length) return;
    matches[matchIndex]?.classList.remove("current");
    matchIndex = (matchIndex + direction + matches.length) % matches.length;
    matches[matchIndex].classList.add("current");
    matches[matchIndex].scrollIntoView({block: "center"});
    $("find-count").textContent = `${matchIndex + 1} of ${matches.length} matches`;
  }
  function openFind() { $("find-panel").hidden = false; $("find").focus(); }
  function closeFind() { $("find-panel").hidden = true; $("find").value = ""; clearMarks(); $("find-open").focus(); }
  async function openSaved() {
    try {
      saved = (await request("saved.list")).saved;
      renderSaved(); $("saved-dialog").showModal();
    } catch (failure) { error(failure.message); }
  }
  function renderSaved() {
    const list = $("saved-list"); list.replaceChildren();
    for (const item of saved) {
      const row = element("li");
      row.append(externalLink(item.url, item.title));
      const remove = element("button", "Remove");
      remove.setAttribute("aria-label", `Remove ${item.title}`);
      remove.addEventListener("click", async () => {
        try {
          saved = (await request("saved.remove", {url: item.url})).saved;
          renderSaved(); if (doc) bookmarkState();
        } catch (failure) { error(failure.message); }
      });
      row.append(remove); list.append(row);
    }
    if (!saved.length) list.append(element("li", "No saved pages yet."));
  }

  for (const button of document.querySelectorAll("[data-mode]")) {
    button.addEventListener("click", () => { void changePreferences({mode: button.dataset.mode}); window.scrollTo(0, 0); });
  }
  $("font-down").addEventListener("click", () => { void changePreferences({fontSize: preferences.fontSize - 1}); });
  $("font-up").addEventListener("click", () => { void changePreferences({fontSize: preferences.fontSize + 1}); });
  $("wrap").addEventListener("click", () => { void changePreferences({wrap: !preferences.wrap}); });
  $("theme").addEventListener("change", () => { void changePreferences({theme: $("theme").value}); });
  $("find-open").addEventListener("click", openFind);
  $("find-close").addEventListener("click", closeFind);
  $("find").addEventListener("input", highlight);
  $("find-next").addEventListener("click", () => moveMatch(1));
  $("find-prev").addEventListener("click", () => moveMatch(-1));
  $("saved-open").addEventListener("click", () => { void openSaved(); });
  $("saved-close").addEventListener("click", () => $("saved-dialog").close());
  $("save").addEventListener("click", async () => {
    try { saved = (await request("saved.toggle", {id})).saved; bookmarkState(); status($("save").getAttribute("aria-pressed") === "true" ? "Saved a bookmark to this page." : "Bookmark removed."); }
    catch (failure) { error(failure.message); }
  });
  $("refresh").addEventListener("click", async () => {
    $("refresh").disabled = true; clearError(); status("Refreshing from the source tab…");
    try { doc = (await request("refresh", {id})).document; render(); status("Reading copy refreshed."); }
    catch (failure) { error(failure.message); }
    finally { $("refresh").disabled = false; }
  });
  $("export").addEventListener("click", () => {
    const blob = new Blob([GopherDocument.plainText(doc, preferences.mode)], {type: "text/plain;charset=utf-8"});
    const url = URL.createObjectURL(blob), link = element("a");
    link.href = url;
    link.download = (doc.source.title.replace(/[^\p{L}\p{N}_-]+/gu, "-").slice(0, 80) || "page") + ".txt";
    document.body.append(link); link.click(); link.remove();
    setTimeout(() => URL.revokeObjectURL(url), 10000);
    status("Exported this view as plain text.");
  });
  $("native-open").addEventListener("click", async () => {
    $("native-open").disabled = true; clearError(); status("Saving this copy in AI-2 Gopher…");
    try {
      const result = await request("native.open", {id});
      status(`Saved locally and opened in AI-2 Gopher: ${result.url}. Manage copies in the app's Saved web pages library.`);
    } catch (failure) { error(failure.message); }
    finally { $("native-open").disabled = false; }
  });
  document.addEventListener("keydown", event => {
    if (event.key === "/" && !["INPUT", "SELECT", "TEXTAREA"].includes(document.activeElement.tagName) && doc) { event.preventDefault(); openFind(); }
    if (event.key === "Escape" && !$("find-panel").hidden) closeFind();
    if (event.key === "Enter" && document.activeElement === $("find")) { event.preventDefault(); moveMatch(event.shiftKey ? -1 : 1); }
  });
  async function init() {
    if (params.has("error")) { error(params.get("error")); return; }
    if (!id) { error("Open a web page and click Read this page as text in the extension toolbar."); return; }
    try {
      const data = await request("load", {id});
      doc = data.document; preferences = data.preferences; saved = data.saved;
      render(); status();
    } catch (failure) { error(failure.message); }
  }
  void init();
})();
