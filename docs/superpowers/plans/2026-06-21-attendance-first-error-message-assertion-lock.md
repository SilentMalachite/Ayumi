# Attendance `first_error_message` 回帰固定アサーション 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `AttendanceLive.Index` の `first_error_message/1` から英語フィールド名前置きが消えたことを **`"end_time 終了"` 判別アサーション**で回帰固定する。あわせて先行プラン文書の永久失敗アサーション指定を実装に揃える。

**Architecture:** プロダクトコードは触らない（`first_error_message/1` は `290734a` で既に `translate_error/1` 再利用版に置換済み）。テスト 1 行と先行プラン文書 3 箇所の判別子文字列を `"end_time 終了"` に統一する。コミットは Fix A + Fix B の単一コミット。

**Tech Stack:** Elixir / Phoenix LiveView / ExUnit / `Phoenix.LiveViewTest`。品質ゲートは `mix review`（format → 警告エラー扱い compile → credo → test）。

## Global Constraints

- 仕様書: `docs/superpowers/specs/2026-06-21-attendance-first-error-message-assertion-lock-design.md`
- 判別子文字列は **`"end_time 終了"`**（半角空白 1 個区切り、ダブルクォート、半角コロンなし）。コードでも文書引用でも完全一致で揃える。
- 触ってよいファイル（2 つだけ）:
  - `test/ayumi_web/live/attendance_live_test.exs`
  - `docs/superpowers/plans/2026-06-21-attendance-first-error-message.md`
- 触らないファイル（明示的非スコープ）: `lib/ayumi_web/live/attendance_live/index.ex`（`first_error_message/1` は既修正）、`lib/ayumi_web/components/core_components.ex`、`priv/gettext/**`、その他テスト・認可ポリシー・§7 既知 Minor。
- インデントはテストファイルの既存行に合わせ半角空白 6 個。
- `mix review` green が完了条件。CHANGELOG 追記不要。
- Fix A と Fix B は単一コミットにまとめる（純テスト＋文書整合のため）。

---

## File Structure

このプランが触るファイル:

- **Modify:** `test/ayumi_web/live/attendance_live_test.exs:211`
  - 役割: `"end_time <= start_time shows error flash and does not append a row"` テストの判別アサーション 1 行を `"end_time "` → `"end_time 終了"` に書き換え。前後の本文 assert と件数 assert は不変。
- **Modify:** `docs/superpowers/plans/2026-06-21-attendance-first-error-message.md`
  - 役割: Step 2 / Step 3 / Step 5 内の `refute render(view) =~ "end_time"`（空白なし）3 箇所を `"end_time 終了"` に統一。挙動には影響しない文書整合。

新規ファイルなし。プロダクトコード（`lib/**`）には差分が出ない。

---

## Task 1: 実テストの判別アサーションを `"end_time 終了"` に書き換え + プラン文書整合 + 品質ゲート + コミット

**Files:**
- Modify: `test/ayumi_web/live/attendance_live_test.exs:211`
- Modify: `docs/superpowers/plans/2026-06-21-attendance-first-error-message.md`
  （Step 2 のコードフェンス内、Step 3 Expected 文、Step 5 Expected 文の 3 箇所）

**Interfaces:**
- Consumes:
  - 既存 `AyumiWeb.AttendanceLive.Index/first_error_message/1`（`290734a` で `translate_error/1` 再利用済み・本プランでは触らない）。
  - 既存テスト `test "end_time <= start_time shows error flash and does not append a row"`（行 191–213、本プランでは判別子 1 行だけ書き換え）。
- Produces:
  - 同テスト内の判別アサーション `refute render(view) =~ "end_time 終了"`。旧バグ flash 形 `end_time 終了時刻は…` の頭 5 文字＋区切り＋本文先頭 2 文字を狙う固定子。
  - プラン文書の引用が実テストと完全一致。

---

- [ ] **Step 1: 現状確認（read-only）— 実テスト L210–212**

実テストの現在の該当行（半角空白 6 個インデント前提）を確認する。

Run:
```bash
sed -n '210,212p' test/ayumi_web/live/attendance_live_test.exs
```

Expected output:
```
      assert render(view) =~ "終了時刻は開始時刻より後にしてください"
      refute render(view) =~ "end_time "
      assert Repo.aggregate(AttendanceRecord, :count, :id) == before_count
```

L211 が `"end_time "`（末尾半角空白 1 個）であることを目視確認。違っていたら STOP して報告（先行修正がさらに進んでいる可能性がある）。

---

- [ ] **Step 2: 現状確認（read-only）— プラン文書側の永久失敗指定**

