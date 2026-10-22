# MicropolisJ v2.0.0とネイティブ版の機能比較

基準：`dheid/micropolis` Tag `v2.0.0`、Commit `4cbac80d8d0052cbc9f4e71130dad212dbe2b492`。2026-10-22。ユーザー承認済み。[ソース同定記録](native-macos-micropolisj-source.ja.md)。Java参照パスはすべてこの固定Commitの`src/main/java/micropolisj/`以下。現在のネイティブ実装と、実機での確認完了は区別する。

## 採用方針（2026-10-23最終確認）

dheid/micropolisの正式v2.0.0をゲーム機能の基準とし、Java版とC++版の内部アルゴリズムの完全一致は必須としない。既存MicropolisCore C++エンジンを維持し、予算・徴税・見積りも現在のC++方式を採用する方針がユーザーに承認された。Javaの期間内積立（escrow）方式への変更は行わない。この方式差自体は統合を妨げる未実装項目ではない。予算表示・実資金増減・サービス効果の整合は回帰テストで確認する。

## 全機能と対応表

分類はコード実装の状態を示し、GUI受け入れ確認済の意味ではない。今回の追加GUIの受け入れはすべて別途必要。「部分実装」は必要な機能情報が不足するもの、「未実装」は呼び出し経路がないものとする。

