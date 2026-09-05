/**
 * glow.js - 正確連動 index.html (Target Total) 的 Glow 背景引擎
 * 
 * 資料來源：
 * 1. 總目標資產 (Target Total)：來自 index.html 寫入的 localStorage.getItem('sav_target_total')
 * 2. 理想資產配置比例 (%)：來自 stock.html 寫入的 localStorage.getItem('target_ratios')
 * 3. 當前實際資產金額 (TWD)：來自 stock.html 寫入的 alloc_original, alloc_leverage, alloc_cash
 * 
 * 運算規則：
 * - 各類別目標金額 = Target Total * (理想比例 %)
 * - 尺寸邏輯：當前金額 / 該類別目標金額 (0% 時尺寸為 0；>=100% 時達到最大尺寸)
 * - 顏色邏輯：各類別獨立計算與理想比例的偏離度，超過 2%~10% 各自獨立漸變變紅
 */

function updateGlowBackground() {
  // 1. 讀取當前實際資產金額 (TWD)
  const allocOrig = parseFloat(localStorage.getItem('alloc_original')) || 0;
  const allocLev = parseFloat(localStorage.getItem('alloc_leverage')) || 0;
  const allocCash = parseFloat(localStorage.getItem('alloc_cash')) || 0;

  const currentTotal = allocOrig + allocLev + allocCash;

  // 2. 讀取 index.html 的 Target Total (若尚未試算，暫以當前總資產為基準)
  let targetTotal = parseFloat(localStorage.getItem('sav_target_total'));
  if (isNaN(targetTotal) || targetTotal <= 0) {
    targetTotal = currentTotal;
  }

  // 3. 讀取理想資產配置目標比例 (%)，預設 50/30/20
  const targetRatios = JSON.parse(localStorage.getItem('target_ratios')) || { orig: 50, lev: 30, cash: 20 };

  // 4. 計算各類別的「目標金額 (TWD)」
  const targetOrigAmount = targetTotal * (targetRatios.orig / 100);
  const targetLevAmount = targetTotal * (targetRatios.lev / 100);
  const targetCashAmount = targetTotal * (targetRatios.cash / 100);

  // 5. 計算各類別「金額達成率 (0.0 ~ 1.0)」：當前金額 / 該類別目標金額
  const ratioAchieveOrig = targetOrigAmount > 0 ? Math.min(1.0, allocOrig / targetOrigAmount) : (allocOrig > 0 ? 1.0 : 0);
  const ratioAchieveLev = targetLevAmount > 0 ? Math.min(1.0, allocLev / targetLevAmount) : (allocLev > 0 ? 1.0 : 0);
  const ratioAchieveCash = targetCashAmount > 0 ? Math.min(1.0, allocCash / targetCashAmount) : (allocCash > 0 ? 1.0 : 0);

  // 6. 計算實際資產佔比 (%) 與 偏離差距 (絕對值 %)
  let actOrig = 0, actLev = 0, actCash = 0;
  if (currentTotal > 0) {
    actOrig = (allocOrig / currentTotal) * 100;
    actLev = (allocLev / currentTotal) * 100;
    actCash = (allocCash / currentTotal) * 100;
  }

  const devOrig = Math.abs(actOrig - targetRatios.orig);
  const devLev = Math.abs(actLev - targetRatios.lev);
  const devCash = Math.abs(actCash - targetRatios.cash);

  // 7. 計算偏離紅化係數 (0.0~1.0)
  function getFactor(dev) {
    if (dev <= 2) return 0;
    return Math.min(1.0, (dev - 2) / 8); // 2% 到 10% 漸漸變紅
  }

  const factorOrig = getFactor(devOrig);
  const factorLev = getFactor(devLev);
  const factorCash = getFactor(devCash);

  // 8. RGB 顏色插值計算
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

  // 9. 光球最大尺寸定為 420px，依「金額達成率 (0.0 ~ 1.0)」動態決定尺寸與透明度
  const maxOrbSize = 420;

  const sizeOrig = maxOrbSize * ratioAchieveOrig;
  const sizeLev = maxOrbSize * ratioAchieveLev;
  const sizeCash = maxOrbSize * ratioAchieveCash;

  // 10. 動態注入 Keyframe 漂浮動畫 (若尚未注入)
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

  // 11. 建立或擷取 DOM 容器
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

  // 12. 套用獨立計算後的顏色、尺寸與透明度
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
