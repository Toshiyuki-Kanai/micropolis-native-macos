# 移動スプライトと効果音の出典

2026-10-22追加の変更版。Electronic Artsの製品ではありません。
Copyright (C) 1989–2007 Electronic Arts Inc.
GPL version 3 or laterとElectronic Arts追加条件。

出典はSimHacker/micropolisの固定Commit c98f6b08519887b450d9be198bfca5237aab6d0c。
micropolis-activity/images/obj1-*.xpm〜obj7-*.xpmの57フレームと、micropolis-activity/res/sounds/の11 WAVを採用。
各原本のパス・URL・Git blob・SHA-256はprovenance.jsonに記録した。
Tauri版に保管されていたXPMも、上流の固定Gitツリーのblobと照合してから採用した。

根拠は親フォルダーのUPSTREAM-README.txt。images/*とres/sounds/*をGPL/EA条件の対象として明記。
UPSTREAM-COPYING.txt、ルートのGPL・EA追加条件・名称ライセンスをアプリに同梱し、既存文書を改変しない。
名称・非EA製品表示・無保証・著作権・変更版の識別・対応ソース提供等の条件を引き続き適用する。
バイナリ配布時は、元素材、変換器、ネイティブ実装を含む対応ソースとビルド手順もGPLの条件に従って提供する。

PNGはscript/prepare_gameplay_assets.pyでXPMの16-bit反復RGBを8-bitへ正確に変換し、Noneを透明にしたもの。
拡縮・描き直し・追加画像の合成は行わない。generated.jsonにPNGのハッシュと原本を記録。
列車・ヘリ・飛行機・船・怪獣・竜巻・爆発をエンジンのframe-1で選ぶ。
Javaの追加音源zombie-roar-5やlayzoneは取り込まず、GPL原版monster/buildを使う。
権利不明素材、新規のBGM、バス画像obj8は含めない。
