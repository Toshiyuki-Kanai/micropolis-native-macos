# Micropolis Native macOS

2026-10-16に作成した、Micropolisエンジンを利用する変更版のネイティブmacOSアプリです。Electronic Artsの製品ではありません。

macOS 27以降・Apple Silicon向け。Swift 6 / SwiftUI / Canvasと、リポジトリ内の既存`MicropolisNative`ローカルSwift Packageを使います。外部ライブラリー、WebView、Electron、WASM、既存の画像・音声素材は使いません。

## Xcodeで実行

1. `MicropolisMac.xcodeproj`をXcode 27.1以降で開きます。
2. Schemeを`MicropolisMac`、実行先を`My Mac`にします。
3. ⌘Rで実行します。初回都市はランダム生成され、停止状態で表示されます。

ローカル実行用のアドホック署名を既定にしています。配布用の署名・公証は設定していません。App Sandboxは有効です。都市ファイルの読込・保存UIは今回含めていません。

## 操作

- 左上のツール選択、または「建設」メニューで道路・住宅・商業・工業・撤去を選び、マップをクリックします。キー1〜5でも選べます。座標はタイルの中心を指定し、区域はエンジンが3×3の範囲を判定します。
- 道路は濃い灰色、住宅は緑、商業は水色、工業はオレンジです。空き地は薄い緑、森林は濃い緑、水域は青です。
- 水域・森林・既存建物などでの費用・建設可否はエンジンが決めます。拒否理由はアラートに表示します。
- 右上の開始／停止（⌘R）は都市を保持したまま実行状態を切り替えます。実行開始後は一時停止／再開（スペース）も使えます。
- 速度は低速・中速・高速。100msごとに最大8 tickを渡し、速度による進行率はエンジンが決めます。tickと月は1対1ではありません。
- 「＋」は確認後に現在の都市を破棄し、新規生成します。⌘Nは別ウインドウに独立した都市を開きます。
- ウインドウをリサイズすると全マップが収まるように縮尺と余白を再計算します。余白へのクリックは無視します。
- アプリメニューの「ライセンスとクレジット…」で著作権、無保証、GPL、EA追加条件、名称ライセンスの全文を参照できます。

初期段階では発電所・送電線をUIに公開していないため、区域の発展を含む完全なゲームプレイには対応していません。

## ビルド・検証

リポジトリルートから：

```sh
./apps/micropolis-macos/script/build_and_run.sh --verify
./apps/micropolis-macos/script/verify_engine.sh
```

`build_and_run.sh`は既存のMicropolisMacプロセスを終了し、arm64 Debugビルド後に.appを起動します。`--debug`、`--logs`、`--telemetry`も使用できます。既存Web/WASM版や都市ファイルは変更しません。スクリプト再実行時に未保存の都市は失われます。

ビルド成果物は`build/micropolis-macos/`、統合検証プログラムは`build/macos-app-validation/`に置きます。いずれもGit管理対象外です。Xcodeからの通常実行はXcodeのDerivedData設定に従います。

`verify_engine.sh`は既存C++/純粋Cの回帰テストと、実際のアプリソースを使うSwift検証を実行します。道路の資金減算、全建設ツール、時間進行、停止・再開、速度、タイマーループ、4表示サイズの48,000タイル中心点の座標変換を確認します。マクロプラグインを禁止したsandbox内ではコンパイルできません。テストを無効にせず、Xcode/Swiftマクロを実行できる環境で実行してください。

自動検証はGUIクリックの代わりにはなりません。Xcodeで実行後、空き地への道路建設で資金が10減ること、区域の色、開始時の時刻進行、停止・一時停止時の時刻保持、再開、各速度、横長・縦長へのリサイズ後のクリック位置を確認してください。

## ソース構成

- `App/`：SwiftUIのWindowGroup、ウインドウごとのモデル所有、標準メニュー。
- `Services/EngineSession.swift`：専用actorでC API呼び出しを直列化。生成・破棄、状態・12,000タイルのコピー、tick、停止、速度、建設。CポインターをUIへ公開しません。
- `Models/`：Sendableの状態コピーとツール定義、MainActorの表示モデル。キャンセル可能な更新ループで待ち行列や追いつき更新を蓄積しません。
- `Rendering/`：マップ⇔画面座標の変換、下位10ビットのタイルIDによる色分け。
- `Views/`：Canvasへパスをまとめて描画、ツールバー、状態表示、ライセンス。
- `Tests/`：実際のアプリモデルを使用する画面なしの統合検証。
- `MicropolisMac.xcodeproj/`：共有Scheme、既存ローカルPackageへの参照、原本を参照するライセンスのCopy Bundle Resources。

## 現時点の未実装

保存・読込UI、Undo、ドラッグで連続建設、パン・ズーム、発電所・送電線等の追加ツール、ピクセルアート、スプライト、音声、手動予算、通知イベント、シナリオUI、配布用の署名・公証。新規都市や終了前の自動保存はありません。

## ライセンス

GPL version 3 or laterおよびEA追加条件。元のエンジンはCopyright (C) 1989–2007 Electronic Arts Inc.。リポジトリルートの`gpl-3.0.txt`、`MicropolisGPLLicenseNotice.md`、`MicropolisPublicNameLicense.md`をそのままアプリに同梱します。無保証です。対応するソースとビルド手順は本リポジトリに含まれます。

Micropolis is a registered trademark of Micropolis Corporation (Micropolis GmbH) and is licensed here as a courtesy of the owner under the Micropolis Public Name License. <https://www.micropolis.com>
