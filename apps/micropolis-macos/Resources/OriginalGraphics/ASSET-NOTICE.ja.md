# Micropolis Original Graphics — 出典と配布条件

このアプリはGPL公開版Micropolisの画像を使用する変更版です。Electronic Artsの製品ではありません。

Copyright (C) 1989 - 2007 Electronic Arts Inc.

設計：Will Wright。Unix移植・最適化・Tcl/Tk UI：Don Hopkins。原文の全表示は同梱のUPSTREAM-README.txtを参照してください。

## 使用素材

- 出典：https://github.com/SimHacker/micropolis
- 固定Commit：c98f6b08519887b450d9be198bfca5237aab6d0c
- 原画像：micropolis-activity/images/tiles.xpm（16×15,360画素、960個の16×16タイル）
- アプリ画像：tiles.png。原画像を無損失でRGBA PNGへ形式変換したものです。絵の追加・拡大・補間・色の変更はしていません。
- 原本、公開元README、GPL本文を同じフォルダに保持しています。URL・Git blob・SHA-256はprovenance.jsonに記録しています。
- 再生成：リポジトリのapps/micropolis-macos/script/prepare_original_graphics.py（Python標準ライブラリのみ）。

## ライセンスの根拠

公開元のUPSTREAM-README.txtの22〜92行は、images/*を含む非テキスト素材にも、Copyright (C) 1989 - 2007 Electronic Arts Inc.、GNU GPL version 3 or later、EA追加条件が適用されると明記しています。tiles.xpmは固定Commitのそのimages/内のファイルです。PNGもその派生物として同じ条件で提供します。Tauri版で使用されているという事情だけを許諾根拠にはしていません。

著作権表示・GPL本文・EA追加条件を伴って再配布し、改変版であることを明示してください。SimCity等のEA商標の利用権やEAとの関係を主張する権利は与えられていません。無保証です。契約上の責任を引き受けて配布する場合のEAに対する条件を含め、UPSTREAM-README.txtとルートのMicropolisGPLLicenseNotice.mdの原文を維持してください。

バイナリを配布する際はGPL第6条に適合する方法で、当該バイナリに対応するアプリ・エンジンのソース、原画像、変換・ビルドスクリプト、必要なライセンス文書へのアクセスを提供してください。原画像だけの同梱では、アプリ全体の対応ソース提供を満たしません。ネット配布では同じ配布場所から無償で対応ソースを取得できる構成にし、最終Commit／ソースアーカイブとバイナリを対応づけてください。今回、バイナリの公開・配布用署名・公証・ソースアーカイブ作成は行っていません。

ルートのGPL本文・MicropolisGPLLicenseNotice.md・MicropolisPublicNameLicense.mdも従来どおりアプリに同梱します。名称ライセンスの表示を削除しないでください。

Micropolis is a registered trademark of Micropolis Corporation (Micropolis GmbH) and is licensed here as a courtesy of the owner under the Micropolis Public Name License. https://www.micropolis.com
