# Watch Climber Web Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking. Native execution in the current session was approved by the user.

**Goal:** ルート入力なしで操作できる日本語のWatch風Web試作を作る。

**Architecture:** 記録の状態遷移・集計をReactから独立させ、模擬センサからサンプルを渡す。画面は共通の記録状態を読み、保存境界で検証とエラー処理を行う。Web試作の完了後にフィードバックを受け、ネイティブ実装は別工程とする。

**Tech Stack:** React, TypeScript, Vite, Vitest, Testing Library。SVGで軌跡を描画し、localStorageでデモ記録を保持する。

**Spec:** `docs/superpowers/specs/2026-10-09-watch-climber-design.md`

## Global Constraints

- 対象は Apple Watch SE 3（GPS）、watchOS 26.5。
- 予定ルート・宿泊地点は未定。これらを入力せずに使えることを必須とする。
- 日本語表示、黒背景、大きな数字、押しやすい操作領域。
- 40mm / 44mm 相当の画面サイズを切り替えて確認できる。
- 全画面で「デモ」を明示する。数値や軌跡を実測・実在の登山道と誤認させない。
- 未取得の標高や心拍はゼロではなく「—」で表示する。
- ネイティブ製品コード・Codemagic設定は今回の実装対象外。

## Review Focus

- GPS不良から復帰しても空白区間を直線距離として加算しない（Task 1）。
- 一時停止から再開しても停止中の移動や時間を加算しない（Task 1）。
- 保存値の破損・形式変更時に画面をクラッシュさせない（Task 2）。
- 保存不可時に「保存済み」を表示しない（Task 2）。
- 狭い画面・タッチ操作でも終了確認を取り消せて記録が継続する（Task 3）。

---

### Task 1: 記録モデルと模擬センサ

**Files:** Create `package.json`, `tsconfig.json`, `vite.config.ts`, `index.html`, `.gitignore`, `src/session.ts`, `src/session.test.ts`, `src/demo.ts`。

**Interfaces:** `Sample = { timestamp: number; latitude: number; longitude: number; altitude: number | null; accuracy: number; heartRate: number | null }`。`Session`は状態・記録時間・距離・累積上昇・サンプル・最終取得値を持つ。`createSession(): Session`、`transition(session: Session, action: 'start' | 'pause' | 'resume' | 'finish'): Session`、`recordSample(session: Session, sample: Sample): Session`、`demoSample(index: number, scenario: 'walk' | 'rest' | 'gps-lost' | 'no-heart-rate'): Sample` を提供する。

- [x] 最小の開発設定を作り、テスト実行可能にする。
- [x] テストを書く：未開始から開始、pause中にサンプルを与えても時間・距離・上昇・軌跡不変、終了後は変更不可。`expect(pausedAfterSample).toEqual(paused)`。
- [x] 集計テストを書く：既知の2地点で距離を検証、accuracy > 50m / 非有限値 / 過去の時刻は集計対象外。欠測・pauseを挟んだ最初の点は接続せず、以後の連続した点で計測を再開する。
- [x] 高度テストを書く：100→101→100→101mは上昇0、100→104mは上昇4m。高度の基準から3m以上変化した時に基準を更新し、上昇分だけ加算する。
- [x] `npm test -- src/session.test.ts`で未実装の失敗を確認する。
- [x] モデルと再現可能な模擬サンプルを実装する。記録時間は有効な連続サンプルの時刻差を使うが、GPS品質の低下だけではタイマーを停止しない。
- [x] 同コマンドで全テストが成功することを確認する。

### Task 2: 保存・復元

**Files:** Create `src/storage.ts`, `src/storage.test.ts`。

**Interfaces:** Task 1の`Session`を使用。`saveSession(storage: Storage, session: Session): { ok: boolean; error?: string }`、`loadSession(storage: Storage): { session: Session | null; error?: string }`を提供する。保存キーは`watch-climber.demo.v1`、データにversionを持たせる。

- [x] テストを書く：保存→復元で値を保持、記録中はpauseとして復元、終了済みは終了状態を保持。破損JSON・不正な数値・未知versionは復元せずエラーを返す。
- [x] Storageが読み書き時に例外を投げるケースで、例外を外へ漏らさず`error`を返すテストを書く。
- [x] `npm test -- src/storage.test.ts`で失敗を確認する。
- [x] 保存と検証処理を実装する。復元時はサンプルの座標・時刻・数値と状態の整合性を検証する。
- [x] 同コマンドで成功を確認する。

### Task 3: Watch画面とデモ操作

**Files:** Create `src/main.tsx`, `src/App.tsx`, `src/App.test.tsx`, `src/components/WatchFrame.tsx`, `src/components/StatusView.tsx`, `src/components/TrackView.tsx`, `src/components/RecordView.tsx`, `src/styles.css`, `README.md`。

**Interfaces:** `App`がSessionと現在の画面を管理。Task 1と2の関数を呼び、表示コンポーネントに読み取り値と操作コールバックを渡す。センサ更新は1秒ごと、ページが非表示になるとpauseし、ブラウザを閉じた間の計測を偽装しない。

- [x] UIテストを書く：ルート未入力で開始→pause→resume→終了確認→取り消し→終了。状態・操作可能ボタン・概要の数値を検証する。
- [x] 欠損心拍の「—」、GPS不良と最終取得時刻、保存失敗通知、全画面のデモ表示、40/44切り替えとタブ操作のテストを書く。
- [x] `npm test -- src/App.test.tsx`で失敗を確認する。
- [x] 3画面とフレームを実装。SVG軌跡は欠測区間で線を切り、北を上にして開始点・現在地を区別。「背景地図なし」を表示する。
- [x] 外側のデモ操作と画面サイズ切り替えを実装。指の移動量40px以上の横スワイプで画面切り替え、タブにキーボード操作と選択状態を設ける。
- [x] デモ操作と保存処理を接続。保存成功を確認できた時だけ保存済みと表示する。終了後の新規記録は前回記録を置き換えることを明示する。
- [x] `npm test`と`npm run build`を実行する。buildはTypeScriptチェックを含める。
- [x] ブラウザで40/44表示、モバイル幅、スワイプ、欠測・保存・復元を確認する。利用可能なブラウザ自動化手段を調べ、実施不能ならその範囲を正直に報告する。
- [x] READMEに`npm install`、`npm run dev -- --host 0.0.0.0`、テスト手順、デモ限定と背景地図なしの制約を書く。

## 完了と引き継ぎ

テストと本番ビルドの結果、起動URL、確認してほしい操作を報告する。
この環境の`.git`は有効なGitリポジトリとして認識されていないため、コミット・ブランチ作成を前提にしない。
ネイティブ版へ進む前に、Web試作へのフィードバックを受ける。
