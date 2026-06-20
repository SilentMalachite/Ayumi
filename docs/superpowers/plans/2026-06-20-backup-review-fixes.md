# DB バックアップ レビュー指摘修正 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Codex の3指摘（P2: フラッシュ非表示 / P3-a: 完了表示に時刻なし / P3-b: 同一秒の再実行でファイル名衝突）を、TDD で最小差分により修正する。

**Architecture:**
- 既存の `Ayumi.Backups`（コンテキスト）と `AyumiWeb.BackupLive.Index`（LiveView）のみを触る。ルート / 権限 / `Layouts.app` の外側は変更しない。
- 順序は `Backups`（純関数）→ `LiveView`（描画 + assigns）。重いロジックほど先にテストで固定する。
- 「コンテキストで状態を導出し、LiveView は薄く保つ」というプロジェクト規約を踏襲する。

**Tech Stack:** Elixir 1.18 / Phoenix 1.8 / Phoenix LiveView / Ecto SQLite3 / ExUnit / Exqlite (VACUUM INTO 直結)

## Global Constraints

- 触ってよいファイルは以下の4本のみ。それ以外を差分に含めない:
  - `lib/ayumi/backups.ex`（`build_dest_path/2` のみ。他の関数は触らない）
  - `lib/ayumi_web/live/backup_live/index.ex`（`render/1` と `handle_event("backup", ...)` の成功節）
  - `test/ayumi/backups_test.exs`（追加のみ）
  - `test/ayumi_web/live/backup_live_test.exs`（追加のみ）
- ルート（`/admin/backup`）・`:require_manager` ・既存の inline alert は **触らない**。
- 表示時刻は **UTC 表記** で統一（ファイル名と同じ基準。JST 変換はやらない）。
- `DataCase` 配下のテストは `async: false`（SQLite 単一書き込みの制約）。新規テストの先頭もそれに従う。
- 並行レースの厳密排他（ロック）は範囲外。UI 二重送信 / cron 1秒重複の想定のみ塞ぐ。
- 完了の判定は `mix review`（format + compile --warnings-as-errors + credo + sobelow + test）グリーン。
- 既存 7 テストを **書き換えない**。新規テストの追加のみで P2/P3-a/P3-b を固定する。
- コミットメッセージ規約: `<type>: <description>` (fix / test / refactor)。1タスク1コミット。
- 日本語: ユーザー向け文字列は日本語のまま。識別子・コメントは英語。

---

## File Structure

| ファイル | 役割 | この計画での変更 |
| --- | --- | --- |
| `lib/ayumi/backups.ex` | バックアップ生成のコンテキスト（VACUUM INTO）。状態を持たない純粋寄り。 | `build_dest_path/2` を空き名探索方式に変更。private `available_path/3` を追加。 |
| `lib/ayumi_web/live/backup_live/index.ex` | `/admin/backup` の LiveView。マネージャー権限下で動く。 | `render/1` を `Layouts.app` で包む。成功節の `backup_info` に `:created_at` を追加し、成功ブロックに UTC 時刻表示を1行追加。 |
| `test/ayumi/backups_test.exs` | `Backups` 単体テスト（`async: false`） | 「同一秒タイムスタンプ衝突 → サフィックス回避」テストを 1 本追加。 |
| `test/ayumi_web/live/backup_live_test.exs` | LiveView 統合テスト（`async: false`） | 「完了フラッシュ表示」「成功時の時刻表示」テストを 2 本追加。 |

ファイル境界の理由:
- `build_dest_path/2` は純関数寄り（外部依存は `File.exists?/1` のみ）。コンテキストに閉じるので単体テストが容易。
- フラッシュと時刻表示は LiveView の責務（描画 + assigns）であり、コンテキスト側に漏らさない。

---

## Task 順序と依存

1. **Task 1: P3-b — `build_dest_path/2` の衝突回避（コンテキスト・純関数）**
2. **Task 2: P2 — `Layouts.app` で `render/1` を包む（フラッシュ表示）**
3. **Task 3: P3-a — 成功時の時刻表示（`:created_at` を UI に渡す）**
4. **Task 4: 全体品質ゲート（`mix review`）**

Task 1 → 2 → 3 の順は「下位から上位へ」。Task 2 と 3 は同じファイルを触るが、関心が違う（render 包む / 成功節 + 成功ブロック）ので別コミットに分ける。

---

### Task 1: P3-b — `build_dest_path/2` の衝突回避

**Files:**
- Modify: `lib/ayumi/backups.ex`（`build_dest_path/2` を差し替え、private `available_path/3` を末尾に追加）
- Test: `test/ayumi/backups_test.exs`（`describe "create_backup/2"` 内に1本追加）

