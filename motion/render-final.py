#!/usr/bin/env python3
"""60fps final render with 4-subframe temporal average (Playwright + Pillow)."""
from __future__ import annotations

import asyncio
import subprocess
import sys
from io import BytesIO
from pathlib import Path

import numpy as np
from PIL import Image
from playwright.async_api import async_playwright

ROOT = Path(__file__).resolve().parent
HTML = ROOT / "index.html"
OUT = ROOT / "out"
BLUR = OUT / "blur"
DURATION = 14.0
FPS = 60
SUBS = (-1.5, -0.5, 0.5, 1.5)
CHROME = "/usr/local/bin/google-chrome"


async def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    BLUR.mkdir(parents=True, exist_ok=True)
    for p in BLUR.glob("frame-*.png"):
        p.unlink()

    total = int(DURATION * FPS)
    dt = 1.0 / FPS

    async with async_playwright() as pw:
        browser = await pw.chromium.launch(
            executable_path=CHROME,
            headless=True,
            args=["--font-render-hinting=medium", "--disable-lcd-text", "--hide-scrollbars"],
        )
        page = await browser.new_page(
            viewport={"width": 1440, "height": 1440},
            device_scale_factor=1,
        )
        await page.goto(HTML.as_uri(), wait_until="load")
        await page.wait_for_function("() => typeof window.seek === 'function'")
        await page.evaluate("window.seek(0)")
        await page.wait_for_timeout(100)

        for f in range(total):
            t_center = f * dt
            acc = None
            for s in SUBS:
                t = (t_center + s * (dt / 4.0)) % DURATION
                await page.evaluate("(x) => window.seek(x)", t)
                await page.evaluate("() => new Promise((r) => requestAnimationFrame(r))")
                png = await page.screenshot(type="png", animations="disabled")
                arr = np.asarray(Image.open(BytesIO(png)).convert("RGB"), dtype=np.float32)
                acc = arr if acc is None else acc + arr
            frame = (acc / len(SUBS)).clip(0, 255).astype(np.uint8)
            Image.fromarray(frame, "RGB").save(BLUR / f"frame-{f:04d}.png", optimize=False)
            if f % 30 == 0:
                print(f"frame {f}/{total}", flush=True)

        await browser.close()

    mp4 = OUT / "finance-motion-60fps.mp4"
    subprocess.check_call(
        [
            "ffmpeg", "-y",
            "-framerate", str(FPS),
            "-i", str(BLUR / "frame-%04d.png"),
            "-c:v", "libx264",
            "-pix_fmt", "yuv420p",
            "-crf", "16",
            "-movflags", "+faststart",
            str(mp4),
        ]
    )
    (OUT / "loop-first.png").write_bytes((BLUR / "frame-0000.png").read_bytes())
    (OUT / "loop-last.png").write_bytes(
        (BLUR / f"frame-{total - 1:04d}.png").read_bytes()
    )
    subprocess.check_call(
        [
            "ffmpeg", "-y",
            "-i", str(OUT / "loop-first.png"),
            "-i", str(OUT / "loop-last.png"),
            "-filter_complex", "blend=all_mode=difference,eq=contrast=3",
            "-frames:v", "1",
            "-update", "1",
            str(OUT / "loop-diff.png"),
        ]
    )
    print("final:", mp4)


if __name__ == "__main__":
    asyncio.run(main())
