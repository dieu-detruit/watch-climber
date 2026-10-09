# Watch Climber

Apple WatchアプリのWebモックです。ページにはWatch画面と検証用の操作だけを置いています。
対象機種はApple Watch SE 3（GPS）、watchOS 26.5。今はブラウザ上の模擬データで操作を確認する段階です。

## 起動

Node.js 22.12以降（推奨24 LTS）、npmを使用します。

```sh
npm ci
npm run dev -- --host 0.0.0.0
```

ターミナルに表示されたURLを開いてください。通常は http://localhost:5173 ですが、使用中なら次のポートになります。

## 試せること

- Watchの40mm／44mm相当の表示、スワイプ・タブ・矢印キーによる画面切り替え
- 表示倍率100〜250%（ケースサイズとは別）。表示領域を超える場合はモック部分を横スクロール
- Digital CrownのWeb操作：時計上のホイール、右側ダイアルの上下ドラッグ、フォーカスして↑↓、補助の＋／−ボタン
- ダイアル押下または回転／拡大縮小ボタンで地形の操作対象を切り替え
- 標高グラフ、累積上昇、平均の登るペース、心拍
- 国土地理院の実際の標高データによる五竜岳周辺の立体地形、回転・拡大
- 開始・一時停止・再開・終了確認・ブラウザ保存
- 歩行／休憩／GPS不良／心拍なしのシナリオ切り替え
- 15倍速のデモと「15分進める」

初期表示はサンプルです。「登山をはじめる」で0から記録します。時間は実時間1秒につき模擬時間15秒進みます。ページを非表示にすると一時停止し、再読込時も一時停止状態で復元します。心拍未取得は「—」、GPS不良は最終取得値を表示します。

「登るペース」は一時停止を除いた記録時間あたりの累積上昇です。「ひと休み」シナリオは記録を継続するので平均ペースが下がります。

記録はこのブラウザのlocalStorageに1件保存します。終了後の「新しい記録」は前のデモ記録を置き換えます。保存失敗時は通知します。位置・軌跡はWebモック用の架空の座標です。Watchネイティブ版では実際のGPS位置を使い、「模擬位置」とは表示しません。ブラウザGPSの追加はユーザーの訂正により対象外です。地形タブは実データを表示しますが、登山道や道案内はありません。GPS・心拍などの実測、通信なしでのページ起動、バックグラウンド記録はまだ行いません。

## 地形データ

`public/terrain/`に国土地理院のDEM10B PNG標高タイル35枚と、モック用に抽出した標高グリッドを保存しています。

- 範囲：約14km × 10km（北緯36.6160〜36.7036、東経137.7027〜137.8558）
- 元データ：z14、X=14459〜14465、Y=6394〜6398
- グリッド：896 × 640、2画素間隔（約15m）、欠損0
- 描画：2グリッド間隔（約122m）で三角形を描画。表示上の高さは投影処理で強調
- `goryu.json`：標高・範囲・取得日時
- `sources.json`：元URLと各PNGのSHA-256
- `tiles/`：取得したPNGをそのまま保存

