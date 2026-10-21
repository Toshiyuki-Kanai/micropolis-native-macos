# Micropolis Native macOS — Gameplay実装・検証

2026-10-21更新。作業開始時（2026-10-17）のmain `3559f1404e470985ea647759b29a8c8709469331`がクリーンであることを確認し、originとの一致とff-only取得後に`feature/gameplay-completion`を作成した。今回のユーザー実機確認を経て、Forkのmainへ反映する対象を記録する。

## 1. 実装機能

新規・開く・保存・別名保存、標準パネル、未保存確認（新規／開く／閉じる／終了）、最近の都市10件、Finder／LaunchServicesの.cty受渡しを追加した。保存時は受理済み建設と実行中tickが完了してからファイル処理へ進む。失敗・キャンセルは現在の都市と未保存状態を保持する。保存先が外部で変更された場合は、内容比較で上書きを拒否する。同一プロセスの重複ファイル編集も避ける。

道路・鉄道・送電線・公園・撤去のドラッグ、4方向経路補間、重複除外、最大64件ごとのactor処理、パン・ピンチ／ホイールズーム、1〜12倍、表示リセット、境界制限、リサイズ、建設範囲プレビューを追加した。

15種類の実在ツールを公開した。住宅・商業・工業・道路・鉄道・送電線・公園・石炭・原子力・警察・消防・スタジアム・港・空港・撤去。病院は住宅需要に応じて自動生成される。学校と病院の直接建設ツールは既存エンジンに存在しないため追加していない。

税率0〜20%、道路・警察・消防の配分、年次税収・必要費用、評価点・支持率・都市規模・資産・RCI需要・交通・汚染・犯罪、通電区域数を表示・操作できる。自然災害切替と6災害の手動発生（確認付き）を追加した。シミュレーション・金融・建設判定はC++に委ね、Swiftに再実装していない。

## 2. 未実装

Undo、自動保存、移動スプライト描画、音、通知イベント一覧、グラフ・密度マップ、シナリオUI、地形・ネットワーク編集UI、手動の年次予算承認、配布用署名・公証。怪獣等の破壊処理は動くが、移動する姿は描画しない。病院・学校の架空の建設機能は作っていない。

## 3. C API

既存`MPSnapshot`の64バイトレイアウト、既存ツールID、ABI v1、.cty形式を維持した。新規`MPDetails`と以下のnative-only APIを追加した。

| API | 内容 |
|---|---|
| `mp_get_details` | 財政・評価・電力・需要・環境・オプションのコピー |
| `mp_configure_budget` | 税率・配分の一括設定、自動予算の有効化 |
| `mp_set_disasters` | 自然災害の切替 |
| `mp_trigger_disaster` | 火災・洪水・竜巻・地震・怪獣・メルトダウン |
| `mp_build`追加ID10〜15 | 原子力・警察・消防・スタジアム・港・空港 |

既存`doTool`、`setCityTax`、`setAutoBudget`、災害メソッドを呼ぶ。無効引数と非有限の配分値を拒否し、既存mutex・例外境界を使用する。財政設定の実際の徴税と配分調整は次のエンジン年次決算に委ねる。

## 4. SwiftUIと安全性

EngineSession actorがCハンドルとファイルのsecurity-scoped accessを所有する。NSFileCoordinator内で既存C APIの読込を呼び、保存はmacOSのitemReplacementDirectory内へC APIで書き出してからFileManagerで保存先を置き換える。ファイル内容の外部変更を検出し、古い都市からの上書きを防ぐ。生成・読込のトランザクション失敗では、C APIの契約に従って以前のハンドルを保持する。その他の破損し得る変更操作で致命的な失敗があればハンドルを退役させる。

MainActorはコピーされたCityFrameと表示状態だけを扱う。更新ループは100ms間隔・最大8 tickで、追いつき更新を蓄積しない。配送番号で古い結果の上書きを防ぐ。保存ダイアログ中は入力・更新を凍結する。致命的エラー後に古い建設入力を新都市へ流さない。

