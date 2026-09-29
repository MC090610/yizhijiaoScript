#!/usr/bin/env node
// Parse a `uiautomator dump` XML (the whole file is one line).
//
// Text-first is the cheapest way to read an Android screen: one dump yields the
// question stem, every option label and the real bounds of every button, with no
// vision at all. Use the pixel tools only when the dump has no content (image
// questions, WebViews that expose nothing) or to confirm a tap landed.
//
//   node dump.js nodes <file.xml>            all non-empty text/desc nodes, by y
//   node dump.js find  <file.xml> <text>     bounds of the LAST node whose text equals <text>
//   node dump.js any   <file.xml> <text>     bounds of the LAST node whose text CONTAINS <text>
//   node dump.js quiz  <file.xml>            anchor on the last 【第N题】, list what follows
//
// Exit status is non-zero when nothing matched, so callers can abort instead of
// building an action out of empty coordinates.
const fs = require("fs");

const [cmd, file, arg] = process.argv.slice(2);
if (!cmd || !file) {
  console.error("usage: dump.js nodes|find|any|quiz <file.xml> [text]");
  process.exit(2);
}
const xml = fs.readFileSync(file, "utf8");

const nodes = [];
const re = /<node\b[^>]*>/g;
let m;
while ((m = re.exec(xml)) !== null) {
  const tag = m[0];
  const unesc = (s) => s.replace(/&#10;/g, " ").replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, '"').trim();
  const text = unesc((/\btext="([^"]*)"/.exec(tag) || [, ""])[1]);
  const desc = unesc((/\bcontent-desc="([^"]*)"/.exec(tag) || [, ""])[1]);
  const cls = (/\bclass="([^"]*)"/.exec(tag) || [, ""])[1];
  const b = /\bbounds="\[(-?\d+),(-?\d+)\]\[(-?\d+),(-?\d+)\]"/.exec(tag);
  if (!b) continue;
  const [x0, y0, x1, y1] = b.slice(1).map(Number);
  nodes.push({
    idx: nodes.length,
    text: text || desc,
    cls: cls.replace(/^android\.widget\./, "").replace(/^android\.view\./, ""),
    x0, y0, x1, y1,
    cx: (x0 + x1) >> 1,
    cy: (y0 + y1) >> 1
  });
}
// NOTE: `nodes` stays in DOCUMENT order. That matters: the quiz extraction below
// slices by document position (which is how the previous page's leftovers get
// cut off correctly), while display sorts by y.

const show = (n) =>
  `[${n.x0},${n.y0}][${n.x1},${n.y1}] center=(${n.cx},${n.cy}) ${n.cls}` +
  `${n.text ? '  "' + n.text + '"' : ""}`;

if (cmd === "nodes") {
  for (const n of [...nodes].sort((a, b) => a.y0 - b.y0 || a.x0 - b.x0)) {
    if (n.text) console.log(show(n));
  }
  process.exit(0);
}

const pick = (pred) => {
  const hits = nodes.filter(pred);
  if (!hits.length) {
    console.error(`no node matched "${arg}" in ${file}`);
    process.exit(1);
  }
  console.log(show(hits[hits.length - 1]));
  process.exit(0);
};

if (cmd === "find") pick((n) => n.text === arg);
if (cmd === "any") pick((n) => n.text.includes(arg));

if (cmd === "quiz") {
  // Structured extraction, not "everything after the anchor is an option": a
  // hybrid WebView leaves the PREVIOUS page in the tree, interleaved by y with
  // the live question. Verified against real dumps where a naive reading picked
  // up "课中任务 / 去完成 / 待完成" as options.
  //
  //   * anchor   : LAST node whose text is exactly 【第N题】
  //   * truncate : at the first 上一题 / 下一题 / 交卷 after the anchor
  //   * labels   : single letters A-J sitting in the left margin (x0 < 200)
  //   * option   : first text node with |cy - labelCy| <= 45 and 200 <= x0 <= 1150
  //   * stem     : longest text above the first label (heuristic - sanity check it)
  const anchors = nodes.filter((n) => /^【第(\d+)题】$/.test(n.text));
  if (!anchors.length) {
    console.error("no 【第N题】 anchor: the app is probably not in the foreground");
    process.exit(1);
  }
  const a = anchors[anchors.length - 1];
  const qno = /^【第(\d+)题】$/.exec(a.text)[1];
  // Document order, exactly like the parser that scored 96 on a 49-question set:
  // sorting by y instead keeps stale nodes from the previous page (they can sit
  // closer to the labels than the real stem does).
  const after = nodes.slice(a.idx + 1).filter((n) => n.text);
  const stopIdx = after.findIndex((n) => ["下一题", "上一题", "交卷"].includes(n.text));
  const body = stopIdx >= 0 ? after.slice(0, stopIdx) : after;

  const labels = body.filter((n) => /^[A-J]$/.test(n.text) && n.x0 < 200);
  const firstLabelY = labels.length ? labels[0].cy : Infinity;
  const stemCand = body.filter((n) => n.cy < firstLabelY && n.text.length >= 4);
  stemCand.sort((p, q) => q.cy - p.cy || q.text.length - p.text.length);
  const stem = stemCand[0];

  console.log(`question=${qno}`);
  console.log(`anchor=${show(a)}`);
  console.log(stem ? `stem="${stem.text}"` : "stem=(not found)");
  for (const L of labels) {
    const txt = body
      .filter((n) => Math.abs(n.cy - L.cy) <= 45 && n.x0 >= 200 && n.x0 <= 1150)
      .sort((p, q) => p.x0 - q.x0)[0];
    console.log(`option ${L.text}: tapY=${L.cy} tapX=${L.cx}` +
      `${txt ? '  "' + txt.text + '"' : ""}`);
  }
  const buttons = after.filter((n) =>
    /^(上一题|下一题|交卷|提交|确定|取消)/.test(n.text));
  for (const b of buttons) console.log(`button ${show(b)}`);
  process.exit(0);
}

console.error("unknown command: " + cmd);
process.exit(2);
