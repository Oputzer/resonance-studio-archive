// SoundCloud playlist -> zip. Local-only, zero npm dependencies.
// Needs `yt-dlp` and `ffmpeg` on PATH (brew install yt-dlp ffmpeg).
const http = require("http");
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const { spawn } = require("child_process");

const PORT = Number(process.env.PORT) || 4321;
const HOST = "127.0.0.1"; // never exposed to your network
const JOBS_DIR = path.join(__dirname, "jobs");
const JOB_TTL_MS = 60 * 60 * 1000; // delete finished jobs after 1 hour

// "best" = keep SoundCloud's original stream, no re-encode (truest quality).
// Everything else is converted by ffmpeg at its highest setting.
const FORMATS = {
  best: { label: "Original (no conversion)", args: ["-f", "bestaudio/best"], thumb: false },
  mp3: { label: "MP3 320", args: ["-x", "--audio-format", "mp3", "--audio-quality", "320K"], thumb: true },
  aac: { label: "AAC (m4a)", args: ["-x", "--audio-format", "m4a", "--audio-quality", "0"], thumb: true },
  wav: { label: "WAV", args: ["-x", "--audio-format", "wav"], thumb: false },
  flac: { label: "FLAC", args: ["-x", "--audio-format", "flac"], thumb: true },
};

const jobs = new Map();
fs.rmSync(JOBS_DIR, { recursive: true, force: true });
fs.mkdirSync(JOBS_DIR, { recursive: true });

function isSoundCloudUrl(raw) {
  try {
    const u = new URL(raw);
    return u.protocol === "https:" && /(^|\.)soundcloud\.com$|^on\.soundcloud\.com$/.test(u.hostname);
  } catch {
    return false;
  }
}

