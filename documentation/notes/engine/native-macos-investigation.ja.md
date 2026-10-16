# Micropolis Native macOS：初回技術調査・Linux検証

調査日：2026-10-16（日本時間）。対象コミット：`9d5b400b2d3beaf81e4103056f6c7f503dfde6e1`。

## 1. 結論：ネイティブ化は可能か

**可能。ただし、現状のコードをそのまま製品として使用できる状態ではない。**

WebAssemblyを使わず、既存のC++本体25翻訳単位をGCCでコンパイル・リンクし、マップ生成、道路設置、資金の減算、1,000回のシミュレーション更新を実行できた。JavaScriptランタイム、ブラウザー、Emscripten SDK、Node.jsはこの検証のビルド・実行に不要だった。

一方、サニタイザーによる検証では既存の範囲外アクセスを検出した。既存都市 `haight.cty` のロード経路ではスプライト生成でクラッシュし、保存処理ではLP64の型幅による上書きも確認した。「計算をネイティブ実行できる」ことと「安全で互換性のあるゲームが完成している」ことは分ける必要がある。

Apple Silicon上のコンパイル・実行は未検証。今回のホストはLinux x86_64であり、macOS SDK、Xcode、SwiftUIのビルドは実行していない。

## 2. 難易度：中

エンジンの切り出しとC API接続は**中**。既存の計算アルゴリズムの移植量は小さく、主な作業は初期化、通知、ファイル形式、オブジェクト寿命の整理になる。

オリジナルに近い操作感・描画・音・災害・予算・シナリオ・保存互換性まで備える製品全体は**高**。今回、公開可能な完成品までの所要時間は見積もっていない。

## 3. エンジンの構造

### リポジトリ全体

| 場所 | 役割・ネイティブ版での扱い |
|---|---|
| `packages/micropolis-engine/src/` | C++エンジン本体。今回の主要調査対象 |
| `packages/micropolis-engine/makefile` | C++17、Emscripten/EmbindによるWASM生成 |
| `apps/micropolis/` | SvelteKitのゲームUI、CLI、WASMローダー。UIはSwiftUIで再実装 |
| `packages/tile-renderer/`, `render-core/` | JavaScript/TypeScriptの描画パッケージ。ネイティブでは直接使用しない |
| `content/micropolis/` | `cities/`, `data/`, `images/`, `sounds/`, `tilesets/` |
| `packages/vitamoo/`, `mooshow/`, `sims-io/`, `optical-codec/` | 他の機能・アプリ向け。最小エンジンに不要 |
| `apps/vitamoospace/`, `apps/yoot/` | 別アプリ・関連コンテンツ |
| `apps/screen-angel/` | 独立したElectronアプリ。別ライセンス。今回の製品には含めない |
| `documentation/`, `images/`, `skills/`, `scripts/` | 文書、資料、操作スキル、開発補助 |
| `package.json`, `pnpm-workspace.yaml`, `pnpm-lock.yaml` | pnpmモノレポ構成 |

本ゲームエンジンは `.cpp` / `.h` で構成される。別アプリのネイティブコードやCMakeをMicropolisのビルドシステムと取り違えないこと。Micropolisエンジン向けのXcodeプロジェクトやSwiftパッケージは見当たらない。

### C++本体

`micropolis.h` の `Micropolis` クラスが状態と操作を保持する。

| ファイル | 主な処理 |
|---|---|
| `micropolis.cpp`, `initialize.cpp`, `allocate.cpp` | 初期化、更新入口、メモリー確保 |
| `simulate.cpp`, `zone.cpp` | シミュレーションの段階実行、区域の成長 |
| `traffic.cpp`, `power.cpp`, `scan.cpp` | 交通、送電、汚染などの集計 |
| `budget.cpp`, `evaluate.cpp`, `graph.cpp` | 財政、市民評価、履歴 |
| `generate.cpp`, `random.cpp` | マップ生成、乱数 |
| `tool.cpp`, `connect.cpp` | 建設ツール、道路等の接続 |
| `sprite.cpp`, `animate.cpp`, `disasters.cpp` | 移動物体、タイルアニメーション、災害 |
| `fileio.cpp` | `.cty` の入出力 |
| `callback.h`, `frontendmessage.*`, `message.cpp`, `update.cpp` | フロントエンドへの通知 |

