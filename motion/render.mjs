#!/usr/bin/env node
/**
 * Deterministic frame renderer for motion/index.html
 *   node render.mjs preview   # 1 frame / beat → preview/
 *   node render.mjs contact   # contact sheet
 *   node render.mjs final     # 60fps + 4-subframe tmix blur
 *   node render.mjs loopcheck # compare first vs last blended frame
 */
import { chromium } from "playwright";
import { spawn } from "child_process";
import { mkdir, readdir, writeFile, rm, copyFile } from "fs/promises";
import path from "path";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const HTML = path.join(__dirname, "index.html");
const DURATION = 14;
const FPS = 60;
const BEAT = 0.5;
const BEATS = 28;
const SUBS = [-1.5, -0.5, 0.5, 1.5];

const mode = process.argv[2] || "preview";

function run(cmd, args, opts = {}) {
  return new Promise((resolve, reject) => {
    const p = spawn(cmd, args, { stdio: opts.quiet ? "pipe" : "inherit" });
    p.on("exit", (code) => (code === 0 ? resolve() : reject(new Error(`${cmd} ${args[0]} → ${code}`))));
  });
}

async function withPage(fn) {
  const browser = await chromium.launch({
    executablePath: process.env.CHROME_PATH || "/usr/local/bin/google-chrome",
    headless: true,
    args: ["--font-render-hinting=medium", "--disable-lcd-text", "--hide-scrollbars"],
  });
  const page = await browser.newPage({
    viewport: { width: 1440, height: 1440 },
    deviceScaleFactor: 1,
  });
  await page.goto("file://" + HTML, { waitUntil: "load" });
  await page.waitForFunction(() => typeof window.seek === "function");
  // Warm fonts / first layout
  await page.evaluate(() => window.seek(0));
  await page.waitForTimeout(100);
  try {
    await fn(page);
  } finally {
    await browser.close();
  }
}

async function captureAt(page, t, outPath) {
  await page.evaluate((tt) => window.seek(tt), t);
  await page.evaluate(
    () =>
      new Promise((r) => {
        requestAnimationFrame(() => requestAnimationFrame(r));
      })
  );
  await page.screenshot({ path: outPath, type: "png", animations: "disabled" });
}

async function preview() {
  const dir = path.join(__dirname, "preview");
  await mkdir(dir, { recursive: true });
  await withPage(async (page) => {
    for (let i = 0; i < BEATS; i++) {
      const t = i * BEAT;
      const name = `beat-${String(i + 1).padStart(2, "0")}.png`;
      process.stdout.write(`preview ${name}  t=${t.toFixed(2)}\n`);
      await captureAt(page, t, path.join(dir, name));
    }
  });
  console.log("preview done:", dir);
}

function xstackLayout(n, cols) {
  const parts = [];
  for (let i = 0; i < n; i++) {
    const c = i % cols;
    const r = Math.floor(i / cols);
    const x =
      c === 0 ? "0" : Array.from({ length: c }, (_, k) => `w${k}`).join("+");
    const y =
      r === 0 ? "0" : Array.from({ length: r }, () => "h0").join("+");
    parts.push(`${x}_${y}`);
  }
  return parts.join("|");
}

async function contact() {
  const dir = path.join(__dirname, "preview");
  const files = (await readdir(dir)).filter((f) => /^beat-\d+\.png$/.test(f)).sort();
  if (files.length !== 28) throw new Error(`expected 28 beats, got ${files.length}`);
  await mkdir(path.join(__dirname, "out"), { recursive: true });
  const out = path.join(__dirname, "out", "contact-sheet.png");
  // Scale each tile down so sheet is manageable, then xstack 7×4
  const args = ["-y"];
  for (const f of files) args.push("-i", path.join(dir, f));
  const scaled = files.map((_, i) => `[${i}:v]scale=240:240[s${i}]`).join(";");
  const inputs = files.map((_, i) => `[s${i}]`).join("");
  args.push(
    "-filter_complex",
    `${scaled};${inputs}xstack=inputs=28:layout=${xstackLayout(28, 7)}[v]`,
    "-map",
    "[v]",
    out
  );
  await run("ffmpeg", args);
  console.log("contact sheet:", out);
}

