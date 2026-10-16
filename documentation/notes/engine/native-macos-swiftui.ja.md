# Micropolis Native macOS — SwiftUI初回実装・検証

2026-10-16（日本時間）。対象mainの基準コミットは`b9e67f36a512d233884b99dd5b3b7a0da3c60be2`。既存C++エンジン、C API、Swift Package、既存テストは変更していない。

## 1. 実装した画面と機能

SwiftUIの標準WindowGroup・ツールバー・メニューを使用するmacOS 27以降／arm64アプリを追加した。ウインドウごとに独立した都市を所有する。起動時はランダム都市を生成し、停止状態で表示する。

Canvasに120×100タイルをタイルIDごとのパスとしてまとめて描く。道路・住宅・商業・工業を色分けし、地形・森林・水域等も単色表示する。12,000個のSwiftUI Viewを生成しない。MapGeometryで表示倍率・余白と論理タイル座標を分離する。

道路、住宅、商業、工業、撤去をクリックで実行できる。費用・範囲・建設可否はC++エンジンが判断する。資金不足・撤去必要・建設拒否等をアラートに表示する。開始・停止、独立した一時停止・再開、速度1〜3を提供し、資金・人口・年月・内部時刻を表示する。新規都市への置換には確認を設けた。

EngineSession actorがC API操作と所有権を直列化する。UIにはSendableの状態・12,000タイルのコピーのみを渡す。生成・更新等のC呼び出しはMainActor上で行わない。100msごとに最大8 tickを実行し、描画と更新を分離する。停止中はstepを呼ばない。追いつき更新を蓄積しない。Viewのタスクをキャンセルすると更新ループが終了する。結果にはactor内で単調増加する配送番号を付け、古い非同期結果が新しい状態を上書きするのを防ぐ。致命的な内部エラー・メモリー不足ではハンドルを退役させ、新規都市生成で復帰できる。

ライセンスとクレジットのウインドウを追加し、GPL本文、EA追加条件、名称ライセンスはリポジトリの原本を参照してアプリへコピーする。既存素材は同梱しない。

## 2. Xcodeプロジェクト

`apps/micropolis-macos/MicropolisMac.xcodeproj`。共有Scheme：`MicropolisMac`。

`../../packages/micropolis-engine`をXCLocalSwiftPackageReferenceとして参照し、既存のMicropolisNative productをリンクする。Swift 6、macOS 27、arm64、App Sandbox有効。ローカル実行用アドホック署名。配布用の署名・公証は未設定。

## 3. ビルド結果

Apple M1／macOS 27.0.1／Xcode 27.1／Swift 6.4で、次の入口からarm64 Debugビルドに成功した。

```sh
./apps/micropolis-macos/script/build_and_run.sh --verify
```

内部では`xcodebuild -project apps/micropolis-macos/MicropolisMac.xcodeproj -scheme MicropolisMac -configuration Debug -destination 'platform=macOS,arch=arm64' -derivedDataPath build/micropolis-macos build`を使用する。

生成物は`build/micropolis-macos/Build/Products/Debug/MicropolisMac.app`。実行ファイルはMach-O arm64。プロジェクト構文をplutilで検証し、Xcodeで開く操作も成功した。Xcode画面自体を操作してのビルドは未実施。

## 4. 実行結果

.appをLaunchServicesから起動し、プロセスの継続と画面上のウインドウ（1100×860ポイント）を確認した。ウインドウ画像を取得し、Canvasの地形マップ、資金20,000、人口0、1900年1月、停止状態、ツールバー、凡例を目視確認した。

画像：`build/macos-app-validation/window.png`。ログ：`build/macos-app-validation/build-and-launch.log`。

## 5. 建設・シミュレーションの検証

```sh
./apps/micropolis-macos/script/verify_engine.sh
```

実際のEngineSession・CityModel・CityFrame・MapGeometryをSwift 6でコンパイルした画面なしの検証プログラムを実行し、以下が成功した。

- seed 12345の都市生成と12,000タイル取得、初期一時停止。
- 道路を空き地(2,2)に建設し、タイル変化と資金20,000→19,990。
- 住宅・商業・工業地区のタイル変化と資金減算、道路の撤去。
- 2,000 tickで時刻0→125。一時停止中の2,000 tickで時刻不変、再開後の進行。
- 一時停止中の速度1・2・3の保持。
- CityModelの実際のタイマーループ、開始・停止、一時停止・再開、速度変更、キャンセル。
- 横長・縦長・端数サイズを含む4サイズで、全48,000タイル中心点の描画→クリック座標の往復一致。右下端・余白・ゼロサイズの境界確認。
- 既存native.mkのC++/純粋C APIテストすべて成功。haight読込後2,000 tickで4839→4964、8シナリオ各1,100 tick、保存互換性、エラー、並行読取、ライフサイクル等も成功。