マップは120×100、1タイルは16ビット。`map[x][y]` の連続順序は `x * WORLD_H + y`。下位10ビットの `LOMASK = 0x03ff` がタイル番号で、上位ビットは電力や区域などの状態。追加の `mop` マップもある。Web版の `TileView.svelte` は16×16ピクセルのタイルを使用する。

主な更新経路は `simTick()` → `simLoop()` → `simFrame()` → `simulate()`。計算は複数フェーズに分割されており、更新回数とゲーム内時刻は1対1ではない。今回の条件では1,000 tickで `cityTime` が0から63になった。

### Web/WASMとの依存境界

| 対象 | 依存と対応 |
|---|---|
| `emscripten.cpp` | EmbindでC++をJSに公開。ネイティブターゲットから除外 |
| `js_callback.h` | `emscripten::val`、JSメソッド呼び出し。ネイティブでは使用しない |
| `callback.cpp` | `<emscripten.h>` と `EM_ASM` / `EM_ASM_` でconsoleへ通知。ネイティブ実装に差し替え |
| `callback.h` / `micropolis.h` | callback引数に `emscripten::val` が露出。既存の非Emscripten向け仮定義で今回のビルドは可能。ただしコメント上はエディター・解析用であり、正式なネイティブABIではない |
| `micropolisengine_lib.js` | 現在はコメントのみ。計算ロジックはない |
| `micropolisengine_template.html` | WASM出力用のHTML shell。不要 |
| makefile | `--preload-file ...cities@cities/` で都市データを仮想FSへ格納。ネイティブでは通常のファイルパスに置換 |
| `apps/micropolis/src/lib/MicropolisSimulator.ts` 等 | 初期化、JS callback、タイマー、WASM heap参照、UI状態同期。Swift側で担当 |

既存ビルドは `pnpm build:engine` → パッケージの `make install` → `em++`。`install` は生成済み `.wasm/.data/.js/.d.ts` をWebアプリへコピーするため、今回使用していない。ルートmakefileはさらにWeb UIとDoxygenを扱う。CIもEmscriptenビルドを前提とする。

計算本体にDOM/WebGL依存は見当たらない。`simulateRobots` / `simulateChurch` 等の拡張は通知先に委ねられるため、検証用の無処理callbackではそのフロントエンド動作は再現していない。

### ネイティブ化に必要な最小変更

1. WASM用2翻訳単位を除外する独立ビルドターゲットとNativeCallbackを追加する。WASM側のmakefileと出力先を共有しない。
2. `Micropolis` の `mapBase`, `mopBase`, `callback` などを確実に初期化し、callbackを登録してから `init()` を実行する。今回の検証では構築前の生ストレージをゼロ化して回避した。これは検証用の迂回策であり、製品ではコンストラクターを修正する。
3. `evaluate.cpp` の `voteProblems` の境界判定を修正する。`problem > PROBNUM` では添字 `PROBNUM` を許してしまう。
4. `SimSprite` のC++オブジェクト構築と破棄を正しくする。現状は `malloc` 相当の `newPtr` で確保したオブジェクトの未構築 `std::string` に代入している。
5. `fileio.cpp` の保存形式を明示的な32ビット値・16ビットワードとして読み書きし、`short*` から `Quad*` へのキャストを除く。`Quad = long` は今回8バイト、WASMでは4バイト。型定義全体の一括変更より、まずファイル境界を修正する。
6. C APIを追加してSwiftにC++内部型と `emscripten::val` を公開しない。正式なcallback contextの抽象化はWASM回帰確認と一緒に行う。

2〜5は今回の調査で見つかった問題であり、既存ソースにはまだ適用していない。範囲外アクセスとスプライトの寿命問題は、ネイティブ固有と断定できるものではない。

