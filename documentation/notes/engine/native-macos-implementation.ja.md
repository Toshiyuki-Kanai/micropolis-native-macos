# Micropolis Native：エンジン安定化・最小C API 実装報告

2026-10-16（日本時間）。基準コミット：`9d5b400b2d3beaf81e4103056f6c7f503dfde6e1`。
前回の `native-macos-investigation.ja.md` を根拠に実装した。

## 1. 実装した内容

共有C++エンジンを局所修正し、独立したネイティブ静的ライブラリー、公開C API、純粋C/C++の回帰テスト、Swift Package、画面を持たないSwift呼び出し例を追加した。SwiftUIは未実装。

ネイティブビルドは既存のMakeとC/C++コンパイラーで完結するため、CMake等の新規依存を追加せず、別の `native.mk` を採用した。既存WASM makefile、package.json、生成物の配置規則は変更していない。

## 2. 修正した不具合

| 根本原因 | 修正 |
|---|---|
| `mapBase` / `mopBase` / callback / 履歴・スプライト等のポインターが未初期化 | メンバー初期値を設定。既定callbackを構築してから利用。初期化前の破棄と再初期化も検証 |
| `historyInitialized` 等の未初期化状態 | ASan/UBSanのdirty-storage試験で発見したフラグなどを初期化 |
| `voteProblems` が添字 `PROBNUM` を許す | 折り返し条件を `>= PROBNUM` に修正 |
| `malloc` 相当で確保した `SimSprite` の未構築 `std::string` に代入 | `new SimSprite{}` で構築。稼働中・プール両リストを `delete` で解放し、再初期化・破棄時にも後始末 |
| `short*` を `Quad*` にキャストし、LP64で8バイト読み書き | 16ビットワードと符号付き32ビットフィールドを明示的に組み立てる。幅・アラインメント・ホストのバイト順への依存を除去 |
| 予算率の変換値を生キャストで再上書きし、その後1.0へ初期化 | 一時状態を先に初期化し、保存されていた16.16固定小数点の率を復元 |
| 書き込み失敗時にライブ配列のバイト順が戻らない | ライブ配列を変更せずbig-endianバイトを書き、fcloseの失敗も返す |
| 未設定の履歴・補助データに確保時のゴミが残る | `newPtr` をゼロ初期化と失敗時の例外に変更。構築失敗時の確保済み配列も解放 |

所有するC++エンジンを誤ってコピーし二重解放しないよう、コピー構築・代入を禁止した。既存著作権・ライセンス本文は維持し、変更箇所に変更日等を記した。

## 3. C APIの仕様

公開ヘッダー：`packages/micropolis-engine/native/include/micropolis_native.h`。

| API | 内容 |
|---|---|
| `mp_create` / `mp_destroy` | opaque handleの生成・破棄。生成時に空都市を初期化 |
| `mp_generate` | 指定seedで新都市を生成し、実行状態を既定値へ戻す |
| `mp_step` | 指定回数更新。1回につき最大1,000,000 tick |
| `mp_set_paused` / `mp_set_speed` | 一時停止・再開、速度0〜3。停止中の速度変更は再開後に反映 |
| `mp_get_snapshot` | 資金、人口、時刻、年月、速度、停止状態、資金配分、revisionのコピー |
| `mp_set_funding` | 警察・消防・道路の資金配分率0〜1を設定 |
| `mp_copy_map` | main/mapまたはmopをコピー。12,000要素のUInt16、`y*120+x` のrow-major |
| `mp_build` | 道路・住宅・商業・工業・撤去・送電線・鉄道・公園・石炭発電所 |
| `mp_load_city` / `mp_save_city` | 既存形式の読込／map+mop形式の保存 |
| `mp_result_string` | エラーコードの静的文字列 |

C11互換、固定幅の値と呼び出し側所有バッファのみを使用し、C++型・JS値・内部マップポインターを公開しない。マップの上位フラグを保持し、タイルIDには `& 0x03ff` を使用する。

