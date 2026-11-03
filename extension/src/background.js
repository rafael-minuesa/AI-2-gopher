/* A Chromium service worker, or a Firefox nonpersistent background script. */
(() => {
  if (typeof importScripts === "function") importScripts("core.js");
  const api = globalThis.browser || globalThis.chrome;
  const PREFIX = "snapshot:";
  const busy = new Set();
  let queue = Promise.resolve();
  function serialized(action) {
    const result = queue.then(action);
    queue = result.catch(() => {});
    return result;
  }
  const errorText = error => error?.message || "Could not read this page. Try again from the source tab.";

  async function capture(tabId) {
    await api.scripting.executeScript({target: {tabId}, files: ["vendor/Readability.js", "core.js", "extract.js"]});
    const results = await api.scripting.executeScript({target: {tabId}, func: () => globalThis.GopherReader.capture()});
    const doc = results.find(result => result.frameId === 0)?.result;
    if (!doc) throw new Error("This page cannot be read by the extension. Open an ordinary web page and try again.");
    return GopherDocument.validate(doc);
  }
  async function store(entry) {
    return serialized(async () => {
      const data = await api.storage.session.get(null);
      const snapshots = Object.entries(data).filter(([key]) => key.startsWith(PREFIX));
      let bytes = new TextEncoder().encode(JSON.stringify(snapshots)).length;
      const size = new TextEncoder().encode(JSON.stringify(entry)).length;
      // Never evict a reading tab silently. Closing old copies releases space.
      const previous = data[PREFIX + entry.id];
      if (previous) bytes -= new TextEncoder().encode(JSON.stringify(previous)).length;
      if (bytes + size > 8000000) throw new Error("Several large reading copies are open. Close one and try again.");
      await api.storage.session.set({[PREFIX + entry.id]: entry});
    });
  }
  async function showError(message) {
    const url = new URL(api.runtime.getURL("reader.html"));
    url.searchParams.set("error", message.slice(0, 800));
    await api.tabs.create({url: url.href});
  }
  async function convertTab(tab) {
    if (!tab?.id || busy.has(tab.id)) return;
    busy.add(tab.id);
    try {
      const url = GopherDocument.safeUrl(tab.url);
      if (!url || !/^https?:/.test(url)) throw new Error("This browser page cannot be converted. Open a normal website and click Read this page as text.");
      await api.action.setBadgeText({tabId: tab.id, text: "…"});
      const document = await capture(tab.id);
      const entry = {id: crypto.randomUUID(), sourceTabId: tab.id, readerTabId: null, document};
      await store(entry);
      try {
        const reader = await api.tabs.create({url: api.runtime.getURL(`reader.html?id=${entry.id}`), openerTabId: tab.id});
        entry.readerTabId = reader.id;
        await store(entry);
      } catch (error) {
        await api.storage.session.remove(PREFIX + entry.id);
        throw error;
      }
    } catch (error) {
      await showError(/Cannot access|Missing host permission|not allowed|permission/i.test(errorText(error))
        ? "The browser does not allow access to this page. Open a normal website and invoke the extension there."
        : errorText(error));
    } finally {
      busy.delete(tab.id);
      await api.action.setBadgeText({tabId: tab.id, text: ""}).catch(() => {});
    }
  }
  async function entryFor(id) {
    if (typeof id !== "string" || !/^[a-f0-9-]{36}$/.test(id)) throw new Error("No reading copy was selected.");
    const entry = (await api.storage.session.get(PREFIX + id))[PREFIX + id];
    if (!entry) throw new Error("This reading copy has expired. Open the source page and click the extension to create a new copy.");
    return entry;
  }
  async function savedPages() {
    const data = (await api.storage.local.get("savedPages")).savedPages;
    if (!Array.isArray(data)) return [];
    return data.filter(item => GopherDocument.safeUrl(item?.url) && typeof item.title === "string").slice(0, 200);
  }
  async function handle(message) {
    switch (message.type) {
      case "native.open": {
        const entry = await entryFor(message.id);
        const doc = GopherDocument.validate(entry.document);
        let response;
        try {
          response = await api.runtime.sendNativeMessage("org.gopherclient.reader", {
            protocolVersion: 1, action: "import", id: entry.id,
            page: {url: doc.source.url, title: doc.source.title,
              capturedAt: doc.source.capturedAt || "",
              article: GopherDocument.plainText(doc, "article"),
              page: GopherDocument.plainText(doc, "page"), links: doc.links}
          });
        } catch {
          throw new Error("Could not connect to AI-2 Gopher. Install the Linux app package and run its install.sh to enable browser integration. Sandboxed browser packages may need additional native messaging setup.");
        }
        if (!response?.ok) throw new Error(response?.error || "The native app could not save this page. Try again.");
        if (typeof response.url !== "string" || !/^gopher:\/\/127\.0\.0\.1:7070\/1\/page\/[a-f0-9-]{36}$/.test(response.url)) {
          throw new Error("The native companion returned an invalid page address. Update the app and extension together.");
        }
        return {url: response.url};
      }
      case "load": {
        const entry = await entryFor(message.id);
        const data = await api.storage.local.get("preferences");
        return {document: entry.document, preferences: GopherDocument.prefs(data.preferences), saved: await savedPages()};
      }
      case "refresh": {
        const entry = await entryFor(message.id);
        let tab;
        try { tab = await api.tabs.get(entry.sourceTabId); }
        catch { throw new Error("The source tab is closed. Open the original page and invoke the extension again."); }
        if (tab.url?.split("#")[0] !== entry.document.source.url.split("#")[0]) {
          throw new Error("The source tab has changed. Invoke the extension on that page to make a new reading copy.");
        }
        entry.document = await capture(tab.id);
        await store(entry);
        return {document: entry.document};
      }
      case "preferences": return serialized(async () => {
        const preferences = GopherDocument.prefs(message.value);
        await api.storage.local.set({preferences});
        return {preferences};
      });
      case "saved.list": return {saved: await savedPages()};
      case "saved.toggle": return serialized(async () => {
        const entry = await entryFor(message.id);
        const saved = await savedPages();
        const url = entry.document.source.url;
        const index = saved.findIndex(item => item.url === url);
        if (index >= 0) saved.splice(index, 1);
        else {
          if (saved.length >= 200) throw new Error("You have 200 saved pages. Remove one before saving another.");
          saved.unshift({url, title: entry.document.source.title, savedAt: new Date().toISOString()});
        }
        await api.storage.local.set({savedPages: saved});
        return {saved};
      });
      case "saved.remove": return serialized(async () => {
        const saved = (await savedPages()).filter(item => item.url !== message.url);
        await api.storage.local.set({savedPages: saved});
        return {saved};
      });
      default: throw new Error("This action is not supported.");
    }
  }

  api.action.onClicked.addListener(tab => { void convertTab(tab).catch(() => {}); });
  api.runtime.onMessage.addListener((message, sender, respond) => {
    // No messages from web pages or content scripts are accepted.
    if (sender.id !== api.runtime.id || sender.url?.split("?")[0] !== api.runtime.getURL("reader.html")) return false;
    handle(message).then(data => respond({ok: true, ...data}), error => respond({ok: false, error: errorText(error)}));
    return true;
  });
  api.tabs.onRemoved.addListener(tabId => {
    void serialized(async () => {
      const data = await api.storage.session.get(null);
      const keys = Object.entries(data).filter(([key, entry]) => key.startsWith(PREFIX) && entry.readerTabId === tabId).map(([key]) => key);
      if (keys.length) await api.storage.session.remove(keys);
    }).catch(() => {});
  });
})();
