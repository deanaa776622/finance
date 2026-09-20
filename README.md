# Finance

長期資產記錄 — iOS（SwiftUI）+ 既有網頁原型。

## iOS App

打開 `Finance.xcodeproj`，選模擬器後 Run。

v1：手動記資產 → 看總淨值與配置是否大致平衡（無即時股價、無每日漲跌）。

```bash
xcodebuild -project Finance.xcodeproj -scheme Finance \
  -destination 'generic/platform=iOS Simulator' build
```

## Web prototype

靜態 HTML（`index.html`、`stock.html` 等），僅作概念參考。