AppKitはパネル、入力NSView、ウインドウdelegate、アプリ終了・外部ファイルイベントに限定した。SwiftUIの元のwindow delegateには他のイベントを転送する。閉じると終了では非同期に保存確認する。既存インスタンスの未保存都市を破棄しないよう、build_and_run.shの強制終了を取り除いた。

描画は独自の単色・幾何学模様・文字。可視タイルだけをCanvasへまとめて描き、道路の交通量、鉄道・送電線・RCI・施設・発展段階・区域中心の通電を区別する。導電タイルの黄色枠は導電性の表示であり通電保証ではない。既存画像・音声は組み込んでいない。

## 5. ビルド・実行

Apple M1、macOS 27.0.1、Xcode 27.1、Swift 6.4。arm64 DebugビルドとMicropolisNative Swift Packageリンクに成功。App Sandboxとuser-selected read-write／app-scoped bookmark entitlementを有効にしたローカル用アドホック署名。

```sh
xcodebuild -project apps/micropolis-macos/MicropolisMac.xcodeproj \
  -scheme MicropolisMac -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath build/micropolis-macos build
./apps/micropolis-macos/script/verify_engine.sh
make -f packages/micropolis-engine/native.mk SANITIZE=1 -j4 \
  CXX='xcrun clang++ -arch arm64' CC='xcrun clang -arch arm64' test
```

実アプリを起動し、LaunchServicesから試験用保存都市を渡して、道路・送電線・RCI・発電所と資金・日付の復元を目視確認した。初回は外部ファイルイベントがSwiftUIに届かない問題を発見し、AppDelegateでの受渡しへ修正して再確認した。試験ファイルはbuild/内のみ。

読込直後の人口・評価は既存ローダーの仕様により未再集計の場合がある。SwiftUIは「人口 集計待ち」と表示し、開始後にエンジンの実数値へ切り替える。乱数列・派生マップ・停止状態を完全保存する独自形式には変更していない。

## 6. 検証結果

| 検証項目 | 結果・範囲 |
|---|---|
| arm64 Debug／Packageリンク | 成功 |
| 既存C++／純粋C API回帰 | 全成功。保存バイト列、失敗I/O、8シナリオ等を維持 |
| 新規都市生成 | CとSwiftで成功 |
| 15建設ツール | Cと実際のEngineSessionで全成功・費用減算確認 |
| 道路・送電線ドラッグ | 実際のCityModelで各15接続タイルを処理し、150／75の資金減算 |
| パン・ズーム後の座標 | 自動変換・逆変換・境界検証に成功。ユーザーのパン・ズーム操作も確認済み |
| 電力供給・人口増加 | 新規の空都市に道路・RCI・石炭・送電線を配置し、通電14区域・人口増加を確認 |
| 時間・停止・再開・速度 | Cと実際のCityModelのタイマーループで成功 |
| 保存・復元・継続 | エンジン破棄・再生成後に資金・時刻・税率・資金配分・道路を復元し、人口を再集計して継続 |
| 保存失敗・外部変更 | 既存ファイルと未保存都市を保護。外部変更の上書きを拒否 |
| haight.cty | C／Swiftで成功。Cで4839→4964の進行、生成／読込20サイクル |
| リサイズ | 4サイズ48,000中心点とパン・ズーム後の可視タイルの座標検証に成功 |
| 長時間 | 328,000 tickの加速実行完走。数時間のGUI連続稼働試験ではない |
| 災害・予算・評価 | 6災害、後続tick、設定検証、保存後の復元が成功 |
| ASan／UBSan | core_test・api_test・gameplay_testが診断なしで成功。LeakSanitizer合格を意味しない |
| Web／WASM既存回帰 | 13ファイル・80テスト成功 |
| 実GUI | Codexは起動・描画・外部ファイルオープンを確認。主要ゲームループはユーザーが実機確認済み（次節） |

Cテストの人口は時計で再seedされるエンジン仕様により試行間で変動するが、電力と人口増加を明示的にassertしている。保存の配分率は既存16.16精度の範囲で照合した。