**Interfaces:**
- Consumes: `Ayumi.Backups.create_backup/2`（既存）。`opts` に `:timestamp` を渡せること（既存仕様）。
- Produces:
  - 外部公開 API は不変。`create_backup/2` の返り値構造（`%{path, size_bytes, created_at}`）は変えない。
  - 副作用上の振る舞いだけ変わる: 同一 `:timestamp` で複数回呼ばれた場合、2回目以降は `_1`, `_2` … サフィックスで別パスを返す。

- [ ] **Step 1: 失敗するテストを追加（Red）**

`test/ayumi/backups_test.exs` の `describe "create_backup/2"` ブロック内、末尾（既存 `test "returns error when dest_dir is the same as the running DB directory"` の直後）に以下を追加する:

```elixir
    @tag :tmp_dir
    test "同じ秒のタイムスタンプでも2回目はサフィックスで衝突を避ける", %{tmp_dir: tmp_dir} do
      ts = ~N[2026-06-20 12:00:00]

      assert {:ok, info1} = Backups.create_backup(tmp_dir, timestamp: ts)
      assert {:ok, info2} = Backups.create_backup(tmp_dir, timestamp: ts)

      assert info1.path != info2.path
      assert File.exists?(info1.path)
      assert File.exists?(info2.path)
    end
```

- [ ] **Step 2: テストが失敗することを確認**

Run:
```
mix test test/ayumi/backups_test.exs -t tmp_dir
```
Expected: 追加した1本が FAIL（2回目の VACUUM INTO で `output file already exists` 相当のエラー）。既存テストは PASS。

- [ ] **Step 3: 実装（Green）— `build_dest_path/2` の差し替えと `available_path/3` 追加**

`lib/ayumi/backups.ex` の `build_dest_path/2` を以下に置き換える:

```elixir
  defp build_dest_path(dest_dir, opts) do
    now = Keyword.get(opts, :timestamp, NaiveDateTime.utc_now())
    base = "ayumi_backup_" <> Calendar.strftime(now, "%Y%m%d_%H%M%S")
    {:ok, available_path(dest_dir, base, 0)}
  end

  defp available_path(dir, base, count) do
    suffix = if count == 0, do: "", else: "_#{count}"
    path = Path.join(dir, base <> suffix <> ".sqlite3")

    if File.exists?(path) do
      available_path(dir, base, count + 1)
    else
      path
    end
  end
```

注:
- 通常時（衝突なし）は従来と同じファイル名になる。サフィックスは衝突時のみ。
- 関数の位置は `build_dest_path/2` の直後（private 関数の並びを守る）。

- [ ] **Step 4: テストが通ることを確認**

Run:
```
mix test test/ayumi/backups_test.exs
```
Expected: 既存3本 + 新規1本 = 4本すべて PASS。

- [ ] **Step 5: コミット**

```bash
git add lib/ayumi/backups.ex test/ayumi/backups_test.exs
git commit -m "fix: avoid backup filename collision on same-second reruns"
```

---

### Task 2: P2 — `Layouts.app` で `render/1` を包んでフラッシュを表示

**Files:**
- Modify: `lib/ayumi_web/live/backup_live/index.ex`（`render/1` のテンプレート全体を `<Layouts.app>` で包む）
- Test: `test/ayumi_web/live/backup_live_test.exs`（`describe "backup execution"` 内に1本追加）

**Interfaces:**
- Consumes:
  - `@flash` と `@current_scope` — `:require_manager` 配下の live_session で利用可能（`form.ex` ほかと同条件。既に確認済み: `support_plan_live/form.ex:72` などで同じ書式）。
  - 既存の `put_flash(:info, "バックアップが完了しました: ...")` — `handle_event("backup", ...)` の成功節に既にある。
- Produces: `render/1` の DOM が `Layouts.app` の `<.flash_group>` を含むようになり、フラッシュメッセージが画面上に出力される。

- [ ] **Step 1: 失敗するテストを追加（Red）**

`test/ayumi_web/live/backup_live_test.exs` の `describe "backup execution"` ブロック内、末尾に以下を追加する:

```elixir
    @tag :tmp_dir
    test "成功時に完了フラッシュが表示される", %{conn: conn, tmp_dir: tmp_dir} do
      {:ok, lv, _html} = live(conn, ~p"/admin/backup")

      html =
        lv
        |> form("#backup-form", %{dest_dir: tmp_dir})
        |> render_submit()

      # インラインは「バックアップ完了」。フラッシュ固有の文言で判定する。
      assert html =~ "バックアップが完了しました"
    end
```

