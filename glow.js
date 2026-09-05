/**
 * glow.js - 資產風控偏離警示 Glow 背景引擎
 * 特色：
 * 1. 保留 CSS 柔和漂浮動畫 (Orbs 移動)。
 * 2. 保留隨總淨資產 (Net Worth) 規模自動動態放大光暈尺寸。
 * 3. 偏離度警示：計算真實配置與理想比例的差距，差距 2%~10% 漸漸變紅，≥10% 時轉為最紅。
 */

function updateGlowBackground() {
  // 1. 讀取真實資產金額
  const allocOrig = parseFloat(localStorage.getItem('alloc_original')) || 0;
  const allocLev = parseFloat(localStorage.getItem('alloc_leverage')) || 0;
  const allocCash = parseFloat(localStorage.getItem('alloc_cash')) || 0;

  const totalNetWorth = allocOrig + allocLev + allocCash;

  // 2. 讀取使用者設定的理想目標比例 (%)，預設 50/30/20
  const targetRatios = JSON.parse(localStorage.getItem('target_ratios')) || { orig: 50, lev: 30, cash: 20 };

  // 3. 計算實際比例 (%)
  let actOrig = 50, actLev = 30, actCash = 20;
  if (totalNetWorth > 0) {
    actOrig = (allocOrig / totalNetWorth) * 100;
    actLev = (allocLev / totalNetWorth) * 100;
    actCash = (allocCash / totalNetWorth) * 100;
  }

  // 4. 計算最大偏離差距 (絕對值 %)
  const devOrig = Math.abs(actOrig - targetRatios.orig);
  const devLev = Math.abs(actLev - targetRatios.lev);
  const devCash = Math.abs(actCash - targetRatios.cash);

  const maxDeviation = Math.max(devOrig, devLev, devCash);

  // 5. 計算偏離紅化係數 (0.0 表示正常，1.0 表示偏離達到 10% 以上最紅)
  let warningFactor = 0;
  if (maxDeviation > 2) {
    warningFactor = Math.min(1.0, (maxDeviation - 2) / 8); // 2% 到 10% 平滑漸變
  }

  // 6. 輔助函式：根據 warningFactor 在「正常主題色」與「警示紅 (#f43f5e)」之間做 RGB 插值計算
  function getInterpolatedColor(baseRgb, factor) {
    // 警示紅：RGB(244, 63, 94)
    const targetRgb = { r: 244, g: 63, b: 94 };
    const r = Math.round(baseRgb.r + (targetRgb.r - baseRgb.r) * factor);
    const g = Math.round(baseRgb.g + (targetRgb.g - baseRgb.g) * factor);
    const b = Math.round(baseRgb.b + (targetRgb.b - baseRgb.b) * factor);
    return `rgb(${r}, ${g}, ${b})`;
  }

  // 原本主題色 RGB 定義
  const colorOrig = getInterpolatedColor({ r: 56, g: 189, b: 248 }, warningFactor); // 原型藍 ➔ 警示紅
  const colorLev = getInterpolatedColor({ r: 74, g: 222, b: 128 }, warningFactor);  // 槓桿綠 ➔ 警示紅
  const colorCash = getInterpolatedColor({ r: 250, g: 204, b: 21 }, warningFactor);  // 現金黃 ➔ 警示紅

  // 7. 根據「總淨資產規模」計算光暈尺寸 (Scale)
  let netWorthScale = 1.0;
  if (totalNetWorth > 0) {
    netWorthScale = 0.8 + Math.min(1.2, Math.log10(totalNetWorth / 100000) * 0.4);
    if (netWorthScale < 0.8) netWorthScale = 0.8;
  }

  // 8. 動態注入 Keyframe 漂浮動畫與 CSS (若尚未注入)
  if (!document.getElementById('glow-style-keyframes')) {
    const styleEl = document.createElement('style');
    styleEl.id = 'glow-style-keyframes';
    styleEl.innerHTML = `
      @keyframes floatOrb1 {
        0%   { transform: translate(0px, 0px) scale(1); }
        50%  { transform: translate(60px, 40px) scale(1.15); }
        100% { transform: translate(0px, 0px) scale(1); }
      }
      @keyframes floatOrb2 {
        0%   { transform: translate(0px, 0px) scale(1); }
        50%  { transform: translate(-50px, 50px) scale(1.1); }
        100% { transform: translate(0px, 0px) scale(1); }
      }
      @keyframes floatOrb3 {
        0%   { transform: translate(0px, 0px) scale(1); }
        50%  { transform: translate(40px, -60px) scale(1.2); }
        100% { transform: translate(0px, 0px) scale(1); }
      }

      .glow-orb {
        position: absolute;
        border-radius: 50%;
        filter: blur(80px);
        opacity: 0.75;
        pointer-events: none;
        will-change: transform, background, width, height;
        transition: background 0.8s ease, width 0.6s ease, height 0.6s ease;
      }
    `;
    document.head.appendChild(styleEl);
  }

  // 9. 建立或擷取 DOM 容器
  let glowContainer = document.getElementById('glow-bg-container');
  if (!glowContainer) {
    glowContainer = document.createElement('div');
    glowContainer.id = 'glow-bg-container';
    glowContainer.style.cssText = `
      position: fixed;
      top: 0; left: 0; width: 100vw; height: 100vh;
      pointer-events: none;
      z-index: 0;
      overflow: hidden;
    `;

    glowContainer.innerHTML = `
      <div id="orb-orig" class="glow-orb" style="top: -10%; left: -10%; animation: floatOrb1 18s ease-in-out infinite;"></div>
      <div id="orb-lev" class="glow-orb" style="top: -5%; right: -10%; animation: floatOrb2 22s ease-in-out infinite;"></div>
      <div id="orb-cash" class="glow-orb" style="bottom: -15%; left: 20%; animation: floatOrb3 20s ease-in-out infinite;"></div>
    `;
    document.body.prepend(glowContainer);
  }

  // 10. 套用動態計算後的顏色與尺寸 (尺寸僅連動總淨資產規模，色彩呈現風控狀態)
  const baseSize = 360 * netWorthScale;

  const orbOrig = document.getElementById('orb-orig');
  const orbLev = document.getElementById('orb-lev');
  const orbCash = document.getElementById('orb-cash');

  if (orbOrig) {
    orbOrig.style.width = `${baseSize}px`;
    orbOrig.style.height = `${baseSize}px`;
    orbOrig.style.background = colorOrig;
  }

  if (orbLev) {
    orbLev.style.width = `${baseSize}px`;
    orbLev.style.height = `${baseSize}px`;
    orbLev.style.background = colorLev;
  }

  if (orbCash) {
    orbCash.style.width = `${baseSize}px`;
    orbCash.style.height = `${baseSize}px`;
    orbCash.style.background = colorCash;
  }
}

// 頁面載入時自動執行一次
document.addEventListener('DOMContentLoaded', updateGlowBackground);