先行プラン文書側で「`refute render(view) =~ "end_time"`」（空白なし）が 3 箇所出ていることを確認する。

Run:
```bash
grep -n 'refute render(view) =~ "end_time"' docs/superpowers/plans/2026-06-21-attendance-first-error-message.md
```

Expected: 3 行ヒット（Step 2 のコードフェンス内 / Step 3 Expected 文 / Step 5 Expected 文）。0 件や 1–2 件なら STOP して報告（仕様書と前提がずれている）。

---

- [ ] **Step 3: 修正前に当該テスト 1 件だけ走らせて現状 green を確認**

修正前ベースラインを取り、後段の修正で偶発的に他のテストが落ちていないか比較できるようにする。

Run:
```bash
mix test test/ayumi_web/live/attendance_live_test.exs -t "end_time <= start_time shows error flash and does not append a row"
```

（あるいはタグ指定が効かない場合は対象ファイル全体でも可: `mix test test/ayumi_web/live/attendance_live_test.exs`）

Expected: green（`first_error_message/1` は既に修正済み、判別子 `"end_time "` も現状の render では出ない）。

ここで赤になる場合は本プランの前提が崩れているため STOP して報告。

---

- [ ] **Step 4: Fix A — 実テスト L211 の判別子を書き換え**

`test/ayumi_web/live/attendance_live_test.exs` の L211 を以下に書き換える。

From:
```elixir
      refute render(view) =~ "end_time "
```

To:
```elixir
      refute render(view) =~ "end_time 終了"
```

書き換え方法（Serena の `replace_content` か Edit ツールで一意置換）:
- 対象は L211 ただ 1 行。
- インデントは既存どおり半角空白 6 個。
- 前後（L210 の本文 assert、L212 の件数 assert）は不変。

書き換え後の L210–212 の期待形:
```elixir
      assert render(view) =~ "終了時刻は開始時刻より後にしてください"
      refute render(view) =~ "end_time 終了"
      assert Repo.aggregate(AttendanceRecord, :count, :id) == before_count
```

---

- [ ] **Step 5: Fix A 確認 — 該当テストを走らせて green を確認**

Run:
```bash
mix test test/ayumi_web/live/attendance_live_test.exs
```

Expected: ファイル全件 green。特に `"end_time <= start_time shows error flash and does not append a row"` テストで:
- L210 本文 assert: PASS（`first_error_message/1` は msgid をそのまま flash する）。
- L211 判別 refute: PASS（`first_error_message/1` は `translate_error/1` 再利用版で `end_time` を前置しない。HTML 属性側にも `end_time 終了` の並びは出ない）。
- L212 件数 assert: PASS（changeset エラー時は append されない）。

赤が出る場合の対応:
- L210 が赤 → render に msgid 本文が出ていない。`first_error_message/1` 実装が想定外。仕様書の前提を再確認。
- L211 が赤 → render に `end_time 終了` 並びが出ている。`first_error_message/1` 実装が想定外、または HTML 内に新たな `end_time 終了` 並びの混入。出力を確認し原因切り分けの上 STOP。
- L212 が赤 → save_day が想定外に append している。先行修正の回帰の可能性、STOP。

---

- [ ] **Step 6: Fix B — 先行プラン文書 3 箇所の引用を `"end_time 終了"` に統一**

`docs/superpowers/plans/2026-06-21-attendance-first-error-message.md` の以下 3 箇所を書き換える。書き換え方法は一括 sed か Edit ツール一意置換。

**Step 6-a:** Step 2 のコードフェンス内（複数行ブロック内の中央行）。

From:
```elixir
      assert render(view) =~ "終了時刻は開始時刻より後にしてください"
      refute render(view) =~ "end_time"
      assert Repo.aggregate(AttendanceRecord, :count, :id) == before_count
```

To:
```elixir
      assert render(view) =~ "終了時刻は開始時刻より後にしてください"
      refute render(view) =~ "end_time 終了"
      assert Repo.aggregate(AttendanceRecord, :count, :id) == before_count
```

**Step 6-b:** Step 3 Expected 文中（散文）。

From:
> Expected: 1 failure。`refute render(view) =~ "end_time"` で失敗。

To:
> Expected: 1 failure。`refute render(view) =~ "end_time 終了"` で失敗。

**Step 6-c:** Step 5 Expected 文中（散文）。

From:
> - `refute render(view) =~ "end_time"` → 新規 PASS (フィールド名が前置されなくなった)。

To:
> - `refute render(view) =~ "end_time 終了"` → 新規 PASS (フィールド名が前置されなくなった)。