## 4. ライセンス上の注意点

以下は実際の文書に基づく。現在の配布ストア規約や全アセットの権利まで承認済みという意味ではない。

### コードと元のSimCity由来部分

根拠はルート `LICENSE`、`MicropolisGPLLicenseNotice.md`、`gpl-3.0.txt`、および `micropolis.h` 等の先頭表示。

- EA由来コードは **GPL version 3 or later + GPL第7条に基づく追加条件**。EAの表示は `Copyright (C) 1989 - 2007 Electronic Arts Inc.`。
- 配布時には著作権表示、GPL本文、追加条件を維持する。変更版であることと変更日を明示し、元のプログラムそのものと誤認させない。
- GPL第5条・第6条から、C APIで接続した単一のSwiftUIアプリは、アプリ・ブリッジ・エンジンを含めGPL適合の結合作品として配布する方針が必要。Cラッパーや静的ライブラリー化で非公開化できる、という設計にはしない。
- バイナリ配布時は対応するソースとビルドに必要なスクリプト等を、採用する第6条の方法で受領者に提供する。上流リポジトリのURLだけでは自分の変更版の提供にならない。ダウンロード配布なら対応ソースにも同じ場所から追加料金なしで到達できる形が実用的。
- 私的なビルド・変更だけで一般公開義務が発生するわけではない。GPLは販売も禁止していない。配布先の権利と再配布を制限しないことが必要。
- GUIには「このアプリについて／ライセンス」等から著作権、無保証、GPL、ソース入手先を参照できる表示を用意する。
- SwiftUIを使うだけで不可能になる条項は確認されない。GPL第1条のSystem Librariesの扱いとApple SDKの条件を踏まえる。Mac App Storeについてはこのリポジトリに適合保証がなく、追加制限を禁じるGPL第10条との整合を別途確認する。初期配布は署名・公証したアプリと対応ソースの直接配布を検討する。

追加条件には商標・宣伝上の権利を付与しないこと、EAとの提携を示唆しないこと、特定の契約責任を引き受ける場合のEAに対する補償もある。

### SimCity名・ロゴ・素材

`MicropolisGPLLicenseNotice.md` は、変更版を **SimCityという商標を使って配布することを明示的に禁止**する。EA商標の権利も付与しない。製品名や公式ロゴを流用しない。コードを使えることから、他のSimCity製品の画像・音声・パッケージ等の権利まで得られるとは扱わない。

`content/micropolis/` の都市、タイル、音、画像について、今回のファイル調査では素材ごとの十分な権利台帳や専用ライセンスは確認できなかった。ルートREADMEのライセンス欄は「Code」と「Name」に分けている。`documentation/notes/engine/ASSETS.txt` は素材の要求一覧であり権利許諾書ではない。`data/notices.xml` もゲーム内通知データであってライセンス通知ではない。

したがって、全バンドル素材の再配布を一律に許諾済みとは断定しない。採用するタイル・音・都市データを絞り、出所と許諾を記録する。確認前のプロトタイプ描画には単色や自作タイルを使える。

### Micropolis名

根拠は `MicropolisPublicNameLicense.md` と `LICENSE` 後半。

- 「Micropolis」はMicropolis GmbHの登録商標で、コードのGPLとは別の名称ライセンス。
- 文書上の許諾は非商用用途向けで撤回可能。接頭辞・接尾辞付きの派生名にも条件が適用される。
- ソースのwelcomeページやタイトルページ、クレジット等に商標帰属を表示し、名称ライセンスも伝達する。
- 宣伝素材への使用には書面許可の条件があり、独自のドメイン・サブドメイン・目立つアカウント名としての使用にも制限がある。販売を考える場合は別名称の採用または書面許諾を検討する。

推奨表示文：

> Micropolis is a registered trademark of Micropolis Corporation (Micropolis GmbH) and is licensed here as a courtesy of the owner under the Micropolis Public Name License.