生成で所有権を受け取り、最後に一度だけ破棄する。NULL破棄は可能だが、破棄済みハンドルの利用や二重破棄は禁止。C++例外はC境界で捕捉し、引数不正、バッファ不足、メモリー不足、I/O、資金不足、撤去必要、建設不可、内部エラーを区別する。

同一ハンドルの操作はmutexで直列化する。破棄と他の呼び出しの同時実行は利用側で禁止する。生成・ロードは新しいエンジンを準備してから交換するため、失敗時に現在の都市を保持する。他の変更操作でメモリー不足／内部エラーが起きた場合は部分変更の可能性があるため、ハンドルを再生成する。

保存は同じディレクトリーの一時ファイルへ書いてからrenameする。失敗時は既存の保存先を保持する。これは原子的な置換であり、停電時の永続性を保証するfsync処理ではない。

今回は状態をポーリングする最小フロントエンド。音、通知、手動予算ダイアログ、robots等のスクリプト拡張を公開するイベントAPIは含めない。これらは今後のUI統合時に追加する。都市生成の既定は自動予算である。

## 4. Linuxビルド結果

Linux x86_64、GCC/G++ 14.2.0、C++17。次のコマンドで成功：

```sh
make -f packages/micropolis-engine/native.mk -j4 test
```

本体25翻訳単位とネイティブ用callback／C APIを共通ソースとして使用し、`build/native/libmicropolis_native.a` を生成した。純粋CのテストはCコンパイラーでコンパイル後、C++リンカーで静的ライブラリーへ接続している。

- 都市生成、道路・R/C/I建設、道路の資金20,000→19,990を確認。
- 新都市で2,000 tick、一時停止・速度変更・再開を確認。
- `haight.cty` のロード後2,000 tick：`cityTime 4839 → 4964`。
- 8つの同梱シナリオファイルをそれぞれロードし、各1,100 tick実行。
- C APIでも都市生成・建設・資金・2,000 tick・停止再開・haightの実行・保存読込を確認。
- C APIの不正引数、容量不足、資金不足、建設拒否、失敗ロード、失敗保存、異なる都市の分離、同一ハンドルの並行読取、繰り返し生成破棄を確認。

native.mkはWASM用の `make install` を呼ばず、ソースディレクトリーへオブジェクトを書かない。

## 5. サニタイザー検証結果

```sh
ASAN_OPTIONS=detect_leaks=0 UBSAN_OPTIONS=halt_on_error=1 \
  make -f packages/micropolis-engine/native.mk SANITIZE=1 -j4 test
```

C++と純粋Cの両テストが **ASan/UBSanの診断なしで成功**。通常版とは別の `build/native-sanitized/` を自動選択する。型幅・アラインメント、配列境界、dirty-storageでの構築、長い文字列を持つスプライトの再利用、都市実行等を通した。

LeakSanitizerも別途有効化して実行したが、このCloud環境ではptrace制約によるfatal errorになった。リーク検査成功とは扱っていない。ASan/UBSanの検査自体は無効にしていない。Macまたは制約のないLinuxで、ツールチェーンが対応するリーク検査を追加実行する。

## 6. 保存互換性の検証結果

**検証対象の互換性テストは成功。**

- 27,120バイトのclassic形式と51,120バイトのmap+mop形式を読み込み可能。
- 保存形式は既存の51,120バイト形式を維持。
- 独立して組み立てたbig-endianの既知バイト列で、資金123,456,789、時刻54,321、資金配分0.25／0.5／0.75を検証。
- 負の資金-12,345、資金配分0と1、隣接する履歴値の保持を確認。
- 非対称座標 `(3,7)` のmap/mopを使い、column-majorファイル順とC APIのrow-major出力を区別して検証。
- C API保存のmap/mop全要素を、独立したCのバイト読み取りと照合。
- `/dev/full`（Linux）等の失敗保存でもライブマップのバイト順を変えないことを確認。
- ロード失敗時にはC APIの都市・資金・revisionを維持する。
- 同じ既知バイト列テストをwasm32でも実行し、32ビット環境とLP64の両方を確認。

