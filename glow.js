/**
 * glow.js - 零卡頓 GPU 硬體加速隨機漂浮 Glow 背景引擎
 * 
 * 效能優化：
 * 1. 移除 Canvas 與高耗能 JS 重繪，改回純 GPU 合成管線 (translate3d)。
 * 2. 使用不對稱 keyframes 與多頻率週期 (14s/19s/23s)，實現完全無規律的隨機漂浮感。
 * 3. 完整保留 index.html (Target Total) 達成率尺寸與獨立風控警示紅化邏輯。
 */

function updateGlowBackground() {
  // 1. 讀取當前實際資產金額 (TWD)
  const allocOrig = parseFloat(localStorage.getItem('alloc_original')) || 0;
  const allocLev = parseFloat(localStorage.getItem('alloc_leverage')) || 0;
  const allocCash = parseFloat(localStorage.getItem('alloc_cash')) || 0;

  const currentTotal = allocOrig + allocLev + allocCash;

  // 2. 讀取 index.html 的 Target Total
  let targetTotal = parseFloat(localStorage.getItem('sav_target_total'));
  if (isNaN(targetTotal) || targetTotal <= 0) {
    targetTotal = currentTotal;
  }

  // 3. 讀取理想資產配置目標比例 (%)
  const targetRatios = JSON.parse(localStorage.getItem('target_ratios')) || { orig: 50, lev: 30, cash: 20 };

  // 4. 計算各類別目標金額與達成率 (0.0 ~ 1.0)
  const targetOrigAmount = targetTotal * (targetRatios.orig / 100);
  const targetLevAmount = targetTotal * (targetRatios.lev / 100);
  const targetCashAmount = targetTotal * (targetRatios.cash / 100);

  const ratioAchieveOrig = targetOrigAmount > 0 ? Math.min(1.0, allocOrig / targetOrigAmount) : (allocOrig > 0 ? 1.0 : 0);
  const ratioAchieveLev = targetLevAmount > 0 ? Math.min(1.0, allocLev / targetLevAmount) : (allocLev > 0 ? 1.0 : 0);
  const ratioAchieveCash = targetCashAmount > 0 ? Math.min(1.0, allocCash / targetCashAmount) : (allocCash > 0 ? 1.0 : 0);

  // 5. 計算實際資產佔比 (%) 與 偏離差距
  let actOrig = 0, actLev = 0, actCash = 0;
  if (currentTotal > 0) {
    actOrig = (allocOrig / currentTotal) * 100;
    actLev = (allocLev / currentTotal) * 100;
    actCash = (allocCash / currentTotal) * 100;
  }

  const devOrig = Math.abs(actOrig - targetRatios.orig);
  const devLev = Math.abs(actLev - targetRatios.lev);
  const devCash = Math.abs(actCash - targetRatios.cash);

  function getFactor(dev) {
    if (dev <= 2) return 0;
    return Math.min(1.0, (dev - 2) / 8); // 2% 到 10% 漸漸變紅
  }

  const factorOrig = getFactor(devOrig);
  const factorLev = getFactor(devLev);
  const factorCash = getFactor(devCash);

  function getInterpolatedColor(baseRgb, factor) {
    const targetRgb = { r: 244, g: 63, b: 94 }; // 警示紅 RGB (#f43f5e)
    const r = Math.round(baseRgb.r + (targetRgb.r - baseRgb.r) * factor);
    const g = Math.round(baseRgb.g + (targetRgb.g - baseRgb.g) * factor);
    const b = Math.round(baseRgb.b + (targetRgb.b - baseRgb.b) * factor);
    return `rgb(${r}, ${g}, ${b})`;
  }

  const colorOrig = getInterpolatedColor({ r: 56, g: 189, b: 248 }, factorOrig); // 原型藍 ➔ 警示紅
  const colorLev = getInterpolatedColor({ r: 74, g: 222, b: 128 }, factorLev);   // 槓桿綠 ➔ 警示紅
  const colorCash = getInterpolatedColor({ r: 250, g: 204, b: 21 }, factorCash);  // 現金黃 ➔ 警示紅

  // 6. 光球最大尺寸為 420px，依「達成率」動態縮放
  const maxOrbSize = 420;

  const sizeOrig = maxOrbSize * ratioAchieveOrig;
  const sizeLev = maxOrbSize * ratioAchieveLev;
  const sizeCash = maxOrbSize * ratioAchieveCash;

  // 7. 注入高感光、高流暢度 GPU 隨機位移動畫 keyframe
  if (!document.getElementById('glow-style-keyframes')) {
    const styleEl = document.createElement('style');
    styleEl.id = 'glow-style-keyframes';
    styleEl.innerHTML = `
      @keyframes randomFloat1 {
        0%   { transform: translate3d(0px, 0px, 0) scale(1); }
        25%  { transform: translate3d(120px, 80px, 0) scale(1.15); }
        50%  { transform: translate3d(40px, 160px, 0) scale(0.9); }
        75%  { transform: translate3d(-80px, 60px, 0) scale(1.1); }
        100% { transform: translate3d(0px, 0px, 0) scale(1); }
      }
      @keyframes randomFloat2 {
        0%   { transform: translate3d(0px, 0px, 0) scale(1); }
        33%  { transform: translate3d(-140px, 100px, 0) scale(1.2); }
        66%  { transform: translate3d(-60px, -80px, 0) scale(0.85); }
        100% { transform: translate3d(0px, 0px, 0) scale(1); }
      }
      @keyframes randomFloat3 {
        0%   { transform: translate3d(0px, 0px, 0) scale(1); }
        20%  { transform: translate3d(80px, -100px, 0) scale(0.95); }
        50%  { transform: translate3d(-100px, -60px, 0) scale(1.18); }
        80%  { transform: translate3d(60px, 40px, 0) scale(1.05); }
        100% { transform: translate3d(0px, 0px, 0) scale(1); }
      }

      .glow-orb {
        position: absolute;
        border-radius: 50%;
        filter: blur(80px);
        pointer-events: none;
        will-change: transform;
        transition: background 0.8s ease, width 0.6s ease, height 0.6s ease, opacity 0.6s ease;
      }
    `;
    document.head.appendChild(styleEl);
  }

  // 8. 建立 DOM 容器
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
      <div id="orb-orig" class="glow-orb" style="top: -5%; left: -5%; animation: randomFloat1 14s ease-in-out infinite;"></div>
      <div id="orb-lev" class="glow-orb" style="top: -5%; right: -5%; animation: randomFloat2 19s ease-in-out infinite;"></div>
      <div id="orb-cash" class="glow-orb" style="bottom: -10%; left: 20%; animation: randomFloat3 23s ease-in-out infinite;"></div>
    `;
    document.body.prepend(glowContainer);
  }

  // 9. 更新樣式
  const orbOrig = document.getElementById('orb-orig');
  const orbLev = document.getElementById('orb-lev');
  const orbCash = document.getElementById('orb-cash');

  if (orbOrig) {
    orbOrig.style.width = `${sizeOrig}px`;
    orbOrig.style.height = `${sizeOrig}px`;
    orbOrig.style.background = colorOrig;
    orbOrig.style.opacity = (0.7 * ratioAchieveOrig).toFixed(2);
  }

  if (orbLev) {
    orbLev.style.width = `${sizeLev}px`;
    orbLev.style.height = `${sizeLev}px`;
    orbLev.style.background = colorLev;
    orbLev.style.opacity = (0.7 * ratioAchieveLev).toFixed(2);
  }

  if (orbCash) {
    orbCash.style.width = `${sizeCash}px`;
    orbCash.style.height = `${sizeCash}px`;
    orbCash.style.background = colorCash;
    orbCash.style.opacity = (0.7 * ratioAchieveCash).toFixed(2);
  }
}

// 頁面載入時自動執行一次
document.addEventListener('DOMContentLoaded', updateGlowBackground);