可能な箇所では `https://www.micropolis.com` にリンクする。本報告もこの名称のゲームとソースについての調査であり、この帰属を明記する。

### サードパーティーと別ライセンス

今回コンパイルした25本体ファイルのincludeはプロジェクト内ヘッダーとC/C++標準・POSIX APIであり、SDL、GTK、Tcl/Tk、Python、外部描画ライブラリーの追加導入は不要だった。標準ライブラリーやツールチェーンのライセンスを無視できるという意味ではない。

実際のインストール済みファイルを確認した主なWeb依存：

| 依存 | 確認したファイルとライセンス | ネイティブ版 |
|---|---|---|
| Svelte 5.55.5 | `node_modules/.pnpm/svelte@5.55.5/node_modules/svelte/LICENSE.md`：MIT | 不要 |
| SvelteKit 2.59.1 | インストール先の `@sveltejs/kit/LICENSE`：MIT | 不要 |
| Vite 5.4.21 / 6.4.1 | インストール先の `vite/LICENSE.md`：coreはMIT。バンドル依存の表示も含む | 不要 |
| TypeScript 5.9.3 | `node_modules/.pnpm/typescript@5.9.3/node_modules/typescript/LICENSE.txt`：Apache-2.0 | 不要 |
| gray-matter 4.0.3 | インストール先の `gray-matter/LICENSE`：MIT | 不要 |
| yaml 2.8.4 | `node_modules/.pnpm/yaml@2.8.4/node_modules/yaml/LICENSE`：ISC | 不要 |
| Fira Mono 4.5.10パッケージ | `package.json` はMIT。`metadata.json` のフォント許諾は外部URLで、同梱のフォント許諾本文は確認できず | SF等のシステムフォントを推奨。フォントファイルの再利用は未確認 |

MIT/ISCのコードを組み込んで配布する場合はその著作権・許諾文を残す。Apache-2.0はライセンスと適用されるNOTICE等を維持する。これらのWeb依存を使わないネイティブ製品へ一律に同梱する必要はない。

インストール済みパッケージをname/versionで重複排除した354件のメタデータ台帳を `build/native-investigation/npm-license-inventory.{json,md}` に保存した。MIT以外にISC、Apache、BSD、MPL-2.0等がある。この台帳は全モノレポの参考調査であり、ネイティブアプリの依存一覧や全ファイル監査ではない。manifest未記載の `union` は実際の `LICENSE` でMIT文面を確認した。

`apps/screen-angel/LICENSE.md` は **source-available / 非オープンソース** と明記し、販売・再配布・派生版公開には書面許諾が必要。ルートGPLをモノレポ全体へ無条件に適用してはいけない。このアプリのコード・素材は採用対象外。

## 5. Linuxネイティブビルドの結果

### 環境と検証方法

- Linux x86_64、GCC/G++ `14.2.0`、C++17。追加パッケージのインストール、ネットワーク取得はしていない。
- 既存の27個の `.cpp` のうち `emscripten.cpp`, `callback.cpp` を除いた25個をコンパイル。
- 検証用 `native_callback.cpp` は `ConsoleCallback` の全35メソッドを無処理で実装。JavaScript実行やゲーム計算の代替はしていない。
- `smoke.cpp` はコンストラクターの未初期化ポインターを回避するため、確保した生ストレージをゼロ化してからplacement newで構築。callbackを登録して `init()` を呼ぶ。
- すべての検証コード、バイナリ、セーブ、ログを既存 `.gitignore` が除外する `build/native-investigation/` に配置。

概略コマンド（正確なソース一覧は同ディレクトリの `*-command.txt`）：

```sh
# リポジトリルートで実行。これらの検証スクリプトもGit管理対象外。
python3 build/native-investigation/run.py
python3 build/native-investigation/run-bounds.py
```

`run.py` は通常版と `-fsanitize=address,undefined -fno-omit-frame-pointer` 版をビルドし、basic/city/saveの3条件を実行する。失敗条件もログを保存して終了コードを表示する。

### 結果を区別した一覧