[出典：国土地理院（加工）](https://maps.gsi.go.jp/development/ichiran.html)・[標高タイルの仕様](https://maps.gsi.go.jp/development/demtile.html)

再取得・変換（Python 3 + Pillow。既存PNGはキャッシュとして使用）：

```sh
python3 scripts/fetch-terrain.py
```

## 検証

```sh
npm test
npm run build
```

ブラウザでの操作チェック（Google Chromeを利用）：

```sh
PREVIEW_URL=http://127.0.0.1:5173 node scripts/check-browser.mjs
```

`CHROME_PATH`でChromeのパスを変更できます。スクリーンショットは`/tmp/watch-climber-*.png`に出力します。

## 現在のデモの小さな制約

- 開始前は固定サンプルのため、シーンの選択は「登山をはじめる」の後に反映されます。
- 再開直後、最初のサンプルを受け取る前に「15分進める」を押すと、時間の基準を取り直す1サンプル分を除いた14分45秒が加算されます。

## Apple / Codemagic の準備

brain-dumpの構成を参考に、実際に利用するApple Developerチーム・Codemagic連携に合わせて設定します。

ユーザーから受領した登録情報：

- App Store Connect / 配布コンテナ：`dev.takafumi.watchclimber`（ユーザー確認済み）
- Watchターゲット：`dev.takafumi.watchclimber.watchkit`
- App Store ConnectアプリID：`6820979760`
- [App Store Connectのアプリ情報](https://appstoreconnect.apple.com/apps/6820979760/distribution/info)
- 所有者の名前・Bundle ID接頭辞を開発環境のユーザー名から推測しない。

配布は前回のbrain-dumpと同じGitHub Actions経路を使用します。CodemagicのWebサービスへの登録・操作は不要です。署名用の `codemagic-cli-tools` だけをGitHubのMac runner内で使用します。

既存のApple APIキーと証明書用秘密鍵はbrain-dumpのGitHub Secretsにあります。再入力・別リポジトリへのコピーを避けるため、brain-dumpの専用ブランチ `ci/watch-climber-testflight` に配布ワークフローを置き、この公開リポジトリの確認済みコミットSHAを指定してビルドします。brain-dumpのmainや既存アプリの配布設定は変更しません。

- [配布ワークフロー](https://github.com/dieu-detruit/brain-dump/blob/ci/watch-climber-testflight/.github/workflows/watch-climber-testflight.yml)
- タグ `watch-climber-testflight-*` で起動。更新時はワークフロー内のcheckout SHAを確認済みコミットへ変更して新しいタグを作ります。
- 配布対象はApp Store Connectの `6820979760` と一致することをAPIで確認します。
- Watch側のHealthKit capability・両IDのプロファイル取得・署名・アップロードを自動実行します。
- 秘密鍵や署名ファイルをartifactには保存しません。公開App Storeへの申請や外部ベータ審査は行いません。

公開リポジトリの標準GitHub-hosted runnerは無料で利用できます。[GitHubの料金説明](https://docs.github.com/en/actions/concepts/billing-and-usage)

## 次の段階

`watch-climber-watch/` にSwiftUI / Core Location / HealthKitのWatch-onlyアプリを実装しました。実GPSの座標・標高・精度、Crownで操作するオフライン3D地形、軌跡、心拍、開始・一時停止・再開・終了、端末内の記録保存に対応します。ネイティブには模擬位置を供給しません。地形の範囲外では現在地の座標を表示し、地形上に偽の現在位置を描きません。

地形はWebと同じ `public/terrain/goryu.json` をバンドルします。緯度をMercator座標、経度を横座標に変換し、元タイルの画素中心に合わせています。格子は約15m間隔です。描画はズームに応じて約244m→122m→61m→30m→15mへ自動で細かくなり、最大12倍まで拡大できます。地表標高はDEM、GPS標高はCore Locationの計測値で、別々に表示します。画面を消した際のGPS・心拍・電池消費は実機確認が必要です。

記録時間はGPS更新とは独立して加算します。GPS精度が50mを超える点は軌跡・集計に使わず、30秒以上の位置更新の空白、一時停止、再起動をまたいだ線を結びません。記録を約10秒ごとにDocumentsへatomic保存し、復元した記録は一時停止します。終了済みの記録はUUID別JSONでも保存します。初版には保存履歴の一覧やエクスポートUIはありません。再起動で途切れたHealthKitワークアウトを復元せず、再開時に新しいワークアウトを作ります。

`codemagic.yaml` は任意の代替経路として残していますが、現在の配布には使用しません。GitHubの署名ワークフローが成功し、Appleの処理が完了したら、[TestFlight](https://appstoreconnect.apple.com/apps/6820979760/testflight)の内部テストからWatchへインストールします。

最初の実機確認: 位置情報を許可→座標・精度が実際に更新される→記録画面で開始してヘルスケアを許可→数分歩いて消灯中も時間・軌跡が続く→一時停止・再開→終了。五竜以外では3D画面の「収録範囲外」が正常です。

現在の検証状況: Webの30テストと本番ビルドは成功。GitHub ActionsのXcode 26.3でWatchアプリのコンパイル、7件のシミュレータテスト、実機向け署名なしアーカイブと地形同梱検査が成功しました（[実行結果](https://github.com/dieu-detruit/watch-climber/actions/runs/37948144194)）。署名付きIPAの作成とTestFlightへのアップロードも成功しました（[配布実行](https://github.com/dieu-detruit/brain-dump/actions/runs/37948777750)）。`0.1 / build 2.1` はApple側でVALID・READY_FOR_BETA_TESTING、暗号化申告受理済みです。内部テストグループ `Internal` の自動配信が有効であることを確認済みです。iPhoneのTestFlightから更新できます。

設計と実装計画は`docs/superpowers/`にあります。

GitHub: https://github.com/dieu-detruit/watch-climber （public）。ビルド・署名・TestFlight配布はGitHub Actionsを使用します。

位置情報は「使用中のみ」で、記録開始後のHKWorkoutSessionとバックグラウンド位置更新により文字盤・別アプリ表示中も計測する構成です。記録開始前・一時停止・終了・強制終了は継続記録の対象外です。実機での消灯中の軌跡と電池消費は引き続き確認が必要です。
