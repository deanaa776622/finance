// 1. 動態注入光暈背景的 CSS 樣式
(function injectGlowStyles() {
  const style = document.createElement('style');
  style.innerHTML = `
    :root {
      --s-orig: 1;
      --s-lev: 1;
      --s-cash: 1;
    }
    .glow-container {
      position: fixed;
      top: 0;
      left: 0;
      width: 100vw;
      height: 100vh;
      overflow: hidden;
      z-index: 0;
      pointer-events: none;
    }
    .blob {
      position: absolute;
      width: 160vw;
      height: 160vw;
      border-radius: 50%;
      filter: blur(80px);
      opacity: 0.75;
      mix-blend-mode: screen;
      transition: background 0.8s ease;
      transform-origin: center center;
    }
    .blob-original {
      top: -20vh;
      left: -20vw;
      animation: smoothRotateOriginal 22s linear infinite;
    }
    .blob-leverage {
      top: -20vh;
      right: -20vw;
      animation: smoothRotateLeverage 28s linear infinite;
    }
    .blob-cash {
      bottom: -30vh;
      left: -10vw;
      animation: smoothRotateCash 25s linear infinite;
    }
    @keyframes smoothRotateOriginal {
      0% { transform: rotate(0deg) translate(-10vw, -10vh) rotate(0deg) scale(var(--s-orig)); }
      50% { transform: rotate(180deg) translate(-10vw, -10vh) rotate(-180deg) scale(calc(var(--s-orig) * 1.15)); }
      100% { transform: rotate(360deg) translate(-10vw, -10vh) rotate(-360deg) scale(var(--s-orig)); }
    }
    @keyframes smoothRotateLeverage {
      0% { transform: rotate(0deg) translate(12vw, -8vh) rotate(0deg) scale(var(--s-lev)); }
      50% { transform: rotate(-180deg) translate(12vw, -8vh) rotate(180deg) scale(calc(var(--s-lev) * 0.9)); }
      100% { transform: rotate(-360deg) translate(12vw, -8vh) rotate(-360deg) scale(var(--s-lev)); }
    }
    @keyframes smoothRotateCash {
      0% { transform: rotate(0deg) translate(0vw, 15vh) rotate(0deg) scale(calc(var(--s-cash) * 0.95)); }
      50% { transform: rotate(180deg) translate(0vw, 15vh) rotate(-180deg) scale(calc(var(--s-cash) * 1.1)); }
      100% { transform: rotate(360deg) translate(0vw, 15vh) rotate(-360deg) scale(calc(var(--s-cash) * 0.95)); }
    }
  `;
  document.head.appendChild(style);
})();

// 2. DOM 載入時自動將光暈容器注入到 body 最前端
document.addEventListener("DOMContentLoaded", function () {
  if (!document.querySelector('.glow-container')) {
    const container = document.createElement('div');
    container.className = 'glow-container';
    container.innerHTML = `
      <div id="blob-original" class="blob blob-original"></div>
      <div id="blob-leverage" class="blob blob-leverage"></div>
      <div id="blob-cash" class="blob blob-cash"></div>
    `;
    document.body.insertBefore(container, document.body.firstChild);
  }
  // 預設自動讀取更新一次
  updateGlowBackground();
});

// 3. 核心運算邏輯：色彩插值與面積縮放
const COLOR_ORIGINAL = { r: 56,  g: 189, b: 248 };
const COLOR_LEVERAGE = { r: 74,  g: 222, b: 128 };
const COLOR_CASH     = { r: 250, g: 204, b: 21  };
const COLOR_RED      = { r: 244, g: 63,  b: 94  };

function glowParseNumber(formattedStr) {
  if (!formattedStr) return 0;
  return parseFloat(formattedStr.toString().replace(/,/g, '')) || 0;
}