| 検証 | 結果 |
|---|---|
| オリジナルの `callback.cpp` をそのままG++で解析 | `emscripten.h` 不在で失敗。切り離し対象であることを確認 |
| C++本体25ファイル＋ネイティブ通知アダプターのコンパイル・リンク | 成功。通常版・サニタイザー版ともビルド可能 |
| 初期化・seed 12345での生成 | 成功。マップchecksum `5197755926554722231` |
| 道路ツール | 成功。資金20,000 → 19,990、マップ変化を確認 |
| 通常版の1,000 tick | 成功。`cityTime 0 → 63`, `roadTotal=1` |
| 未修正本体のASan実行 | 失敗。`evaluate.cpp:298` のstack-buffer-overflow |
| 通常版で既存都市 `haight.cty` を実行 | SIGSEGV。既存都市の動作成功とは判定しない |
| 保存・再ロードの限定比較 | マップ、資金、時刻は一致。ただし履歴上書きがあり、保存互換性合格とは判定しない |
| 調査コピーで評価処理の境界のみ修正したASan実行 | basicは1,000 tick完走。既存都市は別のスプライト構築問題で失敗。保存はUBSanが不正アラインメントを検出 |
| macOS / arm64 / SwiftUI | 未実行 |

### 不具合の実証と制限

1. **都市評価の範囲外アクセス**：`evaluate.cpp:298` で `problemTable[PROBNUM]` を読み、場合によって `problemVotes` も範囲外に書く。調査コピー `evaluate-bounds.cpp` の1か所だけを `>` → `>=` にして後続の検証を行った。元ファイルは変更していない。
2. **スプライト構築**：境界修正版でも、`haight.cty` のロード時に `loadFile` → `doSimInit` → 空港 → `newSprite` → `std::string::operator=` でクラッシュ。`sprite.cpp:114` の生メモリー確保と `:117` の代入が根拠。
3. **保存形式とLP64**：実測 `short=2`, `int=4`, `long=8`, `Quad=8`。`miscHist[10,11]` に入れた `1234,2345` と `[64,65]` の `3456,4567` は、保存後にすべて0へ変化した。32ビット形式の2ワードを扱う場所で8バイト書いている。UBSanは `fileio.cpp:420`, `:435`, `:443` 等の不正アラインメントも報告した。
4. **資金配分の読み込み**：`fileio.cpp` は変換後の値を再び未変換のキャストで上書きし、さらに `initFundingLevel()` は配分を1.0へ戻す。保存・ロードで配分値を本当に維持できるかも修正とテストが必要。今回の1.0のみの比較では合格を示せない。
5. **リーク検査の環境制限**：LeakSanitizerはこの実行環境でptrace制約によるfatal errorになった。評価境界修正版のbasicを `ASAN_OPTIONS=detect_leaks=0 UBSAN_OPTIONS=halt_on_error=1` で再実行すると終了コード0。これはアドレス・未定義動作検査を通した最小経路であり、リーク検査成功ではない。

通常実行の成功ログだけで未定義動作がないとは扱わない。サニタイザーの失敗を無視して製品化へ進めず、上記を先に修正する。

主なログは `smoke-basic.log`, `smoke-city.log`, `smoke-save.log`, `smoke-sanitized-basic.log`, `bounds-basic-no-lsan.log`, `bounds-city.log`, `bounds-save-strict.log`。WASMとネイティブの同一tickでの状態一致や全シナリオの検証は未実施。

## 6. SwiftUIへの統合方針

### C ABIと所有権

SwiftUI → SwiftのEngineSession → C API → C++ `Micropolis` という構成を推奨する。ObjC++は必須ではない。SwiftからはCモジュールの公開ヘッダーだけをimportする。

設計案（今回未実装）：