メモ: 既存テスト `"creates backup successfully"` は `... or html =~ "ayumi_backup_"` の OR があるため、フラッシュ不在でも PASS してしまう。今回はこれを書き換えず、上の専用テストで P2 を固定する。

- [ ] **Step 2: テストが失敗することを確認**

Run:
```
mix test test/ayumi_web/live/backup_live_test.exs
```
Expected: 追加した1本が FAIL（`"バックアップが完了しました"` が html に含まれない）。既存テストは PASS。

- [ ] **Step 3: 実装（Green）— `render/1` 全体を `Layouts.app` で包む**

`lib/ayumi_web/live/backup_live/index.ex` の `render/1` を以下のように変更する。テンプレート全体を `<Layouts.app>` で囲み、既存 markup はそのまま残す（インラインの success / error alert も残す）:

```elixir
  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {gettext("データベースバックアップ")}
      </.header>

      <div class="mt-6">
        <form id="backup-form" phx-submit="backup" class="space-y-4">
          <div>
            <label for="dest_dir" class="block text-sm font-medium">
              {gettext("保存先ディレクトリ")}
            </label>
            <input
              type="text"
              name="dest_dir"
              id="dest_dir"
              value={@dest_dir}
              class="input input-bordered w-full mt-1"
              placeholder="/path/to/backup/directory"
              required
            />
            <p class="mt-1 text-sm text-base-content/60">
              {gettext("バックアップファイルの保存先を指定してください。タイムスタンプ付きのファイル名が自動生成されます。")}
            </p>
          </div>

          <button type="submit" class="btn btn-primary">
            {gettext("バックアップ実行")}
          </button>
        </form>

        <div :if={@result == :ok} class="mt-6 alert alert-success">
          <div>
            <p class="font-semibold">{gettext("バックアップ完了")}</p>
            <p class="text-sm">{@backup_info.path}</p>
            <p class="text-sm">{@backup_info.size_kb} KB</p>
          </div>
        </div>

        <div :if={@result == :error} class="mt-6 alert alert-error">
          <div>
            <p class="font-semibold">{gettext("バックアップに失敗しました")}</p>
            <p class="text-sm">{@backup_error}</p>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
```

注: `Layouts` は `use AyumiWeb, :live_view` 経由で import されており、`@current_scope` は live_session で assign 済み。他 LiveView と同じ作法。

- [ ] **Step 4: テストが通ることを確認**

Run:
```
mix test test/ayumi_web/live/backup_live_test.exs
```
Expected: 既存3本 + 新規1本 = 4本すべて PASS。

- [ ] **Step 5: コミット**

```bash
git add lib/ayumi_web/live/backup_live/index.ex test/ayumi_web/live/backup_live_test.exs
git commit -m "fix: wrap backup live view with Layouts.app so flash renders"
```

---

### Task 3: P3-a — 成功時に UTC 時刻を表示

**Files:**
- Modify: `lib/ayumi_web/live/backup_live/index.ex`
  - `handle_event("backup", ...)` の成功節: `backup_info` に `:created_at` を追加
  - `render/1` の成功ブロック (`<div :if={@result == :ok} ...>`): `Calendar.strftime` で UTC 時刻を1行追加
- Test: `test/ayumi_web/live/backup_live_test.exs`（同じ describe に1本追加）

**Interfaces:**
- Consumes: `Ayumi.Backups.create_backup/2` の戻り値 `info.created_at`（`DateTime.utc_now/0` の値。既存実装で既に返している）。
- Produces: UI 上に `YYYY-MM-DD HH:MM:SS UTC` 形式の時刻が成功ブロック内に出る。フラッシュ側の文言（Task 2 のもの）は変えない。

- [ ] **Step 1: 失敗するテストを追加（Red）**

`test/ayumi_web/live/backup_live_test.exs` の `describe "backup execution"` ブロック内、Task 2 で追加したテストの直後に以下を追加する:

```elixir
    @tag :tmp_dir
    test "成功時に保存時刻が表示される", %{conn: conn, tmp_dir: tmp_dir} do
      {:ok, lv, _html} = live(conn, ~p"/admin/backup")

      html =
        lv
        |> form("#backup-form", %{dest_dir: tmp_dir})
        |> render_submit()

      # 「YYYY-MM-DD HH:MM:SS」形式の時刻が出る（ファイル名の連結桁とは別物）
      assert html =~ ~r/\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}/
    end
```

メモ: ファイル名のタイムスタンプは `YYYYMMDD_HHMMSS`（区切り違い）なので、この正規表現はファイル名にはマッチしない。確実に成功ブロックの整形時刻を見ている。

