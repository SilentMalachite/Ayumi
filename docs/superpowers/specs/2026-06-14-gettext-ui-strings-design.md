# Web層UI文字列の gettext 化 設計書

- 日付: 2026-06-14
- 対象: LiveView / Web コンポーネントに散在する日本語UI文字列を gettext 経由に集約
- ステータス: 実装完了（2026-06-14）

## 背景・問題

CLAUDE.md の規約: 「ユーザー向け文字列は日本語。gettext もしくは一箇所に集約し、inline リテラルとして散在させない」。

現状、Phoenix 既定の gettext バックエンド `AyumiWeb.Gettext` は導入済みで、フレームワーク由来の文字列（`core_components.ex` / `layouts.ex` の接続エラー表示など）は既に `gettext(...)` を使っている。しかしアプリ自身のUI文字列（画面見出し・フォームラベル・セクション名・ボタン・フラッシュ・プロンプト）は **LiveView 内に日本語リテラルとして散在**している（約108文字列）。これが規約の「散在させない」に反する。

調査で判明した重要事実:

- `gettext/1` マクロは `lib/ayumi_web.ex` の `:live_view`（43行目）と `:html`（83行目）の両 quote で `use Gettext, backend: AyumiWeb.Gettext` 済み。→ **全 LiveView/コンポーネントで import 追加不要**。
- enum ラベル（`Gender`/`SupportCategory`/`CertificateKind` の `@labels`）と changeset 検証メッセージは、**各ドメインモジュール内の一箇所に既に集約済み**であり「散在」ではない。
- `priv/gettext/errors.pot` と `en` ロケールは存在するが、アプリ文字列用の `default.pot` も `ja` ロケールも無い。

## 目標 / 非目標

目標:
- Web層に散在する日本語UI文字列を `gettext(...)` 経由に統一し、`mix gettext.extract` で **`priv/gettext/default.pot`（全文字列の中央マニフェスト）** を生成する。
- 既存の描画結果・テストを変えずに（リグレッションゼロで）これを達成する。

非目標:
- 多言語対応（言語切替）。アプリは単一施設・日本語のみ・オフライン・切替予定なし。
- ja ロケール PO の作成（msgid が日本語のため不要）。`default_locale` の変更も行わない。
- ドメイン層文字列（enum ラベル・changeset 検証メッセージ・`accounts.ex`）の gettext 化。既に集約済みであり、Web の gettext へ依存させると層の整合性を崩すため対象外。
- CLI（`mix ayumi.create_user`）の文言。ブラウザUIではないため対象外。

## 設計判断

### msgid 戦略: 日本語を msgid に

`gettext("利用者の編集")` のように日本語をそのまま msgid とする。gettext は未翻訳時に msgid を返すため、**表示文字列は完全に同一**。

- 利点: 差分最小、翻訳 PO の保守不要、`default.pot` が中央マニフェストになり将来の翻訳余地も残る。
- 単一言語アプリに最適。`default_locale`（既定 `en`）のままで日本語が表示される（未翻訳→msgid 返却のため）。

### 範囲: Web層の散在UI文字列のみ

| 区分 | 対象 | 理由 |
|---|---|---|
| 対象 | LiveView/コンポーネント内の見出し・ラベル・セクション名・ボタン・フラッシュ・プロンプト・ナビ | 散在している実体 |
| 対象外 | enum ラベル（ドメイン層） | 既に各モジュールに集約済み |
| 対象外 | changeset 検証メッセージ（ドメイン層） | 既に集約済み・errors ドメインの `translate_error` 経由 |
| 対象外 | `accounts.ex` の文言 | ドメイン層 |
| 対象外 | `mix ayumi.create_user`（CLI） | ブラウザUIではない |

## 対象ファイルと文字列の内訳（約108文字列）