```c
#include <stddef.h>
#include <stdint.h>

typedef struct MPGame MPGame;
typedef int32_t MPResult;  /* 明示した成功・失敗コード */
typedef struct {
    int64_t city_time;
    int64_t funds;
    int64_t population;
    int32_t speed;
    int32_t paused;
    uint64_t revision;
} MPSnapshot;

/* 実ヘッダーはextern "C"ガードを持つ。失敗時out_gameはNULL。 */
MPResult mp_create(MPGame **out_game);
void mp_destroy(MPGame *game);
MPResult mp_generate(MPGame *game, int32_t seed);
MPResult mp_step(MPGame *game, uint32_t ticks);
MPResult mp_set_speed(MPGame *game, int32_t speed);
MPResult mp_set_paused(MPGame *game, int32_t paused);
MPResult mp_get_snapshot(MPGame *game, MPSnapshot *out_snapshot);
/* 120*100要素。出力順序はrow-major y*120+xと仕様に明記する。 */
MPResult mp_copy_tiles(MPGame *game, uint16_t *out_tiles, size_t capacity);
MPResult mp_tool_down(MPGame *game, int32_t tool, int32_t x, int32_t y);
MPResult mp_tool_drag(MPGame *game, int32_t tool,
                      int32_t x0, int32_t y0, int32_t x1, int32_t y1);
MPResult mp_load_city(MPGame *game, const char *utf8_path);
MPResult mp_save_city(MPGame *game, const char *utf8_path);
/* 型付きMPEventを利用者側バッファへコピー。文字列の寿命も仕様化する。 */
/* mp_poll_event(game, out_event) はイベントがない場合も区別する。 */
```

C++例外はC境界内で捕捉し、失敗コードへ変換する。`long`、C++クラス、`std::string`、JS値をABIへ出さない。Swiftはopaque handleを一度だけ破棄し、C++側はcallbackを所有する。既存の `setCallback` は前のcallbackをdeleteするため、二重解放を避ける。

更新・入力・ロード・保存は、1都市につき同じ直列実行コンテキストで行う。まずイベントをキューに貯め、呼び出し後にSwiftへコピーする形が扱いやすい。計算中にSwiftUIへ同期callbackして再入しない。`showBudgetAndWait` は計算を一時停止して予算UIを表示し、ユーザー操作後に再開する設計が必要。

### XcodeとUI

推奨構成は独立した `apps/micropolis-macos/` のXcodeアプリと、ローカルSwift Packageの `MicropolisNative` C/C++ターゲット。既存C++を参照し、ソース選定でWASMファイルを除外する。SwiftソースとC++ソースは別ターゲットにし、CヘッダーをClang moduleとして公開する。元のエンジンを別コピーに分岐させない。SwiftPM側の既存ソース配置に合わせたpath・exclude設定は実装時に確定する。

アプリは `App/`, `Views/`, `Models/`, `Services/EngineSession`, `Rendering/`, `Resources/`, テストを分ける。初期は `WindowGroup` で1都市を扱う。ファイルメニュー、toolbar、ツール一覧、資金・日付表示を備える。保存が安定した段階で、都市ごとの `DocumentGroup` とDocumentモデルへ進める。

### 描画・入力・更新

- 最初はSwiftUI `Canvas` でタイルを描画し、同じタイル群を画像／アトラスとしてまとめる。12,000個のSwiftUI Viewは作らない。48KB程度のmap+mopコピーは初期設計として扱いやすい。
- 当初は自作・単色タイルで機能を検証する。既存アートは許諾確認後に追加する。ピクセルアートはnearest samplingを用い、Retinaでも論理座標と画像ピクセルを混同しない。
- スプライト、オーバーレイ、ズームを加えて描画性能が不足する場合はMetal/MTKViewへ移行する。エンジンと描画APIを結合しない。
- マウス座標をパン・ズーム変換の逆変換でタイル座標に戻し、境界チェック後に `toolDown` / `toolDrag` へ渡す。費用・接続判定をSwift側で再実装しない。
- 通常のクリック／ドラッグに加え、精密なマウス移動、ホイール、修飾キーが必要なら小さなAppKit入力ビューを使う。メニューとキーボードにもツール・速度・一時停止を公開する。
- タイマーは専用直列キュー／actorが管理し、固定のtick数を速度に応じて進める。描画更新とは分離し、MainActorには状態スナップショットを渡す。追いつき処理には上限を設け、重い都市でUIを塞がない。
- タイルアニメーションと移動物体の表示も別途取り出す。一時停止時に何を動かすかを既存ゲームと比較する。

