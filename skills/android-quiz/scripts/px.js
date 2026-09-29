#!/usr/bin/env node
// Pixel tools for raw Android screencaps.
//
// A raw screencap is: int32 width, int32 height, int32 format, [int32 colorspace],
// then RGBA rows. The data offset is derived from the file size, so the optional
// header field does not matter.
//
//   RAW=/path/to/frame.raw node px.js size
//   RAW=... node px.js probe x,y [x,y...]
//   RAW=... node px.js sel   x,y [x,y...]      # SELECTED / not-selected
//   RAW=... node px.js find  <bluish|dark|red> x0,y0,x1,y1 [minPixels]
//   RAW=... node px.js blocks <r,g,b> [tol] [minArea]
//
// Why: reading a screenshot with vision costs seconds and the displayed image is
// scaled by an unknown factor, so converting "what I see" into tap coordinates is
// unreliable (measured: 137 px off in one real case). These helpers give exact
// coordinates and a one-call pass/fail check instead.
const fs = require("fs");

// Commands that need the RAW frame load it eagerly; sweep/selected read their own
// directory of frames and must work without RAW being set.
const file = process.env.RAW || null;
let buf = null, w = 0, h = 0, dataOff = 0;
const needRaw = () => {
  if (!file) {
    console.error("RAW=<frame.raw> is required for this command");
    process.exit(2);
  }
  if (!buf) {
    buf = fs.readFileSync(file);
    w = buf.readInt32LE(0);
    h = buf.readInt32LE(4);
    dataOff = buf.length - w * h * 4;
    if (dataOff < 12) {
      console.error("not a raw screencap: " + file);
      process.exit(2);
    }
  }
};
if (file) needRaw();

const cmd = process.argv[2] || "size";
const px = (x, y) => {
  const i = dataOff + (y * w + x) * 4;
  return [buf[i], buf[i + 1], buf[i + 2]];
};

if (cmd === "size") {
  needRaw();
  console.log(w + "x" + h);
  process.exit(0);
}

if (cmd === "probe") {
  needRaw();
  for (const arg of process.argv.slice(3)) {
    const [x, y] = arg.split(",").map(Number);
    console.log(`${x},${y} = ${px(x, y).join(",")}`);
  }
  process.exit(0);
}

if (cmd === "sel") {
  needRaw();
  // Many Android/web UIs tint the selected option light blue (e.g. 233,239,252)
  // while unselected ones stay neutral grey (e.g. 242,242,242).
  for (const arg of process.argv.slice(3)) {
    const [x, y] = arg.split(",").map(Number);
    const [r, g, b] = px(x, y);
    console.log(`${x},${y} = ${r},${g},${b} -> ` +
      `${b - r > 8 ? "SELECTED" : "not-selected"}`);
  }
  process.exit(0);
}

if (cmd === "find") {
  needRaw();
  const mode = process.argv[3];
  const [x0, y0, x1, y1] = (process.argv[4] || `0,0,${w},${h}`).split(",").map(Number);
  const minPixels = Number(process.argv[5] || 40);
  const hit = (r, g, b) => {
    if (mode === "bluish") return b - r > 25 && b > 110 && r < 170;
    if (mode === "red") return r - g > 30 && r > 80 && b < 160;
    if (mode === "dark") return Math.max(r, g, b) < 120;
    return false;
  };
  let ax = Infinity, ay = Infinity, bx = -1, by = -1, n = 0;
  for (let y = Math.max(0, y0); y < Math.min(h, y1); y++) {
    for (let x = Math.max(0, x0); x < Math.min(w, x1); x++) {
      const [r, g, b] = px(x, y);
      if (!hit(r, g, b)) continue;
      n++;
      if (x < ax) ax = x;
      if (x > bx) bx = x;
      if (y < ay) ay = y;
      if (y > by) by = y;
    }
  }
  if (n < minPixels) {
    console.log(`NONE (mode=${mode} region=${x0},${y0},${x1},${y1} pixels=${n})`);
    process.exit(1);
  }
  console.log(`bbox=[${ax},${ay}][${bx},${by}] ` +
    `center=(${((ax + bx) / 2) | 0},${((ay + by) / 2) | 0}) pixels=${n}`);
  process.exit(0);
}