書き換えに sed を使うなら:
```bash
sed -i '' 's/refute render(view) =~ "end_time"/refute render(view) =~ "end_time 終了"/g' \
  docs/superpowers/plans/2026-06-21-attendance-first-error-message.md
```
（macOS の `sed -i ''` で in-place。文字列内に `"end_time"`（空白なし）が他用途で混在しないことを Step 2 のヒット 3 件で確認済み。）

検証:
```bash
grep -n 'refute render(view) =~ "end_time' docs/superpowers/plans/2026-06-21-attendance-first-error-message.md
```

Expected: 3 行ヒット、すべて `"end_time 終了"` で終わる。

`"end_time"`（空白なし版）が grep で残っていたら Step 6 を再実行 / 手動で潰す。

---

- [ ] **Step 7: 触ったファイルの差分確認（read-only）**

Run:
```bash
git status
git diff --stat
```

Expected:
- 触ったファイル 2 つだけ:
  - `test/ayumi_web/live/attendance_live_test.exs`（1 行変更）
  - `docs/superpowers/plans/2026-06-21-attendance-first-error-message.md`（数行変更）
- `lib/**` / `priv/**` には差分なし。
- 他テストファイルにも差分なし。

それ以外のファイルに差分が出ていたら STOP して内容を確認（誤った置換が混入している可能性）。

---

- [ ] **Step 8: 品質ゲート — `mix review` green**

Run:
```bash
mix review
```

Expected: 0 errors / 0 warnings / 0 credo issues / 全テスト green。

`mix review` で落ちる場合の典型と対応:
- `mix format` 差分 → 本変更は文字列リテラル 1 行のみで format に影響しないはずだが、CRLF / タブ混入があれば直す。
- credo 指摘 → 本変更ではテストファイルの 1 行を書き換えただけのため新規指摘は起きないはず。出たら内容を確認の上、本変更起因か既存指摘かを切り分け、本変更起因なら直す。既存指摘なら範囲外として STOP し報告。
- compile warning → 同上、本変更起因なら直す、既存なら STOP し報告。
- test 失敗 → Step 5 の追加検証どおり切り分け。

---

- [ ] **Step 9: コミット**

Run:
```bash
git add test/ayumi_web/live/attendance_live_test.exs \
        docs/superpowers/plans/2026-06-21-attendance-first-error-message.md
git commit -m "$(cat <<'EOF'
fix: tighten attendance error flash assertion to "end_time 終了"

`first_error_message/1` の修正 (translate_error/1 再利用) を回帰として固定
するため、attendance_live_test.exs の判別アサーションを `"end_time "`
(末尾空白) から `"end_time 終了"` (旧連結固有の英語アトム+空白+本文頭) に
強化。旧バグの flash 形 `end_time 終了時刻は開始時刻より後にしてください`
だけがヒットする並びで、HTML 属性や phx-value-* には現れないため誤ヒット
しない。

あわせて先行プラン文書 (docs/superpowers/plans/2026-06-21-attendance-
first-error-message.md) 内の永久失敗指定 `refute ... "end_time"` を
実装テストに揃え `"end_time 終了"` に統一。プロダクト挙動は不変。
EOF
)"
```

Expected: 1 commit。`git log -1 --stat` で 2 ファイル変更が確認できる。

---

- [ ] **Step 10: コミット後の最終確認**

Run:
```bash
git log -1 --stat
git status
```

Expected:
- 最新コミットが上記メッセージで、変更ファイルは 2 つだけ。
- 作業ツリーは clean（追加で残った差分が無い）。

clean でなければ漏れがある。残差分を確認して追跡 / 取り消しを判断。

---

## 完了条件（Definition of Done）

- `test/ayumi_web/live/attendance_live_test.exs:211` が `refute render(view) =~ "end_time 終了"` になっている。
- `docs/superpowers/plans/2026-06-21-attendance-first-error-message.md` 内の 3 箇所の判別子引用がすべて `"end_time 終了"` に統一されている。
- `mix review` が green。
- 触ったファイルは上記 2 ファイルのみ（`git diff --stat` で確認済）。
- `lib/ayumi_web/live/attendance_live/index.ex` および `AyumiWeb.CoreComponents` には変更なし。
- 1 コミットで Fix A・Fix B が同梱されている。
- CHANGELOG 追記なし。

## スコープ外（混ぜない）

- `first_error_message/1` 本体の再変更（既に `290734a` で修正済み）。
- `AyumiWeb.CoreComponents.translate_error/1` の改変。
- `priv/gettext/**/errors.po` の翻訳エントリ追加・更新。
- §7 既知 Minor（秒表示 HH:MM 化 / inline onclick → phx-hook / navbar `print:hidden` 実機確認）。
- 出欠の認可ポリシー変更。
- 他テストの追加・整理。