ログ：`build/macos-app-validation/engine-tests.log`。**実ウインドウへのマウスクリック、実ウインドウのリサイズ、一時停止等のボタンクリックは自動確認していない。** 座標変換・操作モデルの成功とGUI実操作を区別する。

GitHub反映前に、ユーザーからM1実機での道路建設、資金減算、住宅地区の配置、シミュレーション開始、一時停止・再開、リサイズ後のクリック位置がすべて正常だったとの確認を得た。これはユーザーによるGUI実操作の確認であり、Codexの画面なし自動検証とは別の証拠として扱う。

## 6. 未実装

保存・読込UI、Undo、ドラッグ連続建設、パン・ズーム、発電所・送電線等の追加ツール、画像・スプライト・音声、手動予算、通知イベント、シナリオUI、配布用署名・公証。発電・送電ツールがないため区域発展を含む完全なゲームプレイには未対応。自動保存はない。

## 7. 発見した問題

- sandbox内のSwiftコンパイルはObservationマクロプラグイン実行を拒否された。必要な実行権限で再実行し成功。マクロやテストを無効化していない。
- 初期プロジェクトのheadermap設定警告を`ALWAYS_SEARCH_USER_PATHS=NO`で解消した。
- 実装レビューで致命的エラーと通常の建設拒否の区別、およびハンドル再生成後の古い結果の扱いを修正し、関連検証を再実行した。
- ツールバーの再開アイコンを利用可能な標準シンボルに修正した。
- エンジンには既存の整数縮小変換・未使用のloadScenarioでNULL文字列を構築する警告が残る。今回のフロントエンド経路に新しい障害は確認されず、エンジン変更はしていない。

## 8. 変更ファイル一覧

すべて新規ファイル。

```text
.codex/environments/environment.toml
apps/micropolis-macos/.gitignore
apps/micropolis-macos/App/MicropolisMacApp.swift
apps/micropolis-macos/MicropolisMac.xcodeproj/project.pbxproj
apps/micropolis-macos/MicropolisMac.xcodeproj/xcshareddata/xcschemes/MicropolisMac.xcscheme
apps/micropolis-macos/Models/CityFrame.swift
apps/micropolis-macos/Models/CityModel.swift
apps/micropolis-macos/README.ja.md
apps/micropolis-macos/Rendering/MapGeometry.swift
apps/micropolis-macos/Rendering/TilePalette.swift
apps/micropolis-macos/Services/EngineSession.swift
apps/micropolis-macos/Tests/EngineIntegration.swift
apps/micropolis-macos/Views/CityMapView.swift
apps/micropolis-macos/Views/ContentView.swift
apps/micropolis-macos/Views/LicenseView.swift
apps/micropolis-macos/script/build_and_run.sh
apps/micropolis-macos/script/verify_engine.sh
documentation/notes/engine/native-macos-swiftui.ja.md
```

## 9. git statusと保護対象

初回実装完了時はmainブランチのまま、上記18ファイルのみ未追跡（??）。既存追跡ファイルの変更なし。この時点ではCommit、Push、PR作成を行っていない。

既存エンジン、Web版、都市・素材、ライセンスの計3,137ファイルで開始時と終了時のSHA-256一致を確認した。ビルド・検証成果物、ログ、ウインドウ画像はGit管理対象外のbuild/に置いた。

## 10. ユーザーがXcodeで確認する操作

1. Xcodeでプロジェクトを開き、MicropolisMac／My Macで⌘R。
2. 停止中のマップで空き地に道路をクリックし、道路の灰色と資金10減算を確認。
3. 各地区を十分な空き地へ置き、3×3の色分けと費用を確認。道路を撤去する。
4. 開始で時刻が進み、一時停止で止まり、再開で進むことを確認。速度を切り替える。
5. 停止で都市が保持され、再開始できることを確認。
6. 横長・縦長にウインドウを変更し、表示とクリック位置が一致すること、余白が建設対象にならないことを確認。
7. ＋で新規都市への確認、アプリメニューでライセンス表示を確認。

Micropolis is a registered trademark of Micropolis Corporation (Micropolis GmbH) and is licensed here as a courtesy of the owner under the Micropolis Public Name License. <https://www.micropolis.com>