if (cmd === "blocks") {
  needRaw();
  const [r, g, b] = (process.argv[3] || "242,242,242").split(",").map(Number);
  const tol = Number(process.argv[4] || 8);
  const minArea = Number(process.argv[5] || 1500);
  const mask = new Uint8Array(w * h);
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const [pr, pg, pb] = px(x, y);
      if (Math.abs(pr - r) <= tol && Math.abs(pg - g) <= tol &&
          Math.abs(pb - b) <= tol) mask[y * w + x] = 1;
    }
  }
  const seen = new Uint8Array(w * h);
  const stack = [];
  const out = [];
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const idx = y * w + x;
      if (!mask[idx] || seen[idx]) continue;
      let ax = x, bx = x, ay = y, by = y, area = 0;
      stack.length = 0; stack.push(idx); seen[idx] = 1;
      while (stack.length) {
        const c = stack.pop();
        const cy = (c / w) | 0;
        const cx = c - cy * w;
        area++;
        if (cx < ax) ax = cx; if (cx > bx) bx = cx;
        if (cy < ay) ay = cy; if (cy > by) by = cy;
        if (cx > 0 && mask[c - 1] && !seen[c - 1]) { seen[c - 1] = 1; stack.push(c - 1); }
        if (cx < w - 1 && mask[c + 1] && !seen[c + 1]) { seen[c + 1] = 1; stack.push(c + 1); }
        if (cy > 0 && mask[c - w] && !seen[c - w]) { seen[c - w] = 1; stack.push(c - w); }
        if (cy < h - 1 && mask[c + w] && !seen[c + w]) { seen[c + w] = 1; stack.push(c + w); }
      }
      if (area >= minArea) out.push({ ax, ay, bx, by, area });
    }
  }
  out.sort((p, q) => p.ay - q.ay || p.ax - q.ax);
  for (const c of out) {
    console.log(`[${c.ax},${c.ay}][${c.bx},${c.by}] ` +
      `center=(${((c.ax + c.bx) / 2) | 0},${((c.ay + c.by) / 2) | 0}) ` +
      `size=${c.bx - c.ax + 1}x${c.by - c.ay + 1} area=${c.area}`);
  }
  process.exit(0);
}

// ---------------------------------------------------------------------------
// Layout learning: option boxes and question numbers do NOT move between
// questions, so scanning for them on every pass is wasted work. Learn the row
// structure once, then only *re-check* it (a single-row scan, ~50 ms) and tap
// the remembered centres.
//
// A "row" is described by the y of a horizontal line through the controls: the
// boxes show up as runs of non-white pixels with a stable count, order and
// pitch. That signature survives the selected/unselected colour change, which
// is exactly what a colour-only check cannot do.

const rowRunsWith = (at, W, y, whiteTol, minW) => {
  const runs = [];
  let start = -1;
  for (let x = 0; x < W; x++) {
    const [r, g, b] = at(x, y);
    const nonWhite = Math.max(255 - r, 255 - g, 255 - b) > whiteTol;
    if (nonWhite) {
      if (start < 0) start = x;
    } else if (start >= 0) {
      if (x - start >= minW) runs.push({ x0: start, x1: x - 1, cx: ((start + x - 1) / 2) | 0 });
      start = -1;
    }
  }
  if (start >= 0 && W - start >= minW) runs.push({ x0: start, x1: W - 1, cx: ((start + W - 1) / 2) | 0 });
  return runs;
};
const rowRuns = (y, whiteTol, minW) => rowRunsWith(px, w, y, whiteTol, minW);

// A "run" is a control-width blob. 30 px happened to be right on a 1220-wide
// screen, so derive the threshold from the frame width instead of hard-coding
// it: a 720-wide phone would otherwise filter out every option box, and a
// tablet would merge them.
const defaultMinRun = (W) => Math.max(10, Math.round(W / 40));
const minRunFor = (W, forced) =>
  Number(forced || process.env.MIN_RUN || defaultMinRun(W));

if (cmd === "learn-rows") {
  needRaw();
  // RAW=... node px.js learn-rows profile.json 1293:options 1413:options2 973:tabs
  const outFile = process.argv[3];
  const specs = process.argv.slice(4);
  if (!outFile || !specs.length) {
    console.error("usage: learn-rows <profile.json> <y:name> [y:name ...]");
    process.exit(1);
  }
  const whiteTol = Number(process.env.WHITE_TOL || 12);
  const minW = minRunFor(w);
  const profile = {
    learned_from: file,
    size: w + "x" + h,
    white_tol: whiteTol,
    min_run: minW,
    rows: {}
  };
  for (const spec of specs) {
    const [ys, name] = spec.split(":");
    const y = Number(ys);
    if (!name || Number.isNaN(y)) {
      console.error("bad row spec: " + spec);
      process.exit(1);
    }
    const runs = rowRuns(y, whiteTol, minW);
    profile.rows[name] = { y, runs };
    console.log(`${name}: y=${y} runs=${runs.length} ` +
      `centres=[${runs.map((r) => r.cx).join(",")}]`);
  }
  fs.writeFileSync(outFile, JSON.stringify(profile, null, 2) + "\n");
  console.log("written: " + outFile);
  process.exit(0);
}

