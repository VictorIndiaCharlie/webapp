const searchForm = document.getElementById("search-form");
const wordInput  = document.getElementById("word-input");
const statusEl   = document.getElementById("status");
const resultsEl  = document.getElementById("results");
const randomBtn  = document.getElementById("random-btn");

const addForm    = document.getElementById("add-form");
const newWord    = document.getElementById("new-word");
const addStatus  = document.getElementById("add-status");

const metricLastWord = document.getElementById("metric-last-word");
const metricCount    = document.getElementById("metric-count");
const metricStatus   = document.getElementById("metric-status");

const dictList     = document.getElementById("dictionary-list");
const refreshDictBtn = document.getElementById("refresh-dict-btn");

async function safeFetch(url, options = {}) {
  const res = await fetch(url, options);
  const ct = res.headers.get("content-type") || "";
  if (!ct.includes("application/json")) throw new Error(`Server returned HTTP ${res.status}`);
  const data = await res.json();
  if (!res.ok) throw new Error(data.detail || "Request failed");
  return data;
}

const escapeHtml = (s) => String(s).replace(/[&<>"']/g,
  (c) => ({ "&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;" }[c]));

function wordTag(w) {
  const cls = w.invented ? "anagram-tag invented-tag" : "anagram-tag";
  const label = w.invented ? `~${escapeHtml(w.word)}` : escapeHtml(w.word);
  const title = w.invented ? "Invented pseudo-word" : "Real word";
  return `<span class="${cls}" title="${title}">${label}</span>`;
}

function renderSection(title, items, emptyText, renderFn) {
  if (!items.length) {
    return `<div class="result-section">
      <div class="result-header"><h3>${title}</h3><span class="count">0</span></div>
      <p class="empty-state">${emptyText}</p>
    </div>`;
  }
  const body = items.map(renderFn).join("");
  return `<div class="result-section">
    <div class="result-header"><h3>${title}</h3><span class="count">${items.length}</span></div>
    <div class="anagram-tags">${body}</div>
  </div>`;
}

async function performSearch(word) {
  // RESET the counter
  statusEl.textContent = "Searching…";
  resultsEl.innerHTML  = "";
  metricLastWord.textContent = word;          // preserves spaces as typed
  metricCount.textContent    = "0";           // reset to zero
  metricStatus.textContent   = "Searching…";

  try {
    const data = await safeFetch(
      `/api/anagrams?word=${encodeURIComponent(word)}&max_words=2&invented=true`
    );
    const { exact, sub_anagrams, phrases, stats } = data;

    // Update counter to the total from THIS search
    metricCount.textContent = String(stats.total);
    metricStatus.textContent =
      `${stats.exact_count} exact · ${stats.sub_count} sub · ${stats.phrase_count} phrases ` +
      `(${stats.time_ms} ms)`;

    statusEl.textContent =
      `Searched "${data.input}" ${data.input_word_count > 1 ? "(multi-word)" : ""} — ` +
      `${stats.total} anagrams found`;

    resultsEl.innerHTML = [
      renderSection("Exact Anagrams", exact, "No exact matches.", wordTag),
      renderSection("Sub-Anagrams",   sub_anagrams, "No sub-anagrams.", wordTag),
      renderSection("Phrases",        phrases, "No phrases.",
        (p) => `<span class="anagram-tag">${escapeHtml(p.join(" "))}</span>`),
    ].join("");
  } catch (err) {
    statusEl.textContent = `Error: ${err.message}`;
    metricStatus.textContent = "Error";
  }
}

async function loadDictionary() {
  dictList.innerHTML = `<span class="empty-state">Loading…</span>`;
  try {
    const data = await safeFetch("/api/words/all");
    if (!data.count) {
      dictList.innerHTML = `<span class="empty-state">Dictionary is empty.</span>`;
      return;
    }
    dictList.innerHTML = data.words
      .map((w) => `<span class="anagram-tag">${escapeHtml(w)}</span>`)
      .join("");
  } catch (err) {
    dictList.innerHTML = `<span class="empty-state">Error: ${escapeHtml(err.message)}</span>`;
  }
}

// ---- Wiring ----
searchForm.addEventListener("submit", (e) => {
  e.preventDefault();
  const w = wordInput.value.trim();
  if (!w) return;
  performSearch(w);
  loadDictionary();   // refresh DB list alongside search
});

randomBtn.addEventListener("click", async () => {
  try {
    randomBtn.disabled = true;
    const original = randomBtn.textContent;
    randomBtn.textContent = "Loading…";
    const { word } = await safeFetch("/api/words/random");
    wordInput.value = word;
    await performSearch(word);
    await loadDictionary();
    randomBtn.textContent = original;
  } catch (err) {
    statusEl.textContent = `Error: ${err.message}`;
  } finally {
    randomBtn.disabled = false;
  }
});

addForm.addEventListener("submit", async (e) => {
  e.preventDefault();
  const w = newWord.value.trim();
  if (!w) return;
  addStatus.textContent = "Adding…";
  try {
    const data = await safeFetch("/api/words", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ word: w }),
    });
    addStatus.textContent = data.message
      ? `"${data.word}" ${data.message}`
      : `Added "${data.word}" — search results refresh on next query`;
    newWord.value = "";
    await loadDictionary();
  } catch (err) {
    addStatus.textContent = `Error: ${err.message}`;
  }
});

refreshDictBtn.addEventListener("click", loadDictionary);

// Initial load
loadDictionary();
