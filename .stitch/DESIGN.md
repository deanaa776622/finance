# Design System: Finance — Calm Ledger

> Stitch-style semantic design system for the long-term asset tracker.
> Visual mockups only — not applied to app code yet.

## 1. Visual Theme & Atmosphere

A quiet night-studio interface for long-term wealth recording. Density 4 (Daily App Balanced), variance 5 (gently asymmetric), motion 4 (fluid, restrained). Atmosphere: deep charcoal ink with soft atmospheric mist — allocation colors exist as quiet weather, never neon market flash. The first screen should feel like checking a compass, not a trading terminal.

Chinese copy stays short and calm: 平衡 / 留意配置 / 配置大致平衡. No English status shouting (BALANCED / ATTENTION).

## 2. Color Palette & Roles

- **Deep Ledger** (#0C0E12) — Primary canvas / night ground
- **Lifted Surface** (#161A22) — Docked sheets, list panels (one step lighter)
- **Paper Ink** (#F4F1EC) — Primary text (warm off-white, not pure white)
- **Quiet Ink** (rgba(244,241,236,0.55)) — Secondary labels, metadata
- **Whisper Line** (rgba(244,241,236,0.08)) — Hairline dividers, chart rails
- **Mist Teal** (#5B9AA8) — 原型 / original allocation atmosphere (desaturated)
- **Mist Sage** (#7A9B78) — 槓桿 / leverage atmosphere (desaturated)
- **Warm Sand** (#C4A574) — 現金 / cash atmosphere (muted gold, no neon)
- **Soft Coral** (#C4846A) — Drift / rebalance cue only (never flashy red-green P&L)
- **Single Accent** (#5B9AA8) — Focus rings, progress fill, primary interactive ink

Max one accent family. Saturation kept below 60%. No purple, no cyan neon, no lime glow.

## 3. Typography Rules

- **Display / Status:** SF Pro Display–like rounded sans, weight 600, letter-spacing ~0.35em for status words (平衡). Hierarchy by weight and opacity, not size screaming.
- **Metrics:** Rounded, tabular/monospace digits for money and years.
- **Body / Labels:** SF Pro Text–like, relaxed leading, caption labels with modest tracking.
- **Banned:** Inter, generic serif, gradient text on large headers, emoji, ALL-CAPS English status as hero.

## 4. Component Stylings

- **Home Hero:** Full-bleed night canvas. Soft elliptical mist orbs (blurred, low opacity) encode allocation — not hard circles with neon glow. Centered status word + one calm subtitle. Whisper chevrons top/bottom as gesture hints only.
- **Docked Card:** When assets or savings open, hero shrinks to a softly rounded continuous card (28px) with whisper-soft shadow — no floating neon edge.
- **Asset List:** Plain list, section headers with quiet kind labels. Trend chart as a soft plate with sparse multi-year area, not dense daily candles. Rebalance cue as muted coral text, never alert banners.
- **Savings Tuner:** Years-to-goal as the only hero number. Collapsed group headers (目標 / 計畫 / 現狀). Sliders or steppers with hairline tracks; accent fill restrained.
- **Buttons / FABs:** Minimal; prefer system-like toolbar icons. No outer glow.

## 5. Layout Principles

- One job per screen: Home = allocation calm; Assets = holdings + long trend; Savings = years to target.
- Preserve the existing three-panel gesture shell (上滑儲蓄 / 下滑資產 / 左右切換淨值·曝險) — redesign the surface, not the product model.
- Generous vertical breathing room on home; denser but still quiet on lists.
- No KPI strip, no daily P&L hero, no stock ticker chrome.

## 6. Motion & Interaction

- Spring settle when snapping panels (response ~0.48, damping ~0.88).
- Mist orbs drift extremely slowly; disabled under Reduce Motion.
- Cross-fade between 總淨值 / 總曝險; page dots only while dragging horizontally.
- No bounce-for-attention chevrons; opacity stays quiet.

## 7. Anti-Patterns (Banned)

- Neon outer glow, cyber cyan/lime orbs, pure black (#000)
- Red/green flash for daily moves; “今日漲跌” as hero
- Purple-indigo AI gradients; Inter; emoji
- Dashboard KPI cards; 3 equal metric cards on home
- English BALANCED / ATTENTION as primary status
- Alarm banners for mild allocation drift
- Dense intraday charts
