/**
 * glow.js - 動態資產配置 Glow 背景引擎
 * 自動連動 stock.html 儲存於 LocalStorage 的資產配置金額
 */

function updateGlowBackground() {
  // 1. 讀取 stock.html 寫入的各類別總金額 (以台幣為單位)
  const allocOrig = parseFloat(localStorage.getItem('alloc_original')) || 0;
  const allocLev = parseFloat(localStorage.getItem('alloc_leverage')) || 0;
  const allocCash = parseFloat(localStorage.getItem('alloc_cash')) || 0;

  const total = allocOrig + allocLev + allocCash;

  // 2. 計算真實佔比 (0 ~ 1)
  let ratioOrig = 0.5; // 預設值 (若無資料時)
  let ratioLev = 0.3;
  let ratioCash = 0.2;

  if (total > 0) {
    ratioOrig = allocOrig / total;
    ratioLev = allocLev / total;
    ratioCash = allocCash / total;
  }

  // 3. 獲取或建立背景燈光 Glow 容器 DOM
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
      opacity: 0.6;
      transition: opacity 0.5s ease;
    `;
    document.body.prepend(glowContainer);
  }

  // 4. 動態更新背景 Radial-Gradient (結合原型藍、槓桿綠、現金黃)
  // 燈光範圍 (Stop %) 根據各自持股比例大小動態渲染
  const pOrig = Math.max(10, Math.round(ratioOrig * 60));
  const pLev = Math.max(10, Math.round(ratioLev * 60));
  const pCash = Math.max(10, Math.round(ratioCash * 60));

  glowContainer.style.background = `
    radial-gradient(circle at 20% 20%, rgba(56, 189, 248, ${0.15 + ratioOrig * 0.25}) 0%, transparent ${pOrig}%),
    radial-gradient(circle at 80% 30%, rgba(74, 222, 128, ${0.15 + ratioLev * 0.25}) 0%, transparent ${pLev}%),
    radial-gradient(circle at 50% 80%, rgba(250, 204, 21, ${0.15 + ratioCash * 0.25}) 0%, transparent ${pCash}%)
  `;
}

// 頁面載入時自動執行一次
document.addEventListener('DOMContentLoaded', updateGlowBackground);
