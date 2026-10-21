# Micropolis Native macOS — GPL公開版グラフィック統合

2026-10-21。クリーンなmainとorigin/mainの一致を確認し、fetch後の`013bf4a43addc32a3b8fc98bcf518fc9458ab040`から`feature/original-graphics`を作成。実装段階ではCommit・Push・PR・Mergeを行わず、2026-10-22のユーザー実機確認後にForkのmainへ反映する最終確認に進んだ。

## 採用した原画像と根拠

公開元は[SimHacker/micropolisの固定Commit](https://github.com/SimHacker/micropolis/tree/c98f6b08519887b450d9be198bfca5237aab6d0c/micropolis-activity)。Tauri版の`distribution/0.1.0/LICENSE-RESOLUTION.ja.md`、`asset-provenance.json`、`script/prepare_gpl_assets.py`を読んだ上で、その判断だけに依存せず、公開元から原本3ファイルを独立に取得した。取得したSHA-256とGit blobはTauri版記録とも一致した。Tauri版のファイルは変更していない。

| 使用ファイル | 公開元／派生元 | 著作権・ライセンス・判断 |
|---|---|---|
| `tiles.xpm` | `micropolis-activity/images/tiles.xpm` | Copyright (C) 1989–2007 Electronic Arts Inc.。GPL-3.0-or-later＋EA追加条件。採用 |
| `tiles.png` | 上記XPMを無損失RGBA PNGへ変換 | 同じ著作権・条件。原本の全画素と照合して採用 |
| `UPSTREAM-README.txt` | `micropolis-activity/README`の原文 | 22〜92行で画像等へのGPL／EA追加条件の適用を明記。全文保持・同梱 |
| `UPSTREAM-COPYING.txt` | `micropolis-activity/COPYING`の原文 | GNU GPL v3本文。全文保持・同梱 |

原画像は16×15,360画素、16×16タイル960個の縦ストリップである。XPM内に個別の著作権ヘッダーはないため、公開元READMEによる`images/*`への明示的な適用と、固定Commit内のパスを根拠とした。Will Wrightの設計、Don HopkinsのUnix移植等の表示もREADME原文に保持する。

原本・派生PNG・文書は`apps/micropolis-macos/Resources/OriginalGraphics/`に格納。`provenance.json`は各URL・固定Commit・Git blob・SHA-256・RGBA画素SHA-256を記録する。`prepare_original_graphics.py --check`で改変・変換の一致を検証できる。Python標準ライブラリだけを使用し、元の16ビット色が8ビット値の繰り返しであることも検証して正確に変換する。画像の追加・補間・色変更はない。

## 調査したが採用しない素材

| 既存ファイル／グループ | 出典確認の範囲と除外理由 | SwiftUI版 |
|---|---|---|
| `content/micropolis/images/tiles.png`（256×960） | MicropolisCore由来の現リポジトリ画像。今回採用した固定CommitのXPMと同一の原本・派生関係を独立確認していない | 非同梱 |
| `content/micropolis/images/tiles_pixels.png`（16×60） | 同上。縮小画像を原画の許諾根拠にはしない | 非同梱 |
| `content/micropolis/images/tiles/micropolis_tile_*.png`等（同フォルダPNG計1,033枚） | 分割・拡張画像群。個々の由来・著作権・追加画像の許諾を今回確定できていない | 全非同梱 |
| `content/micropolis/images/tiles_micropolis.swf`、OpenLaszlo側同名SWF | 既存の派生表示素材。今回原画としての出典・個別条件を確定していない。Flashも使用しない | 非同梱 |
| `content/micropolis/tilesets/classic/tiles.bmp` | Tauri版ではBMP由来PNGを配布から除外。classicという名前や既存利用だけでは許諾を推測しない | 非同梱 |
| `content/micropolis/tilesets/classic95/tiles.bmp` | 同上。個別の権利根拠未確認 | 非同梱 |
| `content/micropolis/tilesets/ancientasia/tiles.bmp` | 追加パック。個別著作権・再配布許諾未確認 | 非同梱 |
| `content/micropolis/tilesets/medievaltimes/tiles.bmp` | 同上 | 非同梱 |
| `content/micropolis/tilesets/futureeurope/tiles.bmp` | 同上 | 非同梱 |
| `content/micropolis/tilesets/futureusa/tiles.bmp` | 同上 | 非同梱 |
| `content/micropolis/tilesets/mooncolony/tiles.bmp` | 同上 | 非同梱 |
| `content/micropolis/tilesets/wildwest/tiles.bmp` | 同上 | 非同梱 |
| Tauri版`apps/desktop/assets/gpl/tiles.png`、obj1〜obj7スプライトPNG | 原XPMからの変換方式と記録のみ参照。生成PNGはコピーせず、タイルは今回独立変換。移動スプライトは対象外 | 非同梱 |

未採用素材の著作権者やライセンスを推測して記載しない。既存ファイルは削除・編集しない。新しいアプリのリソース参照は採用したOriginalGraphicsフォルダのみであり、Webのcontentフォルダ全体をコピーしない。

## タイル対応

エンジンの`micropolis.h`の`Tiles`、`MapTileBitmasks`、`animate.cpp`を根拠にした。`mp_copy_map`の並びは`y*120+x`、各値はUInt16。`raw & 0x03ff`だけを画像番号とし、残りの区域・アニメーション・導電性・通電等のフラグを画像索引に混ぜない。

| ID | 内容 |
|---|---|
| 0 | 空き地 |
| 2〜20 | 水・水路・水辺の接続形状 |
| 21〜43 | 森林・樹木・公園の形状 |
| 44〜63 | 瓦礫・洪水・放射能・火災等 |
| 64〜207 | 道路・橋・道路と送電線の交差・交通量／アニメーション段階 |
| 208〜223 | 送電線・鉄道と送電線の交差 |
| 224〜239 | 鉄道・道路と鉄道の交差等 |
| 240〜404 | 住宅地区・住宅の発展／地価段階 |
| 405〜413、414〜422 | 病院・元の教会 |
| 423〜611 | 商業地区・発展／地価段階 |
| 612〜692 | 工業地区・発展段階 |
| 693〜708、709〜744 | 港・空港 |
| 745〜760、761〜769、770〜778 | 石炭発電所・消防署・警察署 |
| 779〜810、811〜826 | スタジアム・原子力発電所 |
| 827〜955 | 停電表示、開閉橋、レーダー、噴水、煙、爆発、試合、原子力アニメーション等 |
| 956〜959 | 原画像では未使用。現エンジンでは拡張教会の先頭にも使用するため原画像を適用しない |
| 960〜1023 | 原画像に存在しない拡張・未使用ID |

0〜955は画像番号と原本のタイル順を直接対応させる。956〜1023は透明セルを通じて従来の簡易色表示を出す。欠落セルを別の追加パック画像で埋めたり、保存IDを書き換えたりしない。地区・公共施設はエンジンが配置する複数タイルの組合せをそのまま描く。発展段階をSwiftで推測しない。

## 描画・キャッシュ・アニメーション

`TileAtlas`はImageIOでPNGを一度読み、RGBA画素を保持する。`TileImageRenderer` actorは可視範囲に交わる16×16タイル区画だけを画像化する。画像番号列が変わった区画だけを再生成し、状態フラグだけの変更では画像を再生成しない。キャッシュは8列×7行の最大56画像、RGBA合計12,288,000バイト。原画約983KB、キャッシュ管理情報、一時出力のメモリーは別途必要である。

SwiftUIのCanvasは区画画像を地図座標から画面座標へ変換し、補間なしで描く。Retina倍率はSwiftUIに任せ、原画16ピクセルと画面のポイントを混同しない。プレビュー・電力・未通電表示は別レイヤーを維持する。画像が欠落・破損・想定外サイズなら簡易描画で継続する。可視範囲変更・都市の置換・保存都市の読込でも同じ画像キャッシュを安全に更新する。

最小限の追加C API `mp_animate_tiles`で既存`animateTiles()`を呼ぶ。Swiftの更新ループの非空tickバッチ後に1回（通常100ms）だけ実行する。既存`mp_step`の動作は変更しない。火災・交通・レーダー・噴水・工場／石炭の煙・試合・原子力等は元のアニメーションテーブルに従う。状態フラグを保持し、資金・都市時刻を進めない。停止・一時停止・速度0では静止する。元のテーブルで静止している水面は静止のまま。移動する列車・船・航空機・怪獣等のスプライトは今回表示しない。

## 配布条件と同梱

`OriginalGraphics/ASSET-NOTICE.ja.md`に出典、改変内容、GPL／EA追加条件、対応ソースの提供条件を記載した。Xcodeは同フォルダをそのままアプリに同梱し、ライセンス画面から追加文書を読める。ルートのGPL本文・EA追加条件・名称ライセンスは改変せず、従来どおり同梱する。

バイナリ配布時には、当該版のアプリ・エンジン・原画像・変換／ビルドスクリプト等を含む対応ソースをGPL第6条に適合する方法で提供する必要がある。ネット配布なら同じ配布場所から無償で取得できる構成とし、ソースとバイナリの版を対応させる。画像原本だけの同梱をアプリ全体の対応ソース提供として扱わない。EA商標権・関連性を主張せず、改変版と無保証を表示し、契約責任を引き受ける場合のEA追加条件も保持する。今回、配布用署名・公証・Release・ソースアーカイブの作成は行わない。採用した原画について重大な未解決の権利問題は見つかっていないが、将来のバイナリ配布時にはこれらの提供作業が残る。

## 検証結果

Apple M1、macOS 27.0.1、Xcode 27.1、Swift 6.4、arm64 Debug。

- Xcodeビルド・MicropolisNativeリンク成功。署名済み実アプリで使い捨て保存都市の道路・送電線・RCI・発電所を表示し、スクリーンショットで確認した。
- 原本3ファイルのハッシュ、再生成PNG、RGBA画素を一致確認。全65,536通りのUInt16値でフラグと画像番号の分離を検証。
- 各描画区画の全タイル・全行を原画画素と照合。956〜1023の透明フォールバック、欠落・破損PNG、キャッシュ再利用と1セル変更時の1区画更新、可視区画選別に成功。
- 実際のCanvasを1倍とRetina2倍で画像化し、0〜955全IDの複数画素を比較。上下方向と色の対応、2×2画素ブロックの非補間を確認。パン・ズーム・リサイズ後も、可視タイルの画素が同じ地図座標の原画像と対応することを比較した。簡易Canvasも描画成功。
- 建設・成長した保存都市とhaight.ctyを原画像で描画。200回のシミュレーション／描画更新と都市置換後もキャッシュ上限を維持。
- C++／C API・Swiftモデル回帰成功。全15ツール、保存・再生成・復元・継続、失敗I/O保護、ドラッグ費用、座標変換、電力・人口、haight、328,000 tick等の既存検証を維持。
- アニメーション追加試験：全1,024 ID、32フレームを既存コアの遷移と比較し、全フラグ・停止・速度0・資金／時刻不変を検証。
- ASan／UBSanで4つのnativeテスト成功。既存Web/WASM回帰は13ファイル80テスト成功。Emscriptenでの再ビルドは今回未実施。
- `git diff --check`成功。共有C++ src、Web版、都市・既存画像・音声、ライセンス原本、依存manifest／lockfileは変更していない。

主コマンド：`bash apps/micropolis-macos/script/verify_graphics.sh`。原画再生成は`python3 apps/micropolis-macos/script/prepare_original_graphics.py`、検証だけなら`--check`を付ける。ログと描画画像はGit管理対象外の`build/original-graphics/`に置く。

## 性能と実機での残確認

Debugの単回測定で、全都市の区画初回生成は約48ms（actor上）、変更なしの100回処理は約182ms（1回約1.82ms）。Canvasオフスクリーン出力は初回1倍約40ms、後続2倍約8ms。後者は初期化・キャッシュ条件が異なるため倍率間の比較や実画面FPSを意味しない。10Hzの更新ループを維持し、画面上の長時間FPS・GPU負荷は未計測。

2026-10-22、原画像版で建設・接続、パン・ピンチ操作、建設プレビュー、電力表示、アニメーションと停止・再開、保存後の継続、ライセンス画面がすべて正常とのユーザー実機確認を受けた。以前の色分け版の結果を流用したものではなく、今回の原画像版に対する操作結果である。Codexの自動試験とは区別する。全施設・全ズーム倍率等の網羅的なGUI試験、数時間のGUI連続稼働・FPS計測は未実施。

## 変更ファイル

- 追加：`apps/micropolis-macos/.gitattributes`。出典ハッシュを持つ原本3ファイルの改行変換を禁止し、上流READMEに元からある末尾空白・末尾空行だけを空白検査の対象外とする。実装コード・テストの空白検査は維持する。
- 変更：`apps/micropolis-macos/MicropolisMac.xcodeproj/project.pbxproj`、`README.ja.md`、`Services/EngineSession.swift`、`Views/CityMapView.swift`、`Views/LicenseView.swift`
- 追加：`apps/micropolis-macos/Rendering/TileAtlas.swift`、`Rendering/TerrainCanvas.swift`、`Tests/GraphicsIntegration.swift`、`script/prepare_original_graphics.py`、`script/verify_graphics.sh`
- 追加素材・資料：`apps/micropolis-macos/Resources/OriginalGraphics/{tiles.xpm,tiles.png,UPSTREAM-README.txt,UPSTREAM-COPYING.txt,ASSET-NOTICE.ja.md,provenance.json}`
- 変更：`packages/micropolis-engine/{README.native.md,native.mk,native/api.cpp,native/include/micropolis_native.h}`
- 追加：`packages/micropolis-engine/tests/native/animation_test.cpp`、本書

公開対象は変更9・追加14の計23ファイル。原画像描画・最小限のnative API・テスト・資料・原本保持用Git属性のみを含み、成果物・ログ・ユーザー設定・認証情報を含めない。既存の実行中ゲームを強制終了せず、試験用アプリは別プロセスで起動した。

## GitHub反映前の最終確認（2026-10-22）

ユーザー実機確認後にarm64 Debugビルド、C++／C API・Swift・画像統合回帰、ASan／UBSanの4つのnativeテスト、既存Webの13ファイル80テストを再実行してすべて成功した。署名検証と、アプリ同梱の原画像・出典記録・ライセンス全文のバイト一致も確認した。画像の出典と権利条件は前記の固定原本のまま維持し、追加パックは同梱していない。確認ログはGit管理対象外の`build/original-graphics/final/`に置く。

公開先は自分のFork `Toshiyuki-Kanai/micropolis-native-macos`のmain。通常のMerge commitを用い、元のSimHackerへの書き込み、mainへの直接Push、force pushは行わない。作業ブランチを保持する。既知の制限（拡張IDの簡易描画、静止水面、移動スプライト非対応、長時間GUI計測・配布用署名／公証／対応ソースアーカイブの未実施）は継続する。
