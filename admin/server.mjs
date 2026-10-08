#!/usr/bin/env node
// OnAir local server.
//   node admin/server.mjs     → agenda at http://localhost:4242/, admin at http://localhost:4242/admin/
// Serves the public pages and agenda.json, the admin page, reads and writes the agenda, and publishes it
// (git commit + push) so a static host such as GitHub Pages picks it up. No dependencies beyond Node itself.
// Listens on all interfaces so screens on the local network can open the public pages and agenda.json
// (read-only). The admin page and everything under /api/ answer only to this machine.
//
// Environment: PORT (default 4242), HOST (default 0.0.0.0; 127.0.0.1 keeps it on this machine),
// AGENDA_FILE (default ../agenda.json), BRANCH (default: the checked-out branch), REMOTE (default origin).

import { createServer } from "node:http";
import { readFile, writeFile, rename } from "node:fs/promises";
import { execFile } from "node:child_process";
import { fileURLToPath } from "node:url";
import { dirname, join, resolve, relative } from "node:path";
import { networkInterfaces } from "node:os";

const PORT = Number(process.env.PORT) || 4242;
const HOST = process.env.HOST || "0.0.0.0";
const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = join(HERE, "..");
const AGENDA = process.env.AGENDA_FILE ? resolve(process.env.AGENDA_FILE) : join(REPO, "agenda.json");
const REMOTE = process.env.REMOTE || "origin";
// Public, read-only files: URL path → [file in the repo, content type].
const PUBLIC = {
  "/": ["index.html", "text/html"],
  "/index.html": ["index.html", "text/html"],
  "/stage.html": ["stage.html", "text/html"],
  "/timer.html": ["timer.html", "text/html"],
  "/vendor/qrcode.mjs": ["vendor/qrcode.mjs", "text/javascript"],
};

const branch = async () => process.env.BRANCH || await git("rev-parse", "--abbrev-ref", "HEAD");
const git = (...args) => new Promise((resolve, reject) =>
  execFile("git", args, { cwd: REPO, timeout: 60000 }, (err, stdout, stderr) =>
    err ? reject(new Error((stderr || stdout || err.message).trim())) : resolve((stdout + stderr).trim())));

// Shape check: enough to stop a broken file from reaching the live page.
function validate(a) {
  const errs = [];
  if (!a || typeof a !== "object") return ["Agenda must be an object."];
  if (!a.event?.date || !/^\d{4}-\d{2}-\d{2}$/.test(a.event.date)) errs.push("event.date must be YYYY-MM-DD.");
  if (!/^[+-]\d{2}:\d{2}$/.test(a.event?.utcOffset || "")) errs.push("event.utcOffset must look like +03:00.");
  if (!Number.isFinite(a.timing?.talkMinutes) || !Number.isFinite(a.timing?.qaMinutes)) errs.push("timing.talkMinutes and timing.qaMinutes are required.");
  if (!Array.isArray(a.sessions) || !a.sessions.length) errs.push("sessions must be a non-empty list.");
  (a.sessions || []).forEach((s, i) => {
    if (!/^\d{2}:\d{2}$/.test(s.start || "")) errs.push(`Session ${i + 1}: start must be HH:MM.`);
    if (!Number.isFinite(s.dur) || s.dur < 1) errs.push(`Session ${i + 1}: dur must be a positive number.`);
    if (!["talk", "break", "keynote"].includes(s.kind)) errs.push(`Session ${i + 1}: kind must be talk, break or keynote.`);
    if (!s.title) errs.push(`Session ${i + 1}: title is required.`);
    if (s.qa !== undefined && (!Number.isFinite(s.qa) || s.qa < 0 || s.qa > s.dur)) errs.push(`Session ${i + 1}: qa must be between 0 and dur.`);
  });
  return errs;
}

const send = (res, code, body, type = "application/json; charset=utf-8", extra = {}) => {
  res.writeHead(code, { "Content-Type": type, "Cache-Control": "no-store", ...extra });
  res.end(typeof body === "string" || Buffer.isBuffer(body) ? body : JSON.stringify(body));
};
const readBody = req => new Promise((resolve, reject) => {
  let data = "";
  req.on("data", c => { data += c; if (data.length > 2e6) { reject(new Error("Body too large")); req.destroy(); } });
  req.on("end", () => resolve(data));
  req.on("error", reject);
});

let publishing = Promise.resolve();

const LOOPBACK = new Set(["127.0.0.1", "::1", "::ffff:127.0.0.1"]);