ログ：`build/gameplay-validation/{app-build.log,swift-tests.log,sanitizer.log,web-tests.log,protected-check.log}`。画面：`build/gameplay-validation/loaded-city.png`。ネイティブ・Swift検証用都市もbuild/に置く。

## 7. ユーザー実機GUI確認（2026-10-21）

ユーザーより、新規都市、道路ドラッグ、住宅・商業・工業、発電所・送電線、シミュレーション進行、人口増加、パン・ズーム、税率・予算変更、保存、アプリ再起動後の読込と継続、未保存確認ダイアログ、保存パネルのキャンセルがすべて正常との報告を受けた。最重要のゲームループはユーザー確認済みである。これはCodexの自動GUI操作の結果ではない。

複数ウインドウでの終了のみ未確認であり、1.0では単一都市ウインドウを正式仕様とした。その他、全15ツール・災害の個別GUI操作、最近使った都市、閉じた都市ウインドウの再表示など、報告に含まれない操作をユーザー確認済みとは扱わない。C／Swift／AppKit自動試験の範囲とも区別する。

## 8. Web／WASMへの影響

共有C++のsrc/、Webアプリ、都市・素材、ライセンス原本は変更していない。開始時と終了時に計3,124ファイルのSHA-256一致を確認した。既存WASM/JS/dataも保護対象に含む。既存生成物を使用した全80テストが成功した。Emscriptenでの再ビルドは行っていない。追加APIはnativeの境界のみで、既存ブラウザーbindingや公開JS APIを変更していない。

Web検証で不足していた既存vitamoo/mooshowのdistをlockfile準拠の依存から準備した。依存manifestとlockfileの変更はなく、新規アプリに外部依存を追加していない。

## 9. 変更ファイル一覧

```text
apps/micropolis-macos/App/Info.plist
apps/micropolis-macos/App/MicropolisMac.entitlements
apps/micropolis-macos/App/MicropolisMacApp.swift
apps/micropolis-macos/MicropolisMac.xcodeproj/project.pbxproj
apps/micropolis-macos/Models/CityFrame.swift
apps/micropolis-macos/Models/CityModel.swift
apps/micropolis-macos/README.ja.md
apps/micropolis-macos/Rendering/MapGeometry.swift
apps/micropolis-macos/Rendering/MapInputView.swift
apps/micropolis-macos/Rendering/TilePalette.swift
apps/micropolis-macos/Services/CityFiles.swift
apps/micropolis-macos/Services/CityWindowBridge.swift
apps/micropolis-macos/Services/EngineSession.swift
apps/micropolis-macos/Tests/EngineIntegration.swift
apps/micropolis-macos/Tests/SandboxSaveProbe.swift
apps/micropolis-macos/Tests/WindowLifecycle.swift
apps/micropolis-macos/Views/CityMapView.swift
apps/micropolis-macos/Views/CityPanels.swift
apps/micropolis-macos/Views/ContentView.swift
apps/micropolis-macos/Views/LicenseView.swift
apps/micropolis-macos/script/build_and_run.sh
apps/micropolis-macos/script/verify_engine.sh
apps/micropolis-macos/script/verify_sandbox_save.sh
apps/micropolis-macos/script/verify_window_lifecycle.sh
documentation/notes/engine/native-macos-gameplay.ja.md
packages/micropolis-engine/README.native.md
packages/micropolis-engine/native.mk
packages/micropolis-engine/native/api.cpp
packages/micropolis-engine/native/include/micropolis_native.h
packages/micropolis-engine/tests/native/gameplay_test.c
```

## 10. Git状態

作業ブランチは`feature/gameplay-completion`。ゲーム機能・native API・テスト・資料のみを公開対象とし、ビルド・ログ・依存キャッシュ・検証都市・画像はGit管理対象外とする。GitHubの反映先は`Toshiyuki-Kanai/micropolis-native-macos`のmain。

## 11. 完成判定