async function blendFrame(inputs, outPath) {
  const listFile = outPath + ".txt";
  await writeFile(listFile, inputs.map((p) => `file '${p}'`).join("\n") + "\n");
  await run(
    "ffmpeg",
    [
      "-y",
      "-f", "concat",
      "-safe", "0",
      "-i", listFile,
      "-vf", "tmix=frames=4:weights=1 1 1 1",
      "-frames:v", "1",
      outPath,
    ],
    { quiet: true }
  );
}

async function finalRender() {
  const rawDir = path.join(__dirname, "out", "raw");
  const blurDir = path.join(__dirname, "out", "blur");
  await rm(rawDir, { recursive: true, force: true });
  await rm(blurDir, { recursive: true, force: true });
  await mkdir(rawDir, { recursive: true });
  await mkdir(blurDir, { recursive: true });

  const totalFrames = DURATION * FPS;
  const dt = 1 / FPS;

  await withPage(async (page) => {
    for (let f = 0; f < totalFrames; f++) {
      const tCenter = f * dt;
      for (let s = 0; s < SUBS.length; s++) {
        const t = ((tCenter + SUBS[s] * (dt / 4)) % DURATION + DURATION) % DURATION;
        await page.evaluate((x) => window.seek(x), t);
        await page.evaluate(
          () => new Promise((r) => requestAnimationFrame(r))
        );
        await page.screenshot({
          path: path.join(rawDir, `f${String(f).padStart(4, "0")}_s${s}.png`),
          type: "png",
          animations: "disabled",
        });
      }
      if (f % 20 === 0) console.log(`capture ${f}/${totalFrames}`);
    }
  });

  console.log("blending…");
  // Parallel-ish batches of ffmpeg
  const batch = 8;
  for (let f = 0; f < totalFrames; f += batch) {
    const jobs = [];
    for (let k = 0; k < batch && f + k < totalFrames; k++) {
      const id = String(f + k).padStart(4, "0");
      const inputs = SUBS.map((_, s) => path.join(rawDir, `f${id}_s${s}.png`));
      const out = path.join(blurDir, `frame-${id}.png`);
      jobs.push(blendFrame(inputs, out));
    }
    await Promise.all(jobs);
    console.log(`blur ${Math.min(f + batch, totalFrames)}/${totalFrames}`);
  }

  const mp4 = path.join(__dirname, "out", "finance-motion-60fps.mp4");
  await run("ffmpeg", [
    "-y",
    "-framerate", String(FPS),
    "-i", path.join(blurDir, "frame-%04d.png"),
    "-c:v", "libx264",
    "-pix_fmt", "yuv420p",
    "-crf", "16",
    "-movflags", "+faststart",
    mp4,
  ]);

  await copyFile(path.join(blurDir, "frame-0000.png"), path.join(__dirname, "out", "loop-first.png"));
  await copyFile(
    path.join(blurDir, `frame-${String(totalFrames - 1).padStart(4, "0")}.png`),
    path.join(__dirname, "out", "loop-last.png")
  );

  // Quick loop video (no audio)
  const loopMp4 = path.join(__dirname, "out", "finance-motion-loop-preview.mp4");
  await run("ffmpeg", [
    "-y",
    "-stream_loop", "2",
    "-i", mp4,
    "-c", "copy",
    loopMp4,
  ]);

  console.log("final:", mp4);
}

async function loopcheck() {
  const a = path.join(__dirname, "out", "loop-first.png");
  const b = path.join(__dirname, "out", "loop-last.png");
  const diff = path.join(__dirname, "out", "loop-diff.png");
  await run("ffmpeg", [
    "-y",
    "-i", a,
    "-i", b,
    "-filter_complex",
    "ssim;blend=all_mode=difference",
    "-frames:v", "1",
    diff,
  ]);
  console.log("wrote", diff);
}

if (mode === "preview") await preview();
else if (mode === "contact") await contact();
else if (mode === "final") await finalRender();
else if (mode === "loopcheck") await loopcheck();
else {
  console.error("unknown mode", mode);
  process.exit(1);
}
