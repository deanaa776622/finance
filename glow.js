/**
 * glow.js - Canvas 隨機漂浮與風控連動 Glow 背景引擎
 * 
 * 特色：
 * 1. 隨機漂浮：三個光球具備獨立隨機向量速度與有機邊界反彈，軌跡完全不重複。
 * 2. 達成率尺寸：連動 index.html (Target Total) 與理想比例，達成率 0%~100% 動態縮放半徑。
 * 3. 獨立風控偏離警示：原型、槓桿、現金各自獨立計算偏離差距，2%~10% 獨立漸變變紅。
 */

// 存放三個資產光球的物理狀態
const glowOrbsState = [
  { id: 'orig', name: '原型', x: 0, y: 0, vx: 0.3, vy: 0.2, baseRgb: { r: 56, g: 189, b: 248 }, currentRgb: 'rgb(56, 189, 248)', currentSize: 0, currentOpacity: 0 },
  { id: 'lev',  name: '槓桿', x: 0, y: 0, vx: -0.25, vy: 0.35, baseRgb: { r: 74, g: 222, b: 128 }, currentRgb: 'rgb(74, 222, 128)', currentSize: 0, currentOpacity: 0 },
  { id: 'cash', name: '現金', x: 0, y: 0, vx: 0.2, vy: -0.3, baseRgb: { r: 250, g: 204, b: 21 }, currentRgb: 'rgb(250, 204, 21)', currentSize: 0, currentOpacity: 0 }
];

let glowCanvas = null;
let glowCtx = null;
let isGlowEngineRunning = false;

// 初始化隨機位置與向量速度
function initGlowPositions() {
  const width = window.innerWidth || 375;
  const height = window.innerHeight || 667;

  glowOrbsState.forEach((orb, idx) => {
    // 預設將三個光球隨機散開在螢幕不同分區
    if (idx === 0) { orb.x = width * (0.15 + Math.random() * 0.3); orb.y = height * (0.15 + Math.random() * 0.3); }
    else if (idx === 1) { orb.x = width * (0.55 + Math.random() * 0.3); orb.y = height * (0.2 + Math.random() * 0.3); }
    else { orb.x = width * (0.3 + Math.random() * 0.4); orb.y = height * (0.6 + Math.random() * 0.3); }

    // 賦予微小的隨機漂浮速度 (-0.4 ~ 0.4 px/frame)
    const speedScale = 0.35;
    orb.vx = (Math.random() - 0.5) * 2 * speedScale;
    orb.vy = (Math.random() - 0.5) * 2 * speedScale;
    
    // 避免速度過慢或死角
    if (Math.abs(orb.vx) < 0.1) orb.vx = orb.vx < 0 ? -0.2 : 0.2;
    if (Math.abs(orb.vy) < 0.1) orb.vy = orb.vy < 0 ? -0.2 : 0.2;
  });
}

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

  // 6. 計算各光球數值
  const maxRadius = 260; // 光球最大半徑 (相當於直徑 520px)

  glowOrbsState[0].currentRgb = getInterpolatedColor(glowOrbsState[0].baseRgb, factorOrig);
  glowOrbsState[0].currentSize = maxRadius * ratioAchieveOrig;
  glowOrbsState[0].currentOpacity = 0.65 * ratioAchieveOrig;

  glowOrbsState[1].currentRgb = getInterpolatedColor(glowOrbsState[1].baseRgb, factorLev);
  glowOrbsState[1].currentSize = maxRadius * ratioAchieveLev;
  glowOrbsState[1].currentOpacity = 0.65 * ratioAchieveLev;

  glowOrbsState[2].currentRgb = getInterpolatedColor(glowOrbsState[2].baseRgb, factorCash);
  glowOrbsState[2].currentSize = maxRadius * ratioAchieveCash;
  glowOrbsState[2].currentOpacity = 0.65 * ratioAchieveCash;

  // 7. 初始化並啟動 Canvas 隨機漂浮循環 (若尚未啟動)
  if (!isGlowEngineRunning) {
    setupCanvas();
    initGlowPositions();
    isGlowEngineRunning = true;
    requestAnimationFrame(renderGlowFrame);
  }
}

// 建立滿版全螢幕 Canvas DOM
function setupCanvas() {
  glowCanvas = document.getElementById('glow-canvas-bg');
  if (!glowCanvas) {
    glowCanvas = document.createElement('canvas');
    glowCanvas.id = 'glow-canvas-bg';
    glowCanvas.style.cssText = `
      position: fixed;
      top: 0; left: 0; width: 100vw; height: 100vh;
      pointer-events: none;
      z-index: 0;
      filter: blur(50px);
    `;
    document.body.prepend(glowCanvas);
  }
  glowCtx = glowCanvas.getContext('2d');
  resizeCanvas();

  window.addEventListener('resize', resizeCanvas);
}

function resizeCanvas() {
  if (glowCanvas) {
    glowCanvas.width = window.innerWidth;
    glowCanvas.height = window.innerHeight;
  }
}

// Canvas 60fps 隨機物理漂浮渲染動畫
function renderGlowFrame() {
  if (!glowCtx || !glowCanvas) return;

  const width = glowCanvas.width;
  const height = glowCanvas.height;

  // 清空畫布
  glowCtx.clearRect(0, 0, width, height);

  // 繪製與位移各個隨機光球
  glowOrbsState.forEach(orb => {
    if (orb.currentSize <= 0 || orb.currentOpacity <= 0) return;

    // 1. 位置隨機累加 (漂浮位移)
    orb.x += orb.vx;
    orb.y += orb.vy;

    // 2. 有機邊界碰撞反彈 (帶微幅隨機擾動)
    const margin = orb.currentSize * 0.3;
    if (orb.x < -margin || orb.x > width + margin) {
      orb.vx *= -1;
      orb.vy += (Math.random() - 0.5) * 0.1;
    }
    if (orb.y < -margin || orb.y > height + margin) {
      orb.vy *= -1;
      orb.vx += (Math.random() - 0.5) * 0.1;
    }

    // 3. 繪製徑向漸層隨機發光球
    const gradient = glowCtx.createRadialGradient(orb.x, orb.y, 0, orb.x, orb.y, orb.currentSize);
    
    // 轉為帶透明度之色彩 Stop
    const rgbStr = orb.currentRgb.replace('rgb', 'rgba').replace(')', '');
    gradient.addColorStop(0, `${rgbStr}, ${orb.currentOpacity})`);
    gradient.addColorStop(0.6, `${rgbStr}, ${orb.currentOpacity * 0.4})`);
    gradient.addColorStop(1, `${rgbStr}, 0)`);

    glowCtx.fillStyle = gradient;
    glowCtx.beginPath();
    glowCtx.arc(orb.x, orb.y, orb.currentSize, 0, Math.PI * 2);
    glowCtx.fill();
  });

  requestAnimationFrame(renderGlowFrame);
}

// 頁面載入時自動執行一次
document.addEventListener('DOMContentLoaded', updateGlowBackground);