if (cmd === "check-rows") {
  needRaw();
  // RAW=... node px.js check-rows profile.json [tolPx]
  // Verifies the remembered rows against the current frame, rewrites the
  // profile with the (possibly drifted) centres, and exits non-zero if the
  // structure changed.
  const profileFile = process.argv[3];
  const tol = Number(process.argv[4] || process.env.DRIFT_TOL || 6);
  if (!profileFile) {
    console.error("usage: check-rows <profile.json> [tolPx]");
    process.exit(1);
  }
  const profile = JSON.parse(fs.readFileSync(profileFile, "utf8"));
  if (profile.size && profile.size !== w + "x" + h) {
    console.log(`SIZE-CHANGED expected=${profile.size} now=${w}x${h}`);
    process.exit(1);
  }
  const whiteTol = profile.white_tol || 12;
  const minW = minRunFor(w, profile.min_run);
  let bad = 0;
  for (const [name, row] of Object.entries(profile.rows)) {
    const now = rowRuns(row.y, whiteTol, minW);
    if (now.length !== row.runs.length) {
      console.log(`${name}: CHANGED runs ${row.runs.length} -> ${now.length} (re-learn)`);
      bad++;
      continue;
    }
    let drift = 0;
    const updated = [];
    for (let i = 0; i < now.length; i++) {
      const d = now[i].cx - row.runs[i].cx;
      if (Math.abs(d) > drift) drift = Math.abs(d);
      updated.push({ ...now[i], label_was: row.runs[i].label_was ?? null });
    }
    if (drift > tol) {
      console.log(`${name}: CHANGED drift=${drift}px > ${tol} (re-learn)`);
      bad++;
      continue;
    }
    row.runs = updated;
    console.log(`${name}: ok runs=${now.length} drift=${drift}px ` +
      `centres=[${updated.map((r) => r.cx).join(",")}]`);
  }
  fs.writeFileSync(profileFile, JSON.stringify(profile, null, 2) + "\n");
  process.exit(bad ? 1 : 0);
}

const rowPitch = (runs) => {
  if (runs.length < 2) return 0;
  return (runs[runs.length - 1].cx - runs[0].cx) / (runs.length - 1);
};

if (cmd === "locate-row") {
  needRaw();
  // RAW=... node px.js locate-row profile.json <name> <y0,y1> [step]
  // The option row MOVES with the length of the question stem, so a remembered
  // y is not enough. Scan the band and pick the line whose run structure
  // (count + pitch + span) matches the learned row best.
  const profileFile = process.argv[3];
  const name = process.argv[4];
  const [y0, y1] = (process.argv[5] || "").split(",").map(Number);
  const step = Number(process.argv[6] || 2);
  if (!profileFile || !name || Number.isNaN(y0) || Number.isNaN(y1)) {
    console.error("usage: locate-row <profile.json> <name> <y0,y1> [step]");
    process.exit(1);
  }
  const profile = JSON.parse(fs.readFileSync(profileFile, "utf8"));
  const target = profile.rows[name];
  if (!target) {
    console.error("no such row: " + name);
    process.exit(1);
  }
  const whiteTol = profile.white_tol || 12;
  const minW = minRunFor(w, profile.min_run);
  const tPitch = rowPitch(target.runs);
  let best = null;
  for (let y = y0; y <= y1; y += step) {
    const runs = rowRuns(y, whiteTol, minW);
    if (runs.length !== target.runs.length) continue;
    const score = Math.abs(rowPitch(runs) - tPitch);
    if (!best || score < best.score - 0.01 ||
        (Math.abs(score - best.score) < 0.01 && Math.abs(y - target.y) < Math.abs(best.y - target.y))) {
      best = { y, runs, score };
    }
  }
  if (!best) {
    console.log(`NONE ${name} no line in ${y0}..${y1} has ${target.runs.length} runs`);
    process.exit(1);
  }
  target.y = best.y;
  target.runs = best.runs;
  fs.writeFileSync(profileFile, JSON.stringify(profile, null, 2) + "\n");
  console.log(`${name}: y=${best.y} (learned ${target.y}) runs=${best.runs.length} ` +
    `pitch=${rowPitch(best.runs).toFixed(1)} centres=[${best.runs.map((r) => r.cx).join(",")}]`);
  process.exit(0);
}

