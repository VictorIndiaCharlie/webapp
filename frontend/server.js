const express = require("express");
const path = require("path");

const app = express();
const PORT = process.env.PORT || 3000;
const BACKEND_URL = process.env.BACKEND_URL || "http://backend:8000";

app.use(express.json());

// --- Generic proxy for /api/* -> backend ---
app.use("/api", async (req, res) => {
  try {
    const target = `${BACKEND_URL}${req.originalUrl}`;
    const opts = {
      method: req.method,
      headers: { "Content-Type": "application/json" },
    };
    if (req.method !== "GET" && req.method !== "HEAD") {
      opts.body = JSON.stringify(req.body ?? {});
    }
    const upstream = await fetch(target, opts);
    const body = await upstream.text();
    res.status(upstream.status);
    const ct = upstream.headers.get("content-type");
    if (ct) res.set("Content-Type", ct);
    res.send(body);
  } catch (err) {
    console.error("Proxy error:", err);
    res.status(502).json({ detail: `backend unreachable: ${err.message}` });
  }
});

// --- Static files ---
app.use(express.static(path.join(__dirname, "public")));

// SPA fallback
app.get("*", (req, res) => {
  res.sendFile(path.join(__dirname, "public", "index.html"));
});

app.listen(PORT, () => {
  console.log(`Frontend listening on http://0.0.0.0:${PORT}`);
  console.log(`Proxying /api -> ${BACKEND_URL}`);
});