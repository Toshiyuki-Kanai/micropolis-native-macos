# MicropolisJ準拠開発 — 基準ソースの確認

2026-10-22。機能実装前のソース同定記録。ユーザーの承認によりdheid/micropolisの正式v2.0.0を機能仕様の基準に確定した。機能準拠の完成報告ではない。

## 指定にある収録先

- リポジトリ：`https://github.com/SimHacker/micropolis`
- 調査したmasterの固定Commit：`c98f6b08519887b450d9be198bfca5237aab6d0c`
- Java版の場所：`micropolis-java/`
- `micropolis-java/build.xml`の`package-version`は`1.7`。この版をv2.0.0と見なすことはできない。
- GitHub Tag一覧では`micropolis-java`（`b011a4572853e0d13c41a2e6048ffbfc457e72d1`）を確認した。v2.0.0 Tag／Releaseはこのリポジトリには確認できなかった。

根拠：[固定Commitのbuild.xml](https://github.com/SimHacker/micropolis/blob/c98f6b08519887b450d9be198bfca5237aab6d0c/micropolis-java/build.xml)、[Tag一覧](https://github.com/SimHacker/micropolis/tags)。

## 採用する正式v2.0.0

- リポジトリ：`https://github.com/dheid/micropolis`
- Release：`v2.0.0`、2020-03-05公開、draft=false、prerelease=false
- Tag：`v2.0.0`
- Tagが直接指すCommit：`4cbac80d8d0052cbc9f4e71130dad212dbe2b492`
- 同Commitの`gradle.properties`：`version=2.0.0`
- 同CommitのREADMEは、SimHacker/micropolisに収録されたJason LongのMicropolisJに基づくJava rewrite forkと明記している。
- リリースには配布用tar／zipがある。調査では固定Commitのソースアーカイブだけを取得し、コードは実行していない。
- 取得したソースtar.gzのSHA-256：`168e7a9e64767980fcbea7e645b984a7c3189e426a76db6f59134451ade367e4`

根拠：[正式Release](https://github.com/dheid/micropolis/releases/tag/v2.0.0)、[固定ソース](https://github.com/dheid/micropolis/tree/4cbac80d8d0052cbc9f4e71130dad212dbe2b492)、[README](https://github.com/dheid/micropolis/blob/4cbac80d8d0052cbc9f4e71130dad212dbe2b492/README.md)、[版番号](https://github.com/dheid/micropolis/blob/4cbac80d8d0052cbc9f4e71130dad212dbe2b492/gradle.properties)。

## 基準確定

2026-10-22、ユーザーが「dheid/micropolisの正式v2.0.0を基準にする」を選択した。以後は上記Tag/Commitの公開UIと実行経路を基準にする。SimHacker収録1.7およびdheidの開発ブランチは仕様として混在させない。

[機能比較・差異・実装計画・検証記録](native-macos-micropolisj-parity.ja.md)へ続く。JavaのコードをSwiftへ移植せず、公開機能の確認と相互読み込み検証に用いる。

## Git

開始時mainはクリーンでorigin/mainと一致。fetch後の`9f3d22eea42e66c731e3f2bc768fbf102675ef01`から`feature/micropolisj-parity`を作成。調査用ダウンロード・Javaコンパイル・ビルド出力はGit管理対象外の`build/`のみ。Commit・Push・PR・Mergeは行わない。
