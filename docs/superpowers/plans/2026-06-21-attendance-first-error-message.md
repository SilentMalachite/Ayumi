# Attendance `first_error_message/1` → `translate_error/1` 再利用 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 実績記録票入力画面 (`AttendanceLive.Index`) の `save_day` で発生する changeset エラーを flash 化するヘルパー `first_error_message/1` を、既存ヘルパー `AyumiWeb.CoreComponents.translate_error/1` の再利用版へ置き換え、英語フィールド名の前置を消し、`%{count}` 等の補間が効くようにする。

**Architecture:** 単一ファイル内 private 関数 1 個の差し替え。`Ecto.Changeset.traverse_errors/2` による手書き整形を捨て、`changeset.errors` の先頭タプル `{msg, opts}` を `translate_error/1` に渡すだけのシンプルな実装に変える。呼び出し側 (`save_day` の `{:error, changeset}` 分岐) と外部公開 API は不変。

**Tech Stack:** Elixir / Phoenix LiveView / Ecto / Gettext (`AyumiWeb.Gettext`, domain `"errors"`)。テストは ExUnit + `Phoenix.LiveViewTest`。

## Global Constraints

- 対象は `lib/ayumi_web/live/attendance_live/index.ex` 内 **唯一の** `first_error_message/1`。他ファイルへの波及なし（呼び出しも同ファイル 1 箇所のみ）。
- フィールド名 (`start_time` 等の英語アトム) を**前置しない**こと。
- `translate_error/1` は **モジュール修飾** (`AyumiWeb.CoreComponents.translate_error/1`) で呼ぶ。`use AyumiWeb, :live_view` 経由で import 済みだが指示書のとおり確実性のため修飾。
- エラーが空 (理論上) の場合のフォールバック文言は従来どおり `gettext("保存できませんでした")` を維持。
- 既存テスト (`test/ayumi_web/live/attendance_live_test.exs` の 「終了<開始」テスト) は green のままで通す。新しい assertion 1 行だけ追加。
- `mix review` (format → 警告エラー扱い compile → credo → test) が green であることが完了条件。
- CHANGELOG への追記は不要（未リリースの実績記録票機能内の軽微改善）。
- スコープ外: §7 既知 Minor (秒表示 HH:MM 化、inline onclick → phx-hook、navbar `print:hidden` 実機確認)、認可ポリシー変更。

---

## File Structure

このタスクが触るファイル:

- **Modify:** `lib/ayumi_web/live/attendance_live/index.ex` (lines 237–243, `first_error_message/1` の本体差し替えのみ)。
- **Modify:** `test/ayumi_web/live/attendance_live_test.exs` (lines 192–213 の既存テストに `refute` 1 行追加)。

両ファイルとも責務に変更なし。新規ファイルなし。

---

## Task 1: `first_error_message/1` を `translate_error/1` 再利用版に置き換え + テスト固定

**Files:**
- Modify: `lib/ayumi_web/live/attendance_live/index.ex:237-243`
- Test: `test/ayumi_web/live/attendance_live_test.exs:192-213`

**Interfaces:**
- Consumes: `AyumiWeb.CoreComponents.translate_error({msg, opts})` — 既存。`opts[:count]` があれば `Gettext.dngettext(AyumiWeb.Gettext, "errors", msg, msg, count, opts)`、無ければ `Gettext.dgettext(AyumiWeb.Gettext, "errors", msg, opts)` を返す (`lib/ayumi_web/components/core_components.ex:447-463`)。`use AyumiWeb, :live_view` → `html_helpers` 経由で `AyumiWeb.CoreComponents` は import 済み (`lib/ayumi_web.ex:79-96`)。
- Consumes: `Ayumi.Plans.AttendanceRecord` の changeset。`changeset.errors` は `[{field :: atom, {msg :: String.t, opts :: keyword}} | ...]` 形式。
- Produces: `first_error_message/1` — private 関数。シグネチャ `(Ecto.Changeset.t) :: String.t` は変えない。呼び出し側 (`AyumiWeb.AttendanceLive.Index/handle_event "save_day"` 内 `{:error, changeset}` 分岐、同ファイル line 176) はそのまま動く。

- [ ] **Step 1: 既存テストの該当箇所を確認 (read-only)**

`test/ayumi_web/live/attendance_live_test.exs` の 192-213 行を読み、現在の assertion は次のとおりであることを確認:

```elixir
assert render(view) =~ "終了時刻は開始時刻より後にしてください"
assert Repo.aggregate(AttendanceRecord, :count, :id) == before_count
```

メッセージ本文 (`"終了時刻は開始時刻より後にしてください"`) は変わらない (このアプリの `priv/gettext/*/LC_MESSAGES/errors.po` に翻訳エントリは無く、`dgettext` は msgid をそのまま返すため)。

- [ ] **Step 2: 失敗するテスト追加 (RED) — フィールド名非表示の固定**

`test/ayumi_web/live/attendance_live_test.exs` の `test "end_time <= start_time shows error flash and does not append a row"` ブロック (192–213 行) 内、`assert render(view) =~ "終了時刻は開始時刻より後にしてください"` の **次の行** に以下を追加:

```elixir
      assert render(view) =~ "終了時刻は開始時刻より後にしてください"
      refute render(view) =~ "end_time 終了"
      assert Repo.aggregate(AttendanceRecord, :count, :id) == before_count
```