- `lib/ayumi_web/live/service_user_live/form.ex`（41）— ページタイトル、フラッシュ、編集中バナー（補間あり）、`<h2>` セクション、`label=`、`prompt=`
- `lib/ayumi_web/live/service_user_live/show.ex`（39）— 見出し・項目ラベル・「登録なし」等
- `lib/ayumi_web/live/service_user_live/index.ex`（6）— 一覧見出し・「新規登録」等
- `lib/ayumi_web/live/support_plan_live/show.ex`（11）
- `lib/ayumi_web/live/support_plan_live/form.ex`（10）
- `lib/ayumi_web/components/layouts.ex`（1）— ナビリンク「利用者」

注: `user_live/login.ex` / `settings.ex` / `core_components.ex` には対象となるアプリ固有の日本語は無い（フレームワーク文字列は既に英語 msgid で gettext 済み）。実装時に最終 grep で確認する。

## 変換メカニクス

- **本体（Elixir）**: `assign(:page_title, gettext("利用者の編集"))` / `put_flash(:info, gettext("利用者情報を更新しました"))`
- **HEEx 本文**: `<h2 class="...">{gettext("基本")}</h2>` / `>{gettext("利用者")}<`
- **HEEx 属性**: `label={gettext("氏名")}` / `prompt={gettext("選択してください")}`
- **補間**（編集中バナー）: gettext は `%{key}` 形式。

  変更前:
  ```heex
  ⚠ {Enum.join(@other_editors, "、")} さんが現在この利用者を編集中です。同時に保存すると、一方の変更が反映されない場合があります。
  ```
  変更後:
  ```heex
  {gettext("⚠ %{names} さんが現在この利用者を編集中です。同時に保存すると、一方の変更が反映されない場合があります。", names: Enum.join(@other_editors, "、"))}
  ```
- **仕上げ**: `mix gettext.extract` を実行し `priv/gettext/default.pot` を生成してコミット。ja ロケールは作らない。

## 制約・エッジケース

- gettext の msgid は**コンパイル時の文字列リテラル必須**。動的・補間部分は msgid に含めず `%{}` プレースホルダにする。対象は全てリテラルで適合。
- HEEx 属性値は `{gettext(...)}` の波括弧で囲む。`phx-*` 等の他属性とは独立で干渉しない。
- `mix gettext.extract` は既に gettext 化済みのフレームワーク文字列も `default.pot` に集約する（全体マニフェストとして正しい挙動）。
- リテラルを変数に置換しない（`gettext(var)` は抽出不可）。

## テスト（`mix review` がゲート）

- **リグレッションゼロが主たる検証**: gettext は未翻訳時に msgid を返すため、描画される日本語は移行前と同一。既存の188テスト（`html =~ "..."`、フラッシュ文言、`render_*` の各アサーション）は**無改変で緑のまま**でなければならない。緑であることがそのまま「表示が変わっていない」証明になる。
- 1ファイルごとに gettext 化 → `mix test` で当該画面のテストが緑であることを確認しながら進める。
- 全完了後に `mix gettext.extract` を実行し `priv/gettext/default.pot` を生成、`mix gettext.extract --check-up-to-date` が通る（POT がコードと同期している）ことを確認。重ければ最低限 `default.pot` の生成・コミットのみでも可。
- 最終ゲート: `mix review`（format / compile --warnings-as-errors / credo / test）クリーン。

## スコープと進め方

- ファイル単位で段階的に gettext 化（画面ごとにテスト緑を確認）。
- 文字列の文言・句読点・空白は**一字一句変えない**（msgid とテストアサーションの一致を保つため）。
- 最後に `default.pot` を生成してコミット。

## 変更ファイル（見込み）

- `lib/ayumi_web/live/service_user_live/form.ex` / `show.ex` / `index.ex`
- `lib/ayumi_web/live/support_plan_live/form.ex` / `show.ex`
- `lib/ayumi_web/components/layouts.ex`
- 新規: `priv/gettext/default.pot`（`mix gettext.extract` 生成物）
- テストの変更は原則なし（無改変で緑を維持）。
