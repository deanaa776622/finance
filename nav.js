// 1. 動態插入導覽列的 CSS 樣式
const navStyle = document.createElement('style');
navStyle.innerHTML = `
  .bottom-nav {
    position: fixed;
    bottom: 0;
    left: 0;
    right: 0;
    height: 50px;
    background-color: #1e293b;
    border-top: 1px solid #334155;
    display: flex;
    justify-content: space-around;
    align-items: center;
    z-index: 1000;
  }
  .nav-item {
    display: flex;
    justify-content: center;
    align-items: center;
    flex: 1;
    height: 100%;
    color: #94a3b8;
    text-decoration: none;
    font-size: 0.95rem;
    transition: color 0.2s ease-in-out;
  }
  .nav-item.active {
    color: #38bdf8;
    font-weight: bold;
    border-top: 2px solid #38bdf8;
  }
  body {
    padding-bottom: 70px !important;
  }
`;
document.head.appendChild(navStyle);

// 2. 在這裡統一設定你的所有選單項目 (未來要增減選項，只改這裡即可！)
const navItems = [
  { name: '首頁', url: 'index.html' },
  { name: '儲蓄試算', url: 'saving.html' },
  { name: '資產淨值', url: 'stock.html' },
  { name: '資產配置', url: 'allocation.html' }
];

// 3. 自動判斷當前網址並渲染至頁面最下方
document.addEventListener("DOMContentLoaded", function () {
  // 取得當前檔名 (若直接存取網域則預設為 index.html)
  let currentPath = window.location.pathname.split('/').pop() || 'index.html';

  const navContainer = document.createElement('nav');
  navContainer.className = 'bottom-nav';

  navItems.forEach(item => {
    const a = document.createElement('a');
    a.href = item.url;
    a.className = 'nav-item';
    a.innerText = item.name;

    // 比對網址，自動把當前頁面標示為 active
    if (currentPath === item.url) {
      a.classList.add('active');
    }

    navContainer.appendChild(a);
  });

  document.body.appendChild(navContainer);
});