function glowInterpolateColor(baseColor, targetColor, factor) {
  const f = Math.min(Math.max(factor, 0), 1);
  const r = Math.round(baseColor.r + f * (targetColor.r - baseColor.r));
  const g = Math.round(baseColor.g + f * (targetColor.g - baseColor.g));
  const b = Math.round(baseColor.b + f * (targetColor.b - baseColor.b));
  return `rgba(${r}, ${g}, ${b}, 1)`;
}

/**
 * 更新背景光暈狀態
 * @param {number} [customTargetTotal] 選擇性傳入未來目標金額，若不傳則自動從 localStorage 讀取
 */
function updateGlowBackground(customTargetTotal) {
  const futureTotalTarget = customTargetTotal !== undefined 
    ? customTargetTotal 
    : (parseFloat(localStorage.getItem('sav_target_total')) || 10000000);

  const tOrig = parseFloat(localStorage.getItem('target_original')) || 60;
  const tLev  = parseFloat(localStorage.getItem('target_leverage')) || 20;
  const tCash = parseFloat(localStorage.getItem('target_cash')) || 20;

  const aOrig = glowParseNumber(localStorage.getItem('alloc_original')) || 0;
  const aLev  = glowParseNumber(localStorage.getItem('alloc_leverage')) || 0;
  const aCash = glowParseNumber(localStorage.getItem('alloc_cash')) || 0;

  // 計算面積縮放 (達成率開根號)
  const targetAmtOrig = futureTotalTarget * (tOrig / 100);
  const targetAmtLev  = futureTotalTarget * (tLev / 100);
  const targetAmtCash = futureTotalTarget * (tCash / 100);

  const scaleOrig = targetAmtOrig > 0 ? Math.min(Math.sqrt(aOrig / targetAmtOrig), 1) : (aOrig > 0 ? 1 : 0);
  const scaleLev  = targetAmtLev > 0 ? Math.min(Math.sqrt(aLev / targetAmtLev), 1) : (aLev > 0 ? 1 : 0);
  const scaleCash = targetAmtCash > 0 ? Math.min(Math.sqrt(aCash / targetAmtCash), 1) : (aCash > 0 ? 1 : 0);

  document.documentElement.style.setProperty('--s-orig', scaleOrig);
  document.documentElement.style.setProperty('--s-lev', scaleLev);
  document.documentElement.style.setProperty('--s-cash', scaleCash);

  // 計算偏離度轉紅
  const total = aOrig + aLev + aCash;
  let cOrig = 0, cLev = 0, cCash = 0;
  if (total > 0) {
    cOrig = (aOrig / total) * 100;
    cLev  = (aLev / total) * 100;
    cCash = (aCash / total) * 100;
  }

  const diffOrig = Math.abs(cOrig - tOrig);
  const diffLev  = Math.abs(cLev - tLev);
  const diffCash = Math.abs(cCash - tCash);

  const colorOrigStr = glowInterpolateColor(COLOR_ORIGINAL, COLOR_RED, diffOrig / 10);
  const colorLevStr  = glowInterpolateColor(COLOR_LEVERAGE, COLOR_RED, diffLev / 10);
  const colorCashStr = glowInterpolateColor(COLOR_CASH, COLOR_RED, diffCash / 10);

  const bOrig = document.getElementById('blob-original');
  const bLev  = document.getElementById('blob-leverage');
  const bCash = document.getElementById('blob-cash');

  if (bOrig) bOrig.style.background = `radial-gradient(circle, ${colorOrigStr} 0%, rgba(0,0,0,0) 70%)`;
  if (bLev)  bLev.style.background  = `radial-gradient(circle, ${colorLevStr} 0%, rgba(0,0,0,0) 70%)`;
  if (bCash) bCash.style.background = `radial-gradient(circle, ${colorCashStr} 0%, rgba(0,0,0,0) 70%)`;

  // 返回最大偏離值供首頁判斷狀態文字
  return Math.max(diffOrig, diffLev, diffCash);
}