**単一都市ウインドウの1.0候補として、主要ゲームループを実機確認済み。** 中心のゲームループはCとSwiftの自動試験と、今回のユーザー実操作で成功した。ソースをmainに反映する判定であり、配布用署名・公証や全機能のGUI試験完了を意味しない。

## 12. 残る課題

報告に含まれないGUI操作と継続使用での調整、数時間のGUI連続稼働・高密度都市のフレーム計測、未実装機能の優先順位付け、配布を行う場合の署名・公証と対応ソース提供。既存の整数縮小変換・loadScenarioのNULL文字列警告は今回の共有エンジン変更範囲外として残る。

## 13. 2026-10-21 保存エラー修正

ユーザー実機操作で初回保存時に`city I/O failed or unsupported city file`が発生した。従来のCLI統合試験はApp Sandboxで実行されておらず、標準パネルで選んだ1ファイルへの権限を検証していなかった。

独立した署名済みApp Sandbox検証アプリへ、使い捨て.ctyをLaunchServicesで渡した。旧処理の`mp_save_city`は隣接`.tmp.XXXXXX`作成を拒否され、元ファイルを保持したまま`MP_IO_ERROR`になった。C APIと保存形式は変更せず、Swift側でOSの同一ボリューム置き換え用ディレクトリへ保存した後、`replaceItemAt`（既存ファイル）／`moveItem`（新規）で反映するよう修正した。ディレクトリへの保存は事前に拒否する。失敗時は元の都市・未保存状態を維持する。

`bash apps/micropolis-macos/script/verify_sandbox_save.sh`で旧エラー再現、新規保存、上書き、別エンジンでの再読込と資金・時刻・税率復元に成功。日本語と空白を含むファイル名で確認した。既存C++/C API・Swift統合試験とarm64 Debugビルドも成功。ログは`build/gameplay-validation/save-fix-{engine,sandbox,build}.log`。この保存修正直後の時点では、標準保存パネル等の実操作は未確認だった。その後のユーザー確認は第7節に記録した。既存の実行中アプリを終了せず、未保存都市は破棄していない。

使用API：[Apple FileManager.itemReplacementDirectory](https://developer.apple.com/documentation/foundation/filemanager/searchpathdirectory/itemreplacementdirectory)、[replaceItemAt](https://developer.apple.com/documentation/foundation/filemanager/replaceitemat(_:withitemat:backupitemname:options:))。

## 14. 1.0候補の最終確認（2026-10-21）

旧実装はWindowGroupと新規ウインドウコマンドによる複数都市を想定していたが、ユーザーの許可に従い、SwiftUIのWindowへ変更して1プロセス1都市に限定した。新規ウインドウコマンドを削除し、起動時の都市表示を明示した。ライセンスの補助ウインドウは別途維持する。閉じる許可を閉じる通知でリセットし、同じNSWindowを再利用して表示する場合も登録を復元する。以前の閉じる許可で、再表示後の未保存確認を回避しない。

最終arm64 Debugビルド・Swift Packageリンク・実アプリ起動と地形表示に成功。C++／C API・実際のSwiftモデル統合・App Sandbox保存・ASan／UBSan・既存Webの13ファイル80テストが成功した。AppKitの独立テストでは、閉じるの非同期判定、再表示時の登録、元delegateへの通知転送、閉じる許可のリセット、キャンセル後の未保存状態保持を確認した。ウインドウ試験は専用NSApplicationイベントループで実行し、成功マーカーまで到達したことをスクリプトでも確認する。ログは`build/gameplay-validation/final-{build,window-tests,sandbox-save,sanitizer,web-tests}.log`、起動画面は`final-startup.png`。

変更対象30ファイルの内容と差分を確認した。ビルド成果物・ログ・個人の絶対パス・認証情報は公開対象に含めない。既存Web／WASM、共有エンジンsrc、都市・素材・ライセンス原本、依存manifest／lockfileは変更していない。既存のGPL・EA追加条件・名称ライセンス表示を維持した。

Micropolis is a registered trademark of Micropolis Corporation (Micropolis GmbH) and is licensed here as a courtesy of the owner under the Micropolis Public Name License. <https://www.micropolis.com>
