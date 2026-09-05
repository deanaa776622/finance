/**
 * glow.js - 資產達成率與風控偏離度雙重連動 Glow 背景引擎
 * 特色：
 * 1. 尺寸邏輯：當前資產金額 / 目標金額 = 0% 時尺寸為 0 (不顯示)；達到 >= 100% 時尺寸達到最大。
 * 2. 顏色邏輯：原型、槓桿、現金各自獨立計算偏離差距 (|實際% - 目標%|)，2%~10% 獨立漸變變紅，>=10% 最紅。
 * 3. 獨立評估：三個光球尺寸與顏色互不影響。
 * 4. 保留 CSS Keyframe 柔和漂浮動畫。
 */

function updateGlowBackground() {
  // 1. 讀取真實資產金額 (TWD)
  const allocOrig = parseFloat(localStorage.getItem('alloc_original')) || 0;
  const allocLev = parseFloat(localStorage.getItem('alloc_leverage')) || 0;
  const allocCash = parseFloat(localStorage.getItem('alloc_cash')) || 0;

  const totalNetWorth = allocOrig + allocLev + allocCash;

  // 2. 讀取使用者設定的理想目標比例 (%)，預設 50/30/20
  const targetRatios = JSON.parse(localStorage.getItem('target_ratios')) || { orig: 50, lev: 30, cash: 20 };

  // 3. 計算實際比例 (%)
  let actOrig = 0, actLev = 0, actCash = 0;
  if (totalNetWorth > 0) {
    actOrig = (allocOrig / totalNetWorth) * 100;
    actLev = (allocLev / totalNetWorth) * 100;
    actCash = (allocCash / totalNetWorth) * 100;
  }

  // 4. 計算各資產目標金額 (Target Amount) 與達成率 (Achievement Ratio: 0.0 ~ 1.0)
  const targetOrigAmount = totalNetWorth * (targetRatios.orig / 100);
  const targetLevAmount = totalNetWorth * (targetRatios.lev / 100);
  const targetCashAmount = totalNetWorth * (targetRatios.cash / 100);

  const ratioAchieveOrig = targetOrigAmount > 0 ? Math.min(1.0, allocOrig / targetOrigAmount) : (allocOrig > 0 ? 1.0 : 0);
  const ratioAchieveLev = targetLevAmount > 0 ? Math.min(1.0, allocLev / targetLevAmount) : (allocLev > 0 ? 1.0 : 0);
  const ratioAchieveCash = targetCashAmount > 0 ? Math.min(1.0, allocCash / targetCashAmount) : (allocCash > 0 ? 1.0 : 0);

  // 5. 計算各自類別的偏離差距 (絕對值 %)
  const devOrig = Math.abs(actOrig - targetRatios.orig);
  const devLev = Math.abs(actLev - targetRatios.lev);
  const devCash = Math.abs(actCash - targetRatios.cash);

  // 6. 偏離紅化係數 (0.0~1.0)
  function getFactor(dev) {
    if (dev <= 2) return 0;
    return Math.min(1.0, (dev - 2) / 8); // 2% 到 10% 漸漸變紅
  }

  const factorOrig = getFactor(devOrig);
  const factorLev = getFactor(devLev);
  const factorCash = getFactor(devCash);

  // 7. RGB 顏色插值計算
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

  // 8. 光球最大尺寸定為 420px，依達成率 (0.0 ~ 1.0) 線性決定尺寸與透明度
  const maxOrbSize = 420;

  const sizeOrig = maxOrbSize * ratioAchieveOrig;
  const sizeLev = maxOrbSize * ratioAchieveLev;
  const sizeCash = maxOrbSize * ratioAchieveCash;

  // 9. 動態注入 Keyframe 漂浮動畫與 CSS (若尚未注入)
  if (!document.getElementById('glow-style-keyframes')) {
    const styleEl = document.createElement('style');
    styleEl.id = 'glow-style-keyframes';
    styleEl.innerHTML = `
      @keyframes floatOrb1 {
        0%   { transform: translate(0px, 0px) scale(1); }
        50%  { transform: translate(60px, 40px) scale(1.12); }
        100% { transform: translate(0px, 0px) scale(1); }
      }
      @keyframes floatOrb2 {
        0%   { transform: translate(0px, 0px) scale(1); }
        50%  { transform: translate(-50px, 50px) scale(1.1); }
        100% { transform: translate(0px, 0px) scale(1); }
      }
      @keyframes floatOrb3 {
        0%   { transform: translate(0px, 0px) scale(1); }
        50%  { transform: translate(40px, -60px) scale(1.15); }
        100% { transform: translate(0px, 0px) scale(1); }
      }

      .glow-orb {
        position: absolute;
        border-radius: 50%;
        filter: blur(80px);
        pointer-events: none;
        will-change: transform, background, width, height, opacity;
        transition: background 0.8s ease, width 0.6s ease, height 0.6s ease, opacity 0.6s ease;
      }
    `;
    document.head.appendChild(styleEl);
  }

  // 10. 建立或擷取 DOM 容器
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

  // 11. 套用動態計算後的顏色、尺寸與透明度 (達成率為 0 時尺寸為 0，且 opacity 設為 0)
  const orbOrig = document.getElementById('orb-orig');
  const orbLev = document.getElementById('orb-lev');
  const orbCash = document.getElementById('orb-cash');

  if (orbOrig) {
    orbOrig.style.width = `${sizeOrig}px`;
    orbOrig.style.height = `${sizeOrig}px`;
    orbOrig.style.background = colorOrig;
    orbOrig.style.opacity = (0.75 * ratioAchieveOrig).toFixed(2);
  }

  if (orbLev) {
    orbLev.style.width = `${sizeLev}px`;
    orbLev.style.height = `${sizeLev}px`;
    orbLev.style.background = colorLev;
    orbLev.style.opacity = (0.75 * ratioAchieveLev).toFixed(2);
  }

  if (orbCash) {
    orbCash.style.width = `${sizeCash}px`;
    orbCash.style.height = `${sizeCash}px`;
    orbCash.style.background = colorCash;
    orbCash.style.opacity = (0.75 * ratioAchieveCash).toFixed(2);
  }
}

// 頁面載入時自動執行一次
document.addEventListener('DOMContentLoaded', updateGlowBackground);