| 機能 | Java参照箇所 | Javaの動作 | 開始時のSwiftUI | C++対応 | 今回の実装・現状 | 検証方法 |
|---|---|---|---|---|---|---|
| 都市生成・プレビュー | gui/NewCityDialog.java | 仮都市、前/次地形、採用/取消 | 即生成のみ | generateSomeCity | 完全実装済み：独立actorで候補生成、地形履歴、採用前に未保存確認 | seed再現・GUI候補切替/取消 |
| 3難易度・初期資金 | gui/NewCityDialog.java, MainWindow.onDifficultyClicked | 20k/10k/5k、途中難易度変更 | 未実装 | setGameLevelFunds/Level | 完全実装済み：資金リセットは新規時のみ、途中変更と保存 | C API各level・保存再読込 |
| 都市を開く・保存・別名 | gui/MainWindow, engine/Micropolis.load/save | classic .cty、失敗表示 | 実装済 | loadCity/saveFile | 完全実装済み：補助マップ空ならclassic、非空は従来拡張を保持 | Java実コード往復・sandbox保存 |
| 未保存確認・終了 | gui/MainWindow | 新規/開く/終了の確認 | 実装済 | frontend責務 | 完全実装済み：単一都市、キャンセル・外部変更保護 | lifecycle・ユーザーGUI |
| 道路・鉄道・送電線 | engine/MicropolisTool, RoadLikeTool | ドラッグ道路、橋/海底/交差点接続、費用 | 実装済 | doTool | 完全実装済み：C++接続・費用。経路の引き方はネイティブ方式 | 15ツール/C++とSwift試験 |
| 住宅・商業・工業地区 | engine/ToolStroke | 複数地区の矩形配置も可能 | 単一配置 | doTool | 完全実装済み：3×3間隔の矩形配置、仮エンジンの費用・マップを確定前表示 | GUI・成長試験 |
| 消防・警察・発電所2種・競技場・港・空港 | engine/BuildingTool | 1施設の配置位置をドラッグ調整後に確定 | 実装済 | doTool | 完全実装済み：クリックまたはドラッグ終点へ配置、確定前に取消可能 | 15ツールと費用 |
| 公園・撤去 | engine/ToolStroke, Bulldozer | 公園/撤去の矩形選択 | 経路ドラッグ | doTool | 完全実装済み：矩形選択を仮エンジンで実行し、一括確定 | 建設/撤去・資金 |
| 区域調査 | gui/NotificationPane, MainWindow.doQueryTool | 建物、人口密度、地価、犯罪、汚染、成長 | 未実装 | doTool(QUERY)/showZoneStatus | 完全実装済み：actorコピー、無料、地面categoryの既存不具合を境界で補正 | query境界・料金不変・GUI |
| 病院・教会 | engine/MapScanner | 住宅の需要から自動生成 | 生成はC++任せ | 既存住宅更新 | 維持。直接建設ツールはJavaにもない | 都市成長、画像 |
| 建設プレビュー・Escape | gui/MainWindow.previewTool/onEscapePressed, ToolPreview | 実際の仮配置と総費用、確定前取消 | 範囲枠のみ | 内部ToolEffectsあり、公開previewなし | 完全実装済み：C++ doToolをmaps/資金/設定/RNGの仮コピー上で実行。料金・配置プレビュー、Escape取消、全体資金不足なら原子取消 | GUI範囲・費用、制限参照 |
| 開始/停止・一時停止 | gui/MainWindow.startTimer, engine/Speed | 停止と4速度 | 停止と3速度 | speed0..3 | 完全実装済み：4番目はフロント側tick数、pause中は停止 | Swiftタイマー・速度試験 |
| 都市成長・電力・交通 | engine/MapScanner, TrafficGen, Micropolis | 発展/衰退、電力、交通路 | C++で実装済 | 対応 | 完全実装済み：Swiftに再実装しない。数値一致は保証しない | 328k ticks・人口/通電 |
| 需要表示 | gui/DemandIndicator | R/C/I棒グラフ | 評価画面数値 | res/com/indValve | 完全実装済み：常時R/C/I棒グラフと評価画面数値 | C API/GUI |
| 税率・資金配分 | gui/BudgetDialog | 0..20%、道路/消防/警察、要求額/配分額、予測更新/リセット | 税率と配分のみ | core budget | 完全実装済み（採用方式の差あり）：設定/見積り/リセット/決算に対応。見積りはC++の年度末処理を仮エンジンで実行し、Javaの期間内escrow方式とは数値の意味が異なる | funding・年次決算試験 |
| 自動予算/年次確認 | gui/MainWindow.showAutoBudget, engine/Micropolis.isBudgetTime | 決算前に停止して承認 | 自動のみ | callbackは決算を待たない | 完全実装済み：native APIがphase9進入前に停止し、承認後だけ決算 | 二年連続停止・資金不変・再開 |
| 財政明細 | gui/BudgetDialog.makeBalancePane | 直近2期の開始残高/税収/建設/運営/終了残高 | 未実装 | 決算時の実支出は取得可 | 完全実装済み：実決算のコピーを起動中保持し3期表示。未保存（Javaと同じ） | 年次明細/残高式 |
| 都市評価 | gui/EvaluationPane, engine/CityEval | 評価/差分、人口/差分、支持率、資産、規模、難易度、4問題 | 基本値のみ | 全項目あり | 完全実装済み：全評価データをコピーし表示 | options/evaluation・GUI |
| 履歴6系列・10/120年 | gui/GraphsPane, engine/CityHistory | 人口R/C/I、収支、犯罪、汚染、複数選択 | 未実装 | getHistory | 完全実装済み：共通尺度、期間/系列切替、ゲーム内の年の目盛 | 保存バイトと全12系列一致・GUI |
| 全域/住宅/商業/工業/交通網 | gui/OverlayMapView, engine/MapState | 概観マップを分類表示 | 未実装 | tile ID分類 | 完全実装済み：概観と主マップのフィルタ | offscreen描画・GUI |
| 人口密度/成長/地価/犯罪/汚染/交通量/電力/消防/警察 | gui/OverlayMapView | 9主題マップ、凡例 | 電力枠のみ | 9 Map群 | 完全実装済み：core値をworldGetで120×100へ展開、主/概観へ描画 | 全マップコピー・GUI凡例 |
| 概観マップ移動 | gui/OverlayMapView | 表示枠、クリック/ドラッグ移動 | 未実装 | UI責務 | 完全実装済み：表示枠・クリック/ドラッグで中心移動 | GUI・座標試験 |
| パン/ズーム | gui/MainWindow, MicropolisDrawingArea | スクロール、ホイール、メニュー | 実装済 | UI責務 | 維持＋メニュー拡縮 | 48k座標・GUI |
| 自動撤去 | gui/MainWindow.onAutoBulldozeClicked | ON/OFF | 常時既定値 | setAutoBulldoze | 完全実装済み：メニューと保存 | options・拒否試験 |
| 災害ON/OFF・6手動災害 | gui/MainWindow, engine/Disaster | 火災/洪水/怪獣/竜巻/地震/メルトダウン | 実装済 | 対応 | 維持、スプライト描画を追加 | 全6災害・GUI |
| 地震の揺れ | gui/MainWindow.EarthquakeStepper | 一時的に画面が揺れる | 未実装 | startEarthquake callback | 完全実装済み：callbackをコピーして3秒の揺れ、揺れ中はtickを進めない | GUI/差異 |
| 都市メッセージ・到達人口・災害位置 | gui/MessagesPane, NotificationPane | ログと位置/通知表示 | 未接続 | sendMessage callback | 完全実装済み：128件の有界コピー、通知一覧・場所へ移動。画像通知パネルは簡略化 | drain/上限/GUI |
| タイルアニメーション | gui/MicropolisDrawingArea, engine/Micropolis.animate | フレーム更新、停止 | 実装済 | animateTiles | 完全実装済み | 1024ID/flags/32frames |
| 列車/ヘリ/飛行機/船/怪獣/竜巻/爆発 | engine/*Sprite, gui/MicropolisDrawingArea.drawSprite | エンジン移動とフレーム描画 | 未表示 | spriteList/moveObjects | 完全実装済み：7種、57フレーム、可視範囲描画、pause停止 | sprite C API・素材全フレーム/GUI |
| 効果音・ON/OFF | engine/Sound, gui/MainWindow.citySound | 建設/失敗/爆発/交通/汽笛/怪獣等 | 無音 | makeSound callback | 完全実装済み：core通知と建設/失敗をNSSound再生。画面外の低い汽笛を抑止。音色と発音タイミングはC++/GPL原音に従う | WAV検証・音の実機確認 |
| キーボード | gui/MainWindow/setupKeys, strings/CityMessages.properties | メニュー短縮キー、ツール、Escape | 主要操作あり | UI責務 | 完全実装済み：macOS短縮キー、矢印パン、拡縮、Escape取消。Java固有のキー割当は再現しない | GUIメニュー |
| 学校直接建設 | engine/MicropolisTool | 存在しない | なし | なし | Java版にも存在しない。追加しない | enum16種 |
| 地形エディタ | guiメニュー/全tool経路 | 地形生成以外の公開編集なし | なし | C++内部toolあり | Java版にも存在しない。追加しない | 全tool/メニュー調査 |
| シナリオ | engine/Micropolis.java | コメントのTODOのみ、公開機能なし | なし | C++には対応あり | Java版にも存在しない。追加しない | 全ソース検索/公開メニュー |
| BGM | engine/Sound、全ソース | 音楽再生機能なし | なし | なし | Java版にも存在しない。追加しない | sound経路/全ソース検索 |
| バス | engine/SpriteKind/Sprite | enumはあるが生成なし・作成するとError | なし | C++内部にはある | Java版にも公開実行機能なし。追加しない | factory/生成経路 |
| Undo/自動保存 | 全ソース/メニュー | 存在しない | なし | なし | Java版にも存在しない。追加しない | 全ソース/メニュー |

## エンジンの差異と影響

- 成長・電力・交通：共通祖先のアルゴリズムだがJavaのTileSpec metadata/MapScannerとC++のbit flag/zone.cppでは処理順・乱数・更新周期が違う。Javaは2 animationで1 step、C++は16 phaseとspeedCycleによる間引き。seed一致や人口推移の逐次一致は達成条件としない。成長、通電、交通と需要の機能をC++のまま提供する。
- 人口・都市評価：Java CityEvalとC++ evaluate.cppは人口係数/問題投票/評価の更新タイミングが同一とは限らない。UIはC++の評価値、差分、問題投票を直接表示する。
- 徴税：Javaは期間内の`collectTaxPartial`をescrowへ集計して年度末に精算。C++は`collectTax`で年度末のtotalPop/地価/税率から求める。係数RLevels/FLevelsは共通でも、Javaはround、C++は切り捨てが入る。Javaと同じライブ予測値を得るための税収ロジック移植は行わない。
- 予算：C++ callback `showBudgetAndWait`には非同期承認を待たず支出する既知のFIXMEがある。共有C++を改変せず、native APIが`phaseCycle==9 && cityTime%48==0`の実行前に止める。承認時刻を記録し、同じ決算で二度止まらない。承認前はresumeを拒否する。承認待ちのphaseを.ctyで保存できないため、承認前の保存も明示エラーにして既存ファイルを保護する。税計算・支出は元のcoreのみ。
- 自動予算のサービス効果：coreの自動予算分岐は、実際には配分率分だけ支出するのに、サービス効果用のroadSpend/fireSpend/policeSpendへ全要求額を記録する既存不整合がある。native境界で決算完了後にcore自身のroadValue/fireValue/policeValueを用い、updateFundEffectsを呼ぶ。共有srcとWebは変更しない。財政明細は資金の実差分で記録し、誤った旧Spend値を表示しない。自動予算・道路配分0で効果0と運営支出0を試験する。
- 災害：C++にはscenario/event/バス等Java公開版で使わない機能も存在。今回UIにはJavaの6災害だけを維持する。乱数と被害の具体的位置・回数は一致保証しない。
- 保存：両者ともbig-endian履歴6×240 short、misc120 short、column-major120×100マップ。C++拡張はさらに補助mopを付け51120 bytes。Java File loaderはサイズ>27120なら128-byteヘッダーと見なすので拡張ファイルを誤読する。SwiftUIは27248-byteの古典Macヘッダー付き都市を私有コピーで正規化して既存C APIへ渡す。元ファイルは変更しない。native旧APIは変更せずclassic保存APIを追加。SwiftUIは補助mapが全0ならclassicを選び、非0なら拡張形式を維持してデータ欠落を防ぐ。後者はJavaのFileメニューでは互換でない。
- core loaderはdoSimInitで初期スキャンを実行する。原本都市とJava再保存都市を別々にロードすると、乱数によって読込直後の派生タイルが既に違う場合がある。互換試験は保存された12,000IDを厳密比較し、C APIの復元資金/時刻/設定と実継続を別に検証する。これはテストを無効化する対応ではなく、保存バイトと実行状態を区別するもの。
- Javaはmapの一部flagsをTileSpecから再構成し、C++はrawflagsを保持。Javaに存在しない拡張church ID956以降はJava側で解釈できない。既存のC++拡張機能を削除して全都市をJava互換にする変更は行わない。
- 難易度：既存C++ loader/saveFileはmisc15の難易度を復元・更新していなかった。native境界で標準misc15を設定/復元する。既存保存レイアウトは変更しない。速度はJava0..4、C++0..3。読込は安全のため停止状態、再開速度はネイティブ既定値。
- 共有`src/`およびWeb/WASM API/ビルド経路は変更しない。追加C APIとnativeコールバックだけで機能を公開する。

## まとめて実装する計画

1. 固定ソースの公開ゲーム機能を上表で棚卸しし、C++のMap/history/query/eval/options/通知/spriteをコピー専用APIで公開する。既存ABI構造体を拡張しない。
2. actor経由でSwiftUIの主題マップ・概観・履歴・調査・評価・通知・都市候補/難易度・予算操作を結合する。保存のスコープ/原子置換/外部変更保護を維持する。
3. 元GPL版の固定Git blobと照合したスプライト/効果音をネイティブ描画・音声へ接続し、出典/ライセンス/再生成検査を同梱する。Javaの未知の追加音源を転用しない。
4. C API、Swift実actor、描画、sandbox保存、Java相互読み込み、Web構造/既存試験、長時間実行を検証する。GUI固有の未検証操作と採用方式の差を明記し、内部仕様の完全一致と誤認させない。

## 検証記録

最終ビルド・試験結果は以下へ追記する。機能同等性の最終判定は実機GUI受け入れ確認まで保留する。

### 自動検証結果（2026-10-22、M1実機）

macOS 27.0.1 (26A434)、Xcode 27.1 (27A9275)、Apple Swift 6.4。生成アプリの実行ファイルは`lipo -archs`でarm64。

| 確認 | 結果 |
|---|---|
| Xcode Debug / arm64 / 既存Swift Packageリンク | 成功。ソースをXcodeプロジェクトへ追加する別設定は不要、既存ファイルと既存resources folderを拡張 |
| C++/C API core/api/gameplay/animation/parity | 成功。全15建設、人口/通電、328,000 ticks、20回の生成/haight読込、6災害を含む |
| 追加C API | 成功。9 overlay、12 history、query、難易度保存、決算前停止/承認、保存保護、原子的建設、全体費用見積り、道路予算0の支出/効果0、有界イベント/スプライト/音声 |
| Swift実EngineSession/CityModel | 成功。全15ツール、描画座標48,000点、ドラッグ、矩形4地区400、preview/RNG一致、取消、保存ゲート、見積り、128-byteヘッダー付都市、保存/再生成/復元継続、haight |
| AddressSanitizer + UndefinedBehaviorSanitizer | 成功、上記C/C++ 5 suite |
| 原画像・音声・ライセンス | 元のtile検査に加え68原本のSHA-256/Git blobと57変換PNGを検証。11 WAVはmacOS NSSoundでdecode成功。再生の聴感確認は含まない |
| Canvas | 実描画の1x/2x、全57sprite frameと座標offset、完全透明フレームの背景保持、画像欠損fallback、保存都市/haight、200 simulation/render更新が成功 |
| Java正式v2.0.0の実コード | 検証対象の全engineソース/tiles.rc/版情報をハッシュ固定。Gradleや外部pluginを実行せずjavacでコンパイル |
| C++→Java File loader→Java保存→C API→継続 | 成功。12,000タイルIDの保存データ、資金/時刻、難易度/税率/自動撤去等。classic形式で検証 |
| Web/WASM既存テスト | 13ファイル80件成功。最初の2件はsandboxのtsx IPC EPERMだったため、コード/テストを変更せず通常実行環境で再試験 |
| 実アプリ起動/初期表示 | 新しいプロセスをopen -nで起動。ネイティブwindowと地形/需要/概観マップの表示をウインドウ撮影で確認。既存アプリを終了させていない |
| ウインドウ実行試験 | 試験専用windowで終了の待機、再表示時登録、既存delegate転送、毎回の未保存保護が成功 |
| sandbox実保存試験 | 使い捨て都市への実ファイルgrantで、旧方式の失敗/既存保護と、新規保存/上書き/再読込/復元の成功を確認 |
| 配布リソース | 生成.app内のGameplay128ファイルと元のGPL/EA/名称ライセンスがソースと一致 |
| Git | feature/micropolisj-parity、未Commit。保護対象src/Web/WASM/既存都市/既存素材/元ライセンスは差分なし。diff --check成功 |

描画計測はDebugのローカル試験：全域画像のcold生成約41ms、100回の画像再利用約176ms、cache56画像/12,288,000 bytes、Canvas rasterize 1x約39ms・2x約9ms。これはオフスクリーンの測定であり、全ての主題マップを表示したGUIの継続FPSや数時間稼働の保証ではない。57spriteのRGBA cacheは約0.44 MiB。メモリを無制限に増やさない。

実行ログ・撮影・Javaクラス・試験都市は`build/micropolisj-parity/`等のGit管理対象外に置く。画像/音声のソースと配布用変換結果は意図したリソースであり、ビルドキャッシュではない。

### 統合前の最終再検証（2026-10-23、M1実機）

- arm64 Debugビルドと既存Swift Packageリンク、署名検証、arm64実行ファイル、新規プロセスのネイティブウインドウ起動に成功。
- C++/C APIの5 suite、実EngineSession/CityModel、Canvasの1x/2x・57スプライト・11 WAVのデコード、保存/再読込/haight、Sandbox実保存、ウインドウ終了保護、固定Java v2.0.0とのclassic保存往復を再実行して成功。
- 予算回帰を補強し、手動年次承認直前の見積りと承認後の実資金残高・税収・運営費が一致することを確認。配分0の実支出と道路サービス効果0、財政明細の残高式も成功。C++方式は維持した。
- ASan/UBSanの5 suite、Web側13ファイル80件を再実行して成功。共有C++ src・Web/WASM・既存都市・元素材・既存ライセンス原本の変更はない。
- 追加素材68原本と57 PNGのハッシュ・変換内容、Gameplay全128ファイルとライセンス文書の.app同梱を再確認。ビルド、ログ、試験都市はGit管理対象外。
- 今回は自動試験と起動確認であり、下記の新GUI手動受け入れ・音声の聴感・数時間のGUI稼働を実施済みとは扱わない。以前の版に対するユーザー実機確認とは区別する。

### 実機GUIで確認する操作

1. 新規都市の前/次地形、3難易度と初期資金、採用/取消。取消で元都市を失わず、採用時は必要な未保存確認が出ること。
2. 道路/鉄道/送電線の経路ドラッグ、RCIの矩形配置、公園/撤去の矩形、施設のドラッグ位置調整。マウスを離す前の費用・画像、Escape取消、全体資金不足の取消、橋/海底接続を確認。
3. 14種類のマップ選択、概観のクリック/ドラッグ、矢印・Shift矢印、ピンチ/ホイール、リサイズ後の建設位置。消防/警察の管轄と電力・交通の変化を見る。
4. 区域調査の6項目、需要バー、評価の差分/4問題、6系列グラフの10/120年と年目盛、通知の場所への移動。
5. 自動予算をOFFにして年末まで進め、停止→配分/税率の見積り→リセット→適用/承認→再開。承認前保存を拒否して元ファイルを保護すること。道路予算0の道路状態/都市への影響も確認。
6. 全7種の移動sprite、地震の3秒の揺れ、効果音ON/OFF、画面外の汽笛、一時停止/再開と4速度。音色はGPL原版でありJavaと同一ではない。
7. 保存→アプリ終了→再起動→再読込→継続。未保存確認、保存パネル取消、最近使った都市、haight、大きな都市の長時間GUI操作。

### 未完了・既知の制限と完成判定

- 調査したJava公開ゲーム機能について、操作/データ取得の実装経路を接続した。ただし新GUIの上記受け入れ検証は未完了で、全機能同等性の完成とは判定しない。既存版についてユーザーが確認済みの結果を今回の追加機能へ流用しない。
- 財政予測はユーザー承認のC++方式を採用する。現在人口/地価による年度末見積りを提供し、Javaの期間内escrowを積み上げる税収方式は移植しない。同じ税収曲線・成長曲線・災害・乱数列になることは保証しない。この内部方式差の変更は今回の対象外。
- 既存の拡張mop/教会タイルは保持し、Javaへ合わせて欠落させない。このデータを含む都市はJavaの通常Fileローダーと完全互換ではない。標準classic都市での往復は実証済み。
- 新しいJava由来のゲーム機能を推測で増やさない。地形エディタ/シナリオ/BGM/学校直接建設/バス/Undo/自動保存は基準Java版の公開実行機能にないので追加しない。
- UIは単一都市windowを維持。Java UIの複製、すべてのJava固有キー割当、同一音源、配布用署名/公証は対象外。今回の音源は権利を確認したGPL原版。
- 長時間自動試験は加速tickと200回の描画更新。数時間のGUI連続稼働は未検証。

変更範囲は`apps/micropolis-macos/`のApp/Models/Services/Views/Rendering/Tests/script/README/Xcode設定/Gameplayリソース、`packages/micropolis-engine/native/`の追加API、native.mk、nativeテスト2本、README.native.md、およびこの比較表とソース同定記録。元Javaソース自体は製品に取り込んでいない。全素材名と固定出典はGameplay/provenance.json、変換結果名はgenerated.jsonに列挙。