### セーブ・ロードとarm64

ファイル形式の修正後、`.cty` の27,120バイト版とmap+mopを持つ51,120バイト版、big-endianの16ビットワードを維持する。単なる自己往復だけでなく、既存都市・既知のバイト列・資金・時刻・予算率・履歴・map/mopを比較する。成功判定をcallbackだけに頼らずAPIの結果として返す。

Swift側のファイル選択／Document処理で許可されたURLを受け取り、sandbox有効時はsecurity-scoped accessの寿命を入出力全体で維持する。シナリオの相対パスはBundle内の絶対パスに解決し、カレントディレクトリーへ依存させない。保存は一時ファイル＋置換等で既存ファイルを保護する。

Apple Siliconはlittle-endian / LP64であるため、今回のLinux LP64検証で見つかった型幅問題は事前に解消する。ポインターは整数のWASM heap addressとして渡さず、opaque handleまたはコピーを使用する。乱数の `UQuad` 幅や整数演算、既存の `IS_INTEL` マクロも点検するが、名前だけからx86専用とは判断しない。まずarm64単独でXcodeビルドし、Intel対応は必要になった時点で検討する。

## 7. 最短の開発計画

1. **エンジンを安定化**：独立ネイティブターゲット、コンストラクター初期化、評価の境界、スプライト寿命、32ビットファイルI/Oを小さく修正する。Linuxでサニタイザー付きの生成・既存都市・保存互換テストを通し、WASM側も回帰確認する。
2. **C APIを固定**：生成、tick、状態取得、map/mopコピー、道路・区域・撤去、一時停止、保存・ロード。C++内部の変更がSwiftへ波及しない形にする。
3. **Codex Local + Xcodeでarm64検証**：まずUIなしで同じ試験を実行し、その後SwiftUIのウィンドウ、単色マップ、資金・日付、速度を表示する。
4. **最小操作可能版**：パン・ズーム、道路と住宅等のツール、保存・再ロードを追加する。「起動→都市生成→建設→時間進行→保存→再起動して復元」を受け入れ条件にする。
5. **体験と配布を仕上げる**：許諾確認済みアート、音、予算・評価・災害、シナリオ、メニューを実装し、署名・公証・対応ソース・ライセンス表示を整える。

今回は1のための調査と検証まで。SwiftUI実装・Xcodeプロジェクト作成は開始していない。

## 8. 次にCodexへ依頼すべき具体的な作業

> この調査報告を根拠に、Micropolisエンジンの独立したLinux/macOSネイティブビルドターゲットと最小C APIを追加してください。既存WASMターゲットと生成物は維持してください。まず未初期化ポインター、voteProblemsの境界、SimSpriteの構築・破棄、LP64での.cty入出力を修正し、生成・道路・1,000 tick・haight.ctyの実行・既知バイト列との保存互換性を検証してください。可能ならWASMテストも実行してください。SwiftUI実装はまだ開始せず、変更内容と未検証事項を日本語で報告してください。Commit、Push、PRは作成しないでください。

### 今回の変更・保存物

- Git管理対象となる新規ファイルはこの報告書のみ。既存ソース、ビルド設定、ライセンス、著作権表示は変更していない。
- 検証用コード・修正コピー・実行ログ・依存調査台帳・生成したセーブ・バイナリは `build/native-investigation/` 内のみ。既存のignore規則を利用し、`.gitignore` 自体も変更していない。
- 生成済みWASM/dataの5ファイルは調査開始時のSHA-256と最終状態が一致した（Git管理対象の2ファイルと既存ビルド出力3ファイル）。Web/WASMの再ビルドやinstallは行わないため、Webアプリの機能回帰テストを実施したという主張はしない。
- Commit、Push、Pull Requestは作成していない。
