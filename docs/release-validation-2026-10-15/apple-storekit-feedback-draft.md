# Apple Feedback草稿：TestFlight目录USD，验签交易CNY

状态：2026-10-16 13:37 已使用指定开发者账号提交，正式编号 [FB25209457](https://feedbackassistant.apple.com/feedback/25209457)，页面编号、标题及正文已回读。本人完成隐私同意及最终资料声明。仅文字、0 附件；实际提交的精简正文见 [提交内容](apple-storekit-feedback-submitted.txt)。价格根因未关闭，未收到处理结论。原始设备日志、账本、账号邮箱、交易 ID、appAccountToken 和邀请链接未提交。

## Title

TestFlight StoreKit 2 returns USA/USD catalog, but verified consumable purchases settle in CNY on the same iPhone

## 2026-10-16 update — installed TestFlight 1.0 (13)

The user confirmed that the current Media & Purchases country is mainland China. Build 13 is now installed and independently verified on the same iPhone. A fresh StoreKit product refresh still displays US$0.99 / US$2.99 / US$3.99. Each selected tier and purchase button show the same returned price, and closing/reopening resets the selection.

The user then opened Apple's purchase sheet for `com.yuji.app.support.encourage`: the app displayed US$0.99, while the system confirmation displayed CNY6. The user cancelled without purchasing. This system-sheet observation is user-reported, not an automated screenshot assertion; the environment badge was not separately reported. A readback immediately afterward found no new verified transactions and no semantic changes to the existing receipt journal, ledger or support-invitation data. The CNY verified transactions below belong to the earlier build 7 evidence. Account country was not changed and the user was not signed out.

Build 13 listens to `Storefront.updates`, reloads `Product.products(for:)`, compares Storefront IDs before and after loading, checks the Product currency against Storefront currency when available, and checks the storefront again before purchasing. Purchase uses `onStorefrontChange`. These checks do not resolve the observed discrepancy between returned product metadata and the system sheet. We have not established that production App Store distribution is unaffected.

## Historical environment and receipt evidence

- Physical iPhone 12, iOS26.6.1
- Xcode27.0 (27A266a), Swift6, SwiftUI
- TestFlight1.0 (7), app com.dmlayman.yuji
- Consumable product com.yuji.app.support.coffee, mainland China configured price CNY18
- App Store Connect Sandbox tester country: mainland China
- No local StoreKit configuration in the distributed App Store build; prices use Product.displayPrice directly, with no currency replacement or conversion

## Observed

The app calls Storefront.current and Product.products(for:). Storefront reports USA / 143441-19,29, and Product.displayPrice reports US$2.99 for coffee. The displayed catalog for all three consumables is US$0.99 / US$2.99 / US$3.99.

After the user completed purchase-account authentication, two user-initiated coffee purchases completed. Both StoreKit-verified transactions returned price18 and currencyCNY; both were durably recorded and correlated with their respective attempt tokens. The existing receipt was retained. No real money is charged in Sandbox.

Reopening the support sheet and calling Product.products(for:) again still returned the USD catalog. Storefront.current remained USA. This was verified on the installed TestFlight build with an independent XCTest runner that does not install or relaunch the app under test. The new observation only selects, closes and reopens the sheet; it does not initiate any purchase.

Earlier purchase calls waited in Apple authentication for several minutes. The server response included ExpiredLongLivedToken and the calls eventually returned AMSErrorDomain100. After the user authenticated, subsequent purchases completed. Authentication recovery did not correct the product catalog currency. These are separate symptoms.

## Expected

StoreKit product price, storefront and the actual purchase currency should agree for the active purchase identity. If Apple changes the purchase storefront, the app should receive a supported update so it can refresh the displayed amount before the next user-initiated purchase.

## Reproduction

1. Install this TestFlight build on the affected iPhone.
2. Open the support chooser and request the products via StoreKit2.
3. Observe USA/USD in Storefront and displayPrice.
4. In build 13, the user opens the encouragement purchase sheet: it displays CNY6, versus US$0.99 in the app. Cancel; do not purchase.
5. Historical build 7 coffee purchases also returned verified CNY18 receipts against a US$2.99 catalog quote. These are separate transactions, not build 13 receipts.
6. Close and reopen the chooser; the catalog remains USD. No further purchase is necessary to demonstrate the current mismatch.

## Questions for Apple

1. Can TestFlight product metadata and purchase execution resolve against different account/storefront contexts on this iOS version?
2. Is there a supported way to invalidate the cached product storefront without signing out the user's everyday Media & Purchases account?
3. Which diagnostics can distinguish account-session propagation from a StoreKit service issue?
4. Is this isolated to Sandbox/TestFlight, or is App Store distribution affected as well?

## Related first-hand reports

- [TestFlight catalog and purchase-sheet currency mismatch](https://developer.apple.com/forums/thread/847397)
- [USD product metadata while storefront is FRA/EUR](https://developer.apple.com/forums/thread/845478)
- [DTS response to TestFlight returning USA](https://developer.apple.com/forums/thread/794932)

These reports are comparison evidence, not confirmation of the cause in this app. No assumptions about production behavior, cache-clearing guarantees, or a supported workaround are made.