既存ローダーは時計で乱数を再seedし、ロード時に道路の交通表示・区域などを走査する。そのため実行中都市のロード前後マップはビット単位で同一とは限らず、乱数列の継続も保存形式に含まれない。この既存動作は変更していない。保存バイト列の正確性、rawデコード、静的マップでのC/C++ APIの完全一致、実都市の実行を別々のテストで検証した。

## 7. Web/WASM回帰テスト結果

既存生成物を使ったWeb/CLIテスト：**13ファイル・80テスト成功**。
修正ソースを再ビルドした隔離WASMを使った同じテスト：**13ファイル・80テスト成功**。
さらに共有C++回帰テストをwasm32としてビルド・実行し、都市・建設・tick・スプライト・保存バイト列・資金配分・8シナリオの試験に成功した。

```sh
python3 packages/micropolis-engine/tests/native/verify_wasm.py --emxx em++
```

この検証スクリプトは `build/wasm-regression/` にのみ出力し、Webアプリのコピーへ新しい生成物を配置する。元の `make install` は実行しない。元のJS/WASM/dataはスクリプト終了時にもハッシュ一致を検証する。

CloudにはEmscriptenがなかったため、依存を調査後、DebianのEmscripten 3.1.69、LLVM/Clang 19、Binaryen 120等を `build/native-validation/toolchain/` へ展開して使用した。システムへのインストールはしていない。最初に試した公式emsdkは配布ホストの403で取得できなかった。

CLI試験のtsxはローカルIPCソケットを必要とする。通常のsandbox実行ではEPERMで2テストが失敗したため、ソケットを利用できる実行条件で全件再実行し成功した。テストは無効化していない。

開始時に保護対象とした既存JS/WASM/data/型定義の4ファイルは最終SHA-256が一致。既存の都市・素材、WASM makefile、JS公開APIは変更していない。ブラウザーの画面操作やGPU描画の実機試験は実施していない。

## 8. Apple Siliconで未検証の項目

- arm64 Apple Clang／macOS SDKでのコンパイル・リンク・実行。
- SwiftPM manifestの評価、公開CヘッダーのSwift import、Swift呼び出し例のビルド・実行。
- Xcodeのアプリターゲットへの実接続、署名、公証、App Sandboxとsecurity-scoped URL。
- SwiftUI画面、マップ描画、実機でのマウス・キーボード入力。
- 制約のない環境でのリーク検査。

`Package.swift` はmacOS 13以降、C++17の `MicropolisNative` ライブラリーと `NativeSmoke` 実行例を定義する。Swift C++ interopは不要。SwiftPMはC++ランタイムのリンクを扱う。手動リンクの場合はApple Clangで作成したarm64の静的ライブラリー、公開ヘッダーと `libc++`（`-lc++`）を使用する。Linuxで生成した `.a` はmacOSへ持ち込まない。

## 9. 次にCodex Localで実施する作業

M1 MacBook Proで、まず画面なしの統合を検証する：

```sh
xcode-select -p
xcrun swift build --package-path packages/micropolis-engine \
  --scratch-path build/swift-native --arch arm64
xcrun swift run --package-path packages/micropolis-engine \
  --scratch-path build/swift-native --arch arm64 NativeSmoke
xcrun swift run --package-path packages/micropolis-engine \
  --scratch-path build/swift-native --arch arm64 NativeSmoke \
  "$PWD/content/micropolis/cities/haight.cty"
make -f packages/micropolis-engine/native.mk CXX='xcrun clang++' CC='xcrun clang' test
```

その後XcodeアプリにこのディレクトリーをローカルSwift Packageとして追加し、SwiftのEngineSessionで所有する。都市操作を直列化し、コピーした12,000タイルとsnapshotをMainActorへ渡してSwiftUI Canvasの表示へ進む。

推奨する次の依頼文：

> M1 MacBook ProのCodex LocalでREADME.native.mdに従いarm64のMakeテスト、Swift PackageとNativeSmokeのビルド・実行を検証してください。問題があれば最小修正してください。その後、XcodeのSwiftUIアプリにローカルPackageを接続し、EngineSession経由の都市生成とCanvasによるマップ表示を実装してください。都市データとライセンスを維持し、Commit・Push・PRは作成しないでください。