(既存の 2 つの assert に挟む形。インデントは既存テストに合わせ半角空白 6 個。)

- [ ] **Step 3: テストが落ちることを確認**

Run: `mix test test/ayumi_web/live/attendance_live_test.exs --only line:192`

(あるいは line 番号で絞らず `mix test test/ayumi_web/live/attendance_live_test.exs` でも可。)

Expected: 1 failure。`refute render(view) =~ "end_time 終了"` で失敗。原因は現行の `first_error_message/1` が `"end_time 終了時刻は開始時刻より後にしてください"` を返しており、flash 文字列内に `end_time` が含まれるため。

- [ ] **Step 4: `first_error_message/1` を置き換え (GREEN)**

`lib/ayumi_web/live/attendance_live/index.ex:237-243` の現行実装:

```elixir
defp first_error_message(changeset) do
  changeset
  |> Ecto.Changeset.traverse_errors(fn {msg, _opts} -> msg end)
  |> Enum.flat_map(fn {field, msgs} -> Enum.map(msgs, &"#{field} #{&1}") end)
  |> List.first()
  |> Kernel.||(gettext("保存できませんでした"))
end
```

を、次へ丸ごと差し替える:

```elixir
defp first_error_message(changeset) do
  case changeset.errors do
    [{_field, error} | _] -> AyumiWeb.CoreComponents.translate_error(error)
    [] -> gettext("保存できませんでした")
  end
end
```

ポイント:
- `changeset.errors` は `[{field, {msg, opts}} | ...]` のリスト (空の場合あり)。
- 先頭エントリの 2 要素目 `{msg, opts}` をそのまま `translate_error/1` に渡す。`translate_error/1` 側で `opts[:count]` があれば `dngettext`、無ければ `dgettext` の補間が走る。
- フィールド名は使わない (前置しない)。
- 空エラー時のフォールバック (`gettext("保存できませんでした")`) は維持。
- モジュール修飾は指示書どおり `AyumiWeb.CoreComponents.translate_error/1` を明示。

- [ ] **Step 5: テストが通ることを確認**

Run: `mix test test/ayumi_web/live/attendance_live_test.exs`

Expected: 全件 PASS (0 failures)。特に `end_time <= start_time ...` テストで:
- `assert render(view) =~ "終了時刻は開始時刻より後にしてください"` → 引き続き PASS (msgid そのまま表示されるため)。
- `refute render(view) =~ "end_time 終了"` → 新規 PASS (フィールド名が前置されなくなった)。

- [ ] **Step 6: `mix review` で品質ゲート通過確認**

Run: `mix review`

Expected: 0 errors / 0 warnings / 0 credo issues / すべてのテスト green。
失敗時の対応:
- `mix format` 差分が出たら本対応で導入したコードのインデント/改行を整える (上記置換コードは format 済みのはず)。
- credo の `Credo.Check.Refactor.Nesting` 等が出る可能性は低いが、もし指摘が出たら `case` を維持したまま改行/インデントだけ調整。
- compile warning の `unused alias` 等は本変更では発生しないはず (alias 追加なし、`Ecto.Changeset.traverse_errors/2` の参照は消えるがエイリアスは元から無い)。

- [ ] **Step 7: 触ったファイルと差分の自己確認 (read-only)**

Run: `git diff --stat lib/ayumi_web/live/attendance_live/index.ex test/ayumi_web/live/attendance_live_test.exs`

Expected: 2 files changed。`index.ex` は 7 行削除 / 6 行追加程度、テストは 1 行追加のみ。それ以外のファイルが変わっていないことを確認 (誤って他ファイルを触っていないか)。

- [ ] **Step 8: コミット**

```bash
git add lib/ayumi_web/live/attendance_live/index.ex test/ayumi_web/live/attendance_live_test.exs
git commit -m "$(cat <<'EOF'
fix: reuse translate_error/1 in attendance first_error_message

`AttendanceLive.Index` の save_day エラー flash がフィールド名
(start_time 等の英語アトム) を前置し、%{count} 等の interpolation も
展開していなかった。`AyumiWeb.CoreComponents.translate_error/1` を再利用
する版に置き換え、フィールド名の前置を削除。既存メッセージ本文の表示は
変わらず、標準 Ecto メッセージは正しく補間される。

Add `refute render(view) =~ "end_time 終了"` to lock the no-field-name behavior.
EOF
)"
```

---

## 完了条件 (Definition of Done)

- `first_error_message/1` が `translate_error/1` 再利用版に置き換わっている。
- `test/ayumi_web/live/attendance_live_test.exs` に `refute render(view) =~ "end_time 終了"` が追加されている。
- 既存テスト全件 green、追加 assertion も green。
- `mix review` が green。
- 触ったファイルは上記 2 ファイルのみ。

## スコープ外（混ぜない）

- §7 既知 Minor の他項目 (秒表示 HH:MM 化、inline onclick の phx-hook 化、navbar `print:hidden` 実機確認)。
- 認可ポリシー (出欠の全職員可) の変更。
- `AyumiWeb.CoreComponents.translate_error/1` 本体の改変。
- gettext 翻訳エントリ (`priv/gettext/**/errors.po`) の新規追加・更新。
