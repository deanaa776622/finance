/**
 * glow.js - 原始經典動態 Glow 背景引擎
 */

function updateGlowBackground() {
  const allocOrig = parseFloat(localStorage.getItem('alloc_original')) || 0;
  const allocLev = parseFloat(localStorage.getItem('alloc_leverage')) || 0;
  const allocCash = parseFloat(localStorage.getItem('alloc_cash')) || 0;

  const totalNetWorth = allocOrig + allocLev + allocCash;

  // 1. 資產規模連動放大
  let netWorthScale = 1.0;
  if (totalNetWorth > 0) {
    netWorthScale = 0.8 + Math.min(1.2, Math.log10(totalNetWorth / 100000) * 0.4);
    if (netWorthScale < 0.8) netWorthScale = 0.8;
  }

  // 2. 注入Keyframe漂浮動畫
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
        opacity: 0.65;
        pointer-events: none;
        will-change: transform;
      }
    `;
    document.head.appendChild(styleEl);
  }

  // 3. 建立 DOM 容器
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
      <div id="orb-orig" class="glow-orb" style="top: -10%; left: -10%; background: #38bdf8; animation: floatOrb1 18s ease-in-out infinite;"></div>
      <div id="orb-lev" class="glow-orb" style="top: -5%; right: -10%; background: #4ade80; animation: floatOrb2 22s ease-in-out infinite;"></div>
      <div id="orb-cash" class="glow-orb" style="bottom: -15%; left: 20%; background: #facc15; animation: floatOrb3 20s ease-in-out infinite;"></div>
    `;
    document.body.prepend(glowContainer);
  }

  // 4. 更新尺寸
  const baseSize = 360 * netWorthScale;
  const orbOrig = document.getElementById('orb-orig');
  const orbLev = document.getElementById('orb-lev');
  const orbCash = document.getElementById('orb-cash');

  if (orbOrig) { orbOrig.style.width = `${baseSize}px`; orbOrig.style.height = `${baseSize}px`; }
  if (orbLev) { orbLev.style.width = `${baseSize}px`; orbLev.style.height = `${baseSize}px`; }
  if (orbCash) { orbCash.style.width = `${baseSize}px`; orbCash.style.height = `${baseSize}px`; }
}

document.addEventListener('DOMContentLoaded', updateGlowBackground);