## 10. 変更ファイル一覧とgit status

既存7ファイルを変更。今回の新規ファイルは11個（この報告書を含む）。これに加えて前回の調査報告書が未追跡のまま残っている。ステージング、Commit、Push、PR作成は行っていない。

| ファイル（リポジトリ相対） | 内容 |
|---|---|
| `packages/micropolis-engine/.gitignore` | SwiftPM出力を除外 |
| `packages/micropolis-engine/src/allocate.cpp` | 解放時のデバッグ出力を除去 |
| `packages/micropolis-engine/src/evaluate.cpp` | 投票配列の境界修正 |
| `packages/micropolis-engine/src/fileio.cpp` | 幅・アラインメント・バイト順・資金配分・失敗I/O修正 |
| `packages/micropolis-engine/src/micropolis.cpp` | 既定callback、構築失敗・再初期化・破棄処理、ゼロ初期化確保 |
| `packages/micropolis-engine/src/micropolis.h` | 所有ポインター・フラグ等の初期値、コピー禁止、後始末メソッド |
| `packages/micropolis-engine/src/sprite.cpp` | C++構築とリスト解放 |
| `packages/micropolis-engine/native.mk` | 独立ネイティブビルド／テスト |
| `packages/micropolis-engine/Package.swift` | ライブラリーとSwift実行例の統合準備 |
| `packages/micropolis-engine/native/include/micropolis_native.h` | 公開C APIと契約 |
| `packages/micropolis-engine/native/api.cpp` | C境界、ロック、エラー、所有権、I/O |
| `packages/micropolis-engine/native/callback.cpp` | ネイティブ用通知アダプター |
| `packages/micropolis-engine/examples/swift/main.swift` | Swift呼び出し例 |
| `packages/micropolis-engine/tests/native/core_test.cpp` | 共有C++回帰試験 |
| `packages/micropolis-engine/tests/native/api_test.c` | 純粋C API試験 |
| `packages/micropolis-engine/tests/native/verify_wasm.py` | 隔離WASM再ビルドとWeb／共有コア試験 |
| `packages/micropolis-engine/README.native.md` | API、ビルド、Xcode接続、制限の説明 |
| `documentation/notes/engine/native-macos-implementation.ja.md` | この実装・検証報告 |

検証バイナリ・セーブ・SDK・ログはGit管理対象外の `build/` に配置した。主なログは `build/native-validation/{test.log,sanitizer-test.log,web-existing.log,wasm-regression.log,leak-check.log}` と `build/wasm-regression/{web-tests.log,core-tests.log}`。

Micropolis is a registered trademark of Micropolis Corporation (Micropolis GmbH) and is licensed here as a courtesy of the owner under the Micropolis Public Name License. <https://www.micropolis.com>

最終 `git status --short --untracked-files=all`：

```text
 M packages/micropolis-engine/.gitignore
 M packages/micropolis-engine/src/allocate.cpp
 M packages/micropolis-engine/src/evaluate.cpp
 M packages/micropolis-engine/src/fileio.cpp
 M packages/micropolis-engine/src/micropolis.cpp
 M packages/micropolis-engine/src/micropolis.h
 M packages/micropolis-engine/src/sprite.cpp
?? documentation/notes/engine/native-macos-implementation.ja.md
?? documentation/notes/engine/native-macos-investigation.ja.md
?? packages/micropolis-engine/Package.swift
?? packages/micropolis-engine/README.native.md
?? packages/micropolis-engine/examples/swift/main.swift
?? packages/micropolis-engine/native.mk
?? packages/micropolis-engine/native/api.cpp
?? packages/micropolis-engine/native/callback.cpp
?? packages/micropolis-engine/native/include/micropolis_native.h
?? packages/micropolis-engine/tests/native/api_test.c
?? packages/micropolis-engine/tests/native/core_test.cpp
?? packages/micropolis-engine/tests/native/verify_wasm.py
```