if (cmd === "sweep") {
  // RAW is ignored; scans a directory of frames so a whole question set can be
  // located from ONE capture round trip.
  //   node px.js sweep profile.json <name> <y0,y1> <dir>
  const profileFile = process.argv[3];
  const name = process.argv[4];
  const [y0, y1] = (process.argv[5] || "").split(",").map(Number);
  const dir = process.argv[6];
  if (!profileFile || !name || !dir) {
    console.error("usage: sweep <profile.json> <name> <y0,y1> <dir-with-*.raw>");
    process.exit(1);
  }
  const files = fs.readdirSync(dir).filter((f) => f.endsWith(".raw")).sort();
  let bad = 0;
  for (const f of files) {
    const child = require("child_process").spawnSync(process.execPath,
      [__filename, "locate-row", profileFile, name, `${y0},${y1}`],
      { env: { ...process.env, RAW: dir + "/" + f }, encoding: "utf8" });
    if (child.status === 0) {
      console.log(`${f}  ${child.stdout.trim()}`);
    } else {
      console.log(`${f}  FAILED: ${(child.stdout || child.stderr || "").trim()}`);
      bad++;
    }
  }
  process.exit(bad ? 1 : 0);
}

if (cmd === "selected") {
  // node px.js selected profile.json <name> <dir> [y0,y1]
  // For every captured frame: find the (moving) row, then report which option
  // carries the selected tint. One local call verifies a whole question set.
  const profileFile = process.argv[3];
  const name = process.argv[4];
  const dir = process.argv[5];
  if (!profileFile || !name || !dir) {
    console.error("usage: selected <profile.json> <name> <dir> [y0,y1]");
    process.exit(1);
  }
  const profile = JSON.parse(fs.readFileSync(profileFile, "utf8"));
  const row = profile.rows[name];
  if (!row) {
    console.error("no such row: " + name);
    process.exit(1);
  }
  const bandArg = process.argv[6];   // default: the whole height of each frame
  const whiteTol = profile.white_tol || 12;
  const tPitch = rowPitch(row.runs);
  const files = fs.readdirSync(dir).filter((f) => f.endsWith(".raw")).sort();
  let bad = 0;
  for (const f of files) {
    const b = fs.readFileSync(dir + "/" + f);
    const W = b.readInt32LE(0);
    const H = b.readInt32LE(4);
    const minW = minRunFor(W, profile.min_run);
    const band = bandArg ? bandArg.split(",").map(Number) : [0, H - 1];
    const off = b.length - W * H * 4;
    const at = (x, y) => { const i = off + (y * W + x) * 4; return [b[i], b[i + 1], b[i + 2]]; };
    let best = null;
    for (let y = band[0]; y <= band[1]; y += 2) {
      const runs = rowRunsWith(at, W, y, whiteTol, minW);
      if (runs.length !== row.runs.length) continue;
      const sc = Math.abs(rowPitch(runs) - tPitch);
      if (!best || sc < best.sc) best = { y, runs, sc };
    }
    if (!best) {
      console.log(`${f}: row not found in ${band[0]}..${band[1]}`);
      bad++;
      continue;
    }
    const picked = [];
    best.runs.forEach((r, i) => {
      const [cr, cg, cb] = at(r.cx, best.y);
      if (cb - cr > 8) picked.push(String.fromCharCode(65 + i));
    });
    console.log(`${f}: y=${best.y} runs=${best.runs.length} ` +
      `selected=${picked.length ? picked.join(",") : "NONE"}`);
    if (picked.length !== 1) bad++;
  }
  process.exit(bad ? 1 : 0);
}

console.error("usage: RAW=<frame.raw> px.js size | probe x,y... | sel x,y... | " +
  "find mode x0,y0,x1,y1 [min] | blocks r,g,b [tol] [min] | " +
  "learn-rows <profile.json> <y:name>... | check-rows <profile.json> [tol] | " +
  "locate-row <profile.json> <name> <y0,y1> [step] | sweep <profile.json> <name> <y0,y1> <dir> | " +
  "selected <profile.json> <name> <dir> [y0,y1]");
process.exit(1);
