# 仕様: `first_error_message` 修正の回帰固定アサーション

**Date:** 2026-06-21
**Scope:** テスト 1 行差し替え + プラン文書整合（コードのプロダクト挙動は変えない）
**Source:** `~/Desktop/ayumi_fix_assertion_regression_lock.md`

## 目的

`AyumiWeb.AttendanceLive.Index` の `first_error_message/1` は、コミット `290734a`
で `AyumiWeb.CoreComponents.translate_error/1` 再利用版に置換済み。これにより
flash から英語フィールド名の前置き（例: `end_time 終了時刻は…`）が消えた。
ところが現行テスト（`test/ayumi_web/live/attendance_live_test.exs:210-212` の
`"end_time <= start_time shows error flash and does not append a row"`）の
判別アサーションは末尾空白付きの `"end_time "` 止まりで、旧連結固有の並び
（英語アトム + 空白 + 日本語本文）を厳密に固定できていない。本仕様では、
指示書どおり `"end_time 終了"` を判別子にしてこの修正の回帰を固定する。

## 背景

- 旧バグの flash 文字列: `end_time 終了時刻は開始時刻より後にしてください`
- 修正後の flash 文字列: `終了時刻は開始時刻より後にしてください`
- 既存 `assert ... =~ "終了時刻は開始時刻より後にしてください"` は **修正前後どちらでも**
  通るため回帰検出力が無い。
- 末尾空白付きの `"end_time "` も偽陽性は出にくいが、旧バグ固有性を示さない
  （`phx-value-*` 等で `end_time ` が将来混入する可能性が残る）。
- `"end_time 終了"` は **旧連結だけが取り得る並び**。HTML 属性
  (`name="attendance_record[end_time]"` は `end_time]`、`phx-value-field="end_time"`
  は `end_time"`) には現れず、`gettext` フォールバック (`"保存できませんでした"`)
  にも `end_time` 自体が出ない。よって誤ヒットしない強い判別子。

## 変更スコープ

### Fix A（必須・実テスト）

- **File:** `test/ayumi_web/live/attendance_live_test.exs`
- **Line:** 211
- **From:** `      refute render(view) =~ "end_time "`
- **To:**   `      refute render(view) =~ "end_time 終了"`

既存の本文 `assert`（L210）と件数 `assert`（L212）はそのまま残す。
インデントは半角空白 6 個（既存コードに合わせる）。

### Fix B（プラン文書整合）

- **File:** `docs/superpowers/plans/2026-06-21-attendance-first-error-message.md`
- 本ファイルは `git status` で untracked（不変扱い運用に該当せず）。
- 以下 3 か所の引用を `"end_time 終了"` に統一する:
  - Step 2 本文（コードフェンス内）の `refute render(view) =~ "end_time"`
  - Step 3 Expected 文中の `refute render(view) =~ "end_time"`
  - Step 5 Expected 文中の `refute render(view) =~ "end_time"`
- `git diff --stat` 期待値（Step 7）と Step 8 コミットメッセージは触らない
  （実テスト 1 行差し替えで済むため、差分行数の見立ては変わらない）。
- 文書のみの修正のためプロダクト挙動・テスト挙動には影響しない。

### 触らないファイル（明示的非スコープ）

- `lib/ayumi_web/live/attendance_live/index.ex`（`first_error_message/1` は既修正）
- `lib/ayumi_web/components/core_components.ex`（`translate_error/1` 本体）
- `priv/gettext/**/errors.po`（翻訳エントリ追加・更新なし）
- 他のテスト、認可ポリシー、§7 既知 Minor（秒表示 HH:MM 化 / inline onclick の
  phx-hook 化 / navbar `print:hidden` 実機確認）

## 判別子論拠（なぜ `"end_time 終了"` で偽陽性が出ないか）

| 出現箇所 | 文字列パターン | `=~ "end_time 終了"` |
|----------|-----------------|----------------------|
| 旧バグ flash 本文 | `end_time 終了時刻は開始時刻より後にしてください` | ○（固定対象） |
| フォーム属性 | `name="attendance_record[end_time]"` | × （直後が `]`） |
| `phx-*` 属性 | `phx-value-field="end_time"` 等 | × （直後が `"`） |
| 他フィールドの changeset 訳 | `start_time …` | × （`end_time` 自体出ない） |
| 空エラー時のフォールバック | `保存できませんでした` | × （`end_time` 出ない） |
| 翻訳更新リスク | `priv/gettext/**/errors.po` に該当 msgid 無し | × （現状） |

→ 旧連結のみが満たす並びのため、回帰検出に十分強い。

## 実装手順

1. **テスト修正（Fix A）**: `test/ayumi_web/live/attendance_live_test.exs:211`
   の文字列リテラルを `"end_time "` → `"end_time 終了"` に置換。
2. **プラン文書修正（Fix B）**: 上記 3 箇所を `"end_time 終了"` に統一。
3. **テスト実行**: `mix test test/ayumi_web/live/attendance_live_test.exs`
   → 全件 green。`first_error_message/1` は既に修正済みのため追加判別子も
   そのまま通る。
4. **品質ゲート**: `mix review`（format → 警告エラー扱い compile → credo →
   全テスト）→ green。
5. **コミット**: Fix A・Fix B をまとめて 1 コミット。
   メッセージ案: `fix: tighten attendance error flash assertion to "end_time 終了"`

## 完了条件（Definition of Done）

- `test/ayumi_web/live/attendance_live_test.exs:211` が
  `refute render(view) =~ "end_time 終了"` になっている。
- `docs/superpowers/plans/2026-06-21-attendance-first-error-message.md`
  内の判別子引用が `"end_time 終了"` に統一されている。
- `mix review` が green。
- 触ったファイルは上記 2 ファイルのみ（`git diff --stat` で確認）。
- CHANGELOG 追記なし。
- `lib/ayumi_web/live/attendance_live/index.ex` および
  `AyumiWeb.CoreComponents` には変更なし。

## リスク・代替案

- **リスク:** `priv/gettext/**/errors.po` に将来 msgid
  `"終了時刻は開始時刻より後にしてください"` の翻訳が入り、`終了` が消える
  訳語に置換された場合、判別子の意図が壊れる。現状はエントリ無しで実害なし。
  影響範囲が小さく、翻訳追加時にテストが落ちれば即気付ける。
- **代替案 B（不採用）:** 実テスト現状の `"end_time "` を残してプラン文書だけ
  揃える案。判別子論拠が指示書本文と一致せず、偽陽性余地（`end_time ` を
  含む属性値の将来混入）が残るため不採用。