const server = createServer(async (req, res) => {
  const url = new URL(req.url, "http://localhost");
  const isPublic = req.method === "GET" && (url.pathname in PUBLIC || url.pathname === "/agenda.json");
  if (!isPublic) {
    // Admin page and API: this machine only, addressed by a local name (blocks DNS-rebinding tricks).
    const host = (req.headers.host || "").replace(/:\d+$/, "");
    if (!LOOPBACK.has(req.socket.remoteAddress) || !["localhost", "127.0.0.1", "[::1]"].includes(host)) {
      return send(res, 403, { error: "The agenda admin is only available on the machine running it." });
    }
    // Writes need a custom header: browsers won't send it cross-site without a CORS preflight, which we never grant.
    if (req.method !== "GET" && req.headers["x-agenda-admin"] !== "1") return send(res, 403, { error: "Missing admin header" });
  }

  try {
    // Public pages; served from here they load this server's agenda.json
    if (isPublic && url.pathname in PUBLIC) {
      const [file, type] = PUBLIC[url.pathname];
      return send(res, 200, await readFile(join(REPO, file)), `${type}; charset=utf-8`);
    }
    if (req.method === "GET" && url.pathname === "/admin") return send(res, 301, "", "text/plain", { Location: "/admin/" });
    if (req.method === "GET" && (url.pathname === "/admin/" || url.pathname === "/admin/index.html")) {
      return send(res, 200, await readFile(join(HERE, "index.html")), "text/html; charset=utf-8");
    }
    if (req.method === "GET" && (url.pathname === "/agenda.json" || url.pathname === "/api/agenda")) {
      return send(res, 200, await readFile(AGENDA, "utf8"));
    }
    if (req.method === "PUT" && url.pathname === "/api/agenda") {
      const agenda = JSON.parse(await readBody(req));
      // The admin page never edits links (Slido, livestream), so keep the ones on disk. An admin tab left open
      // across a link change would otherwise write its stale links back.
      try { agenda.links = JSON.parse(await readFile(AGENDA, "utf8")).links ?? agenda.links; } catch (e) {}
      const errs = validate(agenda);
      if (errs.length) return send(res, 422, { error: errs.join(" ") });
      const tmp = AGENDA + ".tmp";
      await writeFile(tmp, JSON.stringify(agenda, null, 2) + "\n");
      await rename(tmp, AGENDA); // atomic: the file is never half-written
      return send(res, 200, { ok: true, savedAt: new Date().toISOString() });
    }
    if (req.method === "POST" && url.pathname === "/api/publish") {
      const { message } = JSON.parse((await readBody(req)) || "{}");
      // Serialize publishes so two quick clicks don't race on git.
      const run = publishing.then(async () => {
        const br = await branch().catch(() => { throw new Error("Publishing needs a git repository with a remote (see README)."); });
        const log = [], file = relative(REPO, AGENDA);
        if (file.startsWith("..")) throw new Error("Publishing only works for an agenda file inside this repository.");
        const remotes = await git("remote");
        if (!remotes.split("\n").includes(REMOTE)) throw new Error(`No git remote "${REMOTE}" to publish to. Add one, or set REMOTE.`);
        const changed = await git("status", "--porcelain", "--", file);
        if (changed) {
          await git("add", file);
          log.push(await git("commit", "-m", `Agenda: ${String(message || "update").slice(0, 120)}`, "--", file));
        }
        log.push(await git("pull", "--rebase", "--autostash", REMOTE, br));
        log.push(await git("push", REMOTE, `HEAD:${br}`));
        return { ok: true, committed: !!changed, log: log.filter(Boolean).join("\n") };
      });
      publishing = run.catch(() => {});
      return send(res, 200, await run);
    }
    if (req.method === "GET" && url.pathname === "/api/status") {
      const br = await branch().catch(() => null);
      if (!br) return send(res, 200, { git: false });
      const ahead = await git("rev-list", "--count", `${REMOTE}/${br}..HEAD`).catch(() => "?");
      const dirty = !!(await git("status", "--porcelain", "--", relative(REPO, AGENDA)).catch(() => ""));
      return send(res, 200, { branch: br, unpushedCommits: ahead, agendaChanged: dirty });
    }
    send(res, 404, { error: "Not found" });
  } catch (e) {
    send(res, 500, { error: e.message });
  }
});

server.listen(PORT, HOST, () => {
  // Addresses other devices on the network can use (only when listening beyond loopback).
  const lan = HOST === "127.0.0.1" || HOST === "localhost" ? [] : Object.values(networkInterfaces()).flat()
    .filter(i => i && i.family === "IPv4" && !i.internal).map(i => i.address);
  const base = [`localhost:${PORT}`, ...lan.map(a => `${a}:${PORT}`)];
  console.log(`OnAir admin:   http://localhost:${PORT}/admin/   (this machine only)`);
  for (const [label, page] of [["Live agenda:  ", ""], ["Stage screen: ", "stage.html"], ["Speaker timer:", "timer.html"]]) {
    base.forEach((b, i) => console.log(`${i ? " ".repeat(14) : label} http://${b}/${page}`));
  }
  console.log(`Editing:       ${AGENDA}`);
});