function safeName(s) {
  return (s || "soundcloud").replace(/[^\p{L}\p{N}\-_ ']+/gu, "").trim().slice(0, 80) || "soundcloud";
}

function startJob(url, format) {
  const id = crypto.randomBytes(8).toString("hex");
  const dir = path.join(JOBS_DIR, id);
  fs.mkdirSync(dir);
  const job = {
    id, dir, url, format,
    status: "running", // running | done | error | cancelled
    title: null, total: 0, current: 0, done: 0, failed: [], log: [],
    createdAt: Date.now(),
  };
  jobs.set(id, job);

  const args = [
    "--yes-playlist", "--ignore-errors", "--newline", "--no-overwrites",
    ...FORMATS[format].args,
    "--embed-metadata",
    ...(FORMATS[format].thumb ? ["--embed-thumbnail"] : []),
    "--no-simulate", // --print would otherwise skip the actual download
    "--print", "before_dl:ITEM\t%(playlist_index|1)s\t%(n_entries|1)s\t%(playlist_title|)s\t%(title)s",
    "--print", "after_move:SAVED\t%(filepath)s",
    "-o", "%(playlist_index|0)03d - %(uploader)s - %(title)s.%(ext)s",
    "-P", dir,
    url,
  ];
  const proc = spawn("yt-dlp", args);
  job.proc = proc;

  const onLine = (line) => {
    if (!line.trim()) return;
    let m;
    if ((m = line.match(/^ITEM\t(\d+)\t(\d+)\t([^\t]*)\t(.*)$/))) {
      job.current = +m[1]; job.total = +m[2];
      if (!job.title) job.title = m[3] || m[4];
      job.log.push(`Downloading: ${m[4]}`);
      return;
    }
    if ((m = line.match(/^SAVED\t/))) { job.done++; return; }
    if (/^ERROR:/.test(line)) job.failed.push(line.replace(/^ERROR:\s*/, "").slice(0, 300));
    job.log.push(line);
    if (job.log.length > 200) job.log.shift();
  };
  const splitter = (stream) => {
    let buf = "";
    stream.on("data", (d) => {
      buf += d.toString();
      const lines = buf.split(/\r?\n/);
      buf = lines.pop();
      lines.forEach(onLine);
    });
    stream.on("end", () => buf && onLine(buf));
  };
  splitter(proc.stdout);
  splitter(proc.stderr);

  proc.on("error", (err) => {
    job.status = "error";
    job.failed.push(err.code === "ENOENT" ? "yt-dlp is not installed (brew install yt-dlp ffmpeg)" : err.message);
  });
  proc.on("close", () => {
    if (job.status !== "running") return;
    if (job.total === 0 && job.done > 0) job.total = job.done; // single track URL
    job.status = job.done > 0 ? "done" : "error";
    if (job.status === "error" && !job.failed.length) job.failed.push("No tracks could be downloaded. Is the playlist public?");
    job.finishedAt = Date.now();
  });
  return job;
}

function publicJob(j) {
  return {
    id: j.id, status: j.status, title: j.title, format: j.format,
    total: j.total, current: j.current, done: j.done,
    failed: j.failed, lastLine: j.log[j.log.length - 1] || "",
  };
}

function streamZip(job, res) {
  const files = fs.readdirSync(job.dir).filter((f) => !f.startsWith("."));
  if (!files.length) { res.writeHead(404); return res.end("No files"); }
  const name = `${safeName(job.title)} (${job.format}).zip`;
  // Headers must be plain ASCII: ASCII fallback + full UTF-8 name for browsers.
  const ascii = name.normalize("NFKD").replace(/[^\x20-\x7e]/g, "").replace(/"/g, "") || "playlist.zip";
  res.writeHead(200, {
    "Content-Type": "application/zip",
    "Content-Disposition": `attachment; filename="${ascii}"; filename*=UTF-8''${encodeURIComponent(name)}`,
  });
  // Python's zipfile flags names as UTF-8 so accents survive on Windows too.
  // ZIP_STORED: audio is already compressed / WAV barely shrinks.
  const py = "import sys,zipfile\n" +
    "z=zipfile.ZipFile(sys.stdout.buffer,'w',zipfile.ZIP_STORED,allowZip64=True)\n" +
    "[z.write(f) for f in sys.argv[1:]]\nz.close()";
  const zip = spawn("python3", ["-I", "-c", py, ...files], { cwd: job.dir });
  zip.stdout.pipe(res);
  zip.on("error", () => res.end());
}

function sendJson(res, code, obj) {
  res.writeHead(code, { "Content-Type": "application/json" });
  res.end(JSON.stringify(obj));
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let b = "";
    req.on("data", (d) => { b += d; if (b.length > 1e5) req.destroy(); });
    req.on("end", () => { try { resolve(JSON.parse(b || "{}")); } catch (e) { reject(e); } });
  });
}

const server = http.createServer(async (req, res) => {
  try {
    await handle(req, res);
  } catch (err) {
    console.error(err);
    if (!res.headersSent) sendJson(res, 500, { error: "Server error: " + err.message });
    else res.end();
  }
});

async function handle(req, res) {
  const { pathname } = new URL(req.url, "http://x");

  if (req.method === "GET" && (pathname === "/" || pathname === "/index.html")) {
    res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
    return fs.createReadStream(path.join(__dirname, "public", "index.html")).pipe(res);
  }

  if (req.method === "GET" && pathname === "/api/formats") {
    return sendJson(res, 200, Object.entries(FORMATS).map(([k, v]) => ({ id: k, label: v.label })));
  }

  if (req.method === "POST" && pathname === "/api/jobs") {
    let body;
    try { body = await readBody(req); } catch { return sendJson(res, 400, { error: "Bad JSON" }); }
    const url = String(body.url || "").trim();
    const format = String(body.format || "best");
    if (!isSoundCloudUrl(url)) return sendJson(res, 400, { error: "That doesn't look like a SoundCloud link." });
    if (!FORMATS[format]) return sendJson(res, 400, { error: "Unknown format." });
    return sendJson(res, 201, publicJob(startJob(url, format)));
  }

  let m = pathname.match(/^\/api\/jobs\/([a-f0-9]{16})(\/download|\/cancel)?$/);
  if (m) {
    const job = jobs.get(m[1]);
    if (!job) return sendJson(res, 404, { error: "Job not found (it may have expired)." });
    if (!m[2] && req.method === "GET") return sendJson(res, 200, publicJob(job));
    if (m[2] === "/download" && req.method === "GET") {
      if (job.status !== "done") return sendJson(res, 409, { error: "Not finished yet." });
      return streamZip(job, res);
    }
    if (m[2] === "/cancel" && req.method === "POST") {
      if (job.status === "running") { job.status = "cancelled"; job.proc?.kill("SIGTERM"); }
      return sendJson(res, 200, publicJob(job));
    }
  }

  sendJson(res, 404, { error: "Not found" });
}

// Housekeeping: delete old job folders.
setInterval(() => {
  const now = Date.now();
  for (const [id, j] of jobs) {
    if (j.status !== "running" && now - (j.finishedAt || j.createdAt) > JOB_TTL_MS) {
      fs.rmSync(j.dir, { recursive: true, force: true });
      jobs.delete(id);
    }
  }
}, 5 * 60 * 1000).unref();

server.listen(PORT, HOST, () => console.log(`SoundCloud Zip running at http://localhost:${PORT}`));