- [ ] **Step 2: テストが失敗することを確認**

Run:
```
mix test test/ayumi_web/live/backup_live_test.exs
```
Expected: 追加した1本が FAIL（時刻形式の文字列が html に含まれない）。既存テストは PASS。

- [ ] **Step 3: 実装（Green-1）— `handle_event` の `backup_info` に `:created_at` を追加**

`lib/ayumi_web/live/backup_live/index.ex` の `handle_event("backup", ...)` 成功節（`{:ok, info} ->` ブロック）を以下に変更:

```elixir
      {:ok, info} ->
        backup_info = %{
          path: info.path,
          size_kb: div(info.size_bytes, 1024),
          created_at: info.created_at
        }
```

（残りの `assign` / `put_flash` 部分は変更しない）

- [ ] **Step 4: 実装（Green-2）— 成功ブロックに UTC 時刻表示を追加**

同ファイル `render/1` の成功ブロック（`<div :if={@result == :ok} class="mt-6 alert alert-success">` の中）に、`size_kb` 行の直後で `</div>` の直前に以下を追加:

```heex
          <p class="text-sm">
            {Calendar.strftime(@backup_info.created_at, "%Y-%m-%d %H:%M:%S UTC")}
          </p>
```

最終形（成功ブロックのみ抜粋）:

```heex
        <div :if={@result == :ok} class="mt-6 alert alert-success">
          <div>
            <p class="font-semibold">{gettext("バックアップ完了")}</p>
            <p class="text-sm">{@backup_info.path}</p>
            <p class="text-sm">{@backup_info.size_kb} KB</p>
            <p class="text-sm">
              {Calendar.strftime(@backup_info.created_at, "%Y-%m-%d %H:%M:%S UTC")}
            </p>
          </div>
        </div>
```

- [ ] **Step 5: テストが通ることを確認**

Run:
```
mix test test/ayumi_web/live/backup_live_test.exs
```
Expected: 5本すべて PASS。

- [ ] **Step 6: コミット**

```bash
git add lib/ayumi_web/live/backup_live/index.ex test/ayumi_web/live/backup_live_test.exs
git commit -m "fix: show backup created_at (UTC) in success block"
```

---

### Task 4: 品質ゲート（`mix review`）

**Files:** なし（検査のみ）

**Interfaces:**
- Consumes: Task 1–3 のすべての変更。
- Produces: グリーンの `mix review` 出力（完了報告に使う）。

- [ ] **Step 1: 全体テスト**

Run:
```
mix test
```
Expected: すべて PASS。Task 1–3 で追加した3本 + 既存テスト群が全部緑。

- [ ] **Step 2: `mix review` を流す**

Run:
```
mix review
```
Expected: format / compile --warnings-as-errors / credo / sobelow / test の全段がグリーン。

- [ ] **Step 3: 差分の最終確認**

Run:
```
git diff main --stat
```
Expected: 以下4ファイルだけが変更されている:
- `lib/ayumi/backups.ex`
- `lib/ayumi_web/live/backup_live/index.ex`
- `test/ayumi/backups_test.exs`
- `test/ayumi_web/live/backup_live_test.exs`

それ以外のファイルが含まれていたら、巻き戻して原因を確認する（スコープ外の変更が混入）。

- [ ] **Step 4: 完了報告**

以下のフォーマットで報告する:

1. 変更ファイルと概算 ±行数（`git diff --stat` の値）
2. 追加テストの要旨:
   - 衝突回避（`backups_test.exs`）
   - 完了フラッシュ表示（`backup_live_test.exs`）
   - 保存時刻表示（`backup_live_test.exs`）
3. `mix review` 末尾出力（グリーンの証跡）

---

## 受け入れ条件（指示書 §5 と対応）

- [ ] フラッシュテスト：成功時に「バックアップが完了しました」が html に出る（P2 / Task 2）
- [ ] 時刻テスト：成功ブロックに `YYYY-MM-DD HH:MM:SS` の時刻が出る（P3-a / Task 3）
- [ ] 衝突テスト：同一秒2回で別パスになり、両ファイルが存在する（P3-b / Task 1）
- [ ] 既存 7 テスト グリーン維持
- [ ] `mix review` グリーン
- [ ] 差分は §1 の4ファイルのみ

## やらないこと（スコープ厳守 / 指示書 §6 と対応）

- ルート / 権限（`/admin/backup` の `:require_manager`）は触らない
- 時刻の **JST 変換は行わない**（UTC 表記で統一）
- インラインの alert を削らない（フラッシュと役割が別）
- 並行レースの完全排他（ロック等）は実装しない
- ついでのリファクタ・整形をしない。最小差分
