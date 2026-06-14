# 同時編集の安全化 設計書（案A 楽観ロック ＋ 案B 編集中表示）

- 日付: 2026-06-14
- 対象: 複数スタッフが本体テーブルを同時編集したときの「黙った上書き（lost update）」対策
- ステータス: 承認済み（実装計画へ）

## 背景・問題

現状コードは技術的にはすでに複数ユーザー同時利用に対応している（複数アカウント可・セッション排他なし・`journal_mode: :wal` / `busy_timeout: 5_000` / `pool_size: 5` / `foreign_keys: :on`）。
そのため「database is locked」系は概ね緩和済みで、6人規模では実害が出にくい。

残る本丸は **ロスト・アップデート（後勝ちで黙って上書き）**。

- 追記式ログ（`goal_progress` / `plan_phase_event`）は insert-only のため上書きが起きない（構造上の利点）。
- 上書きリスクは **本体テーブル `service_users` / `support_plans` / `goals`** の in-place 更新にのみ存在する。
- 現状で実際に更新関数があるのは `Ayumi.Plans.update_service_user/2` のみ。`support_plan` / `goal` は今は作成のみだが、編集機能が付くと同じリスクを抱える。

## 目標 / 非目標

目標:
- 本体テーブルの同時編集で、片方の変更が黙って消える事象を**根絶**する。
- 衝突を事前に減らす UX（「○○さん編集中」）を、外部依存なし・完全オフラインで提供する。

非目標:
- 自動マージ（コンフリクト解決）は行わない。検知して再編集を促す。
- 追記式ログへの変更は行わない（対象外）。
- 担当(担当者)によるアクセス制御（スコープ）は本件のスコープ外（別途）。
- 本体の追記式化（案C）は採用しない。

## 全体像

本体テーブルに2層を重ねる。考え方は **案Aが正しさの土台、案BはUXの上乗せ**。案Bを無視しても案Aがデータ損失を必ず防ぐ。

| 層 | 役割 | 保証の強さ |
|---|---|---|
| 案A 楽観ロック | 黙った上書きを根絶（後勝ちを検知して弾く） | ハード保証 |
| 案B 編集中表示 | 衝突を事前に減らす（「○○さん編集中」） | 助言（ソフト） |

## 案A：楽観ロック（optimistic lock）

1. **マイグレーション**: 3本体すべてに `lock_version :integer, null: false, default: 0` を追加。追記的・後方互換（既存行は default 0）。
2. **スキーマ**: 各 schema に `field :lock_version, :integer, default: 0`。`cast` 対象には**入れない**（フォーム経由の改ざん不可）。
3. **コンテキスト** (`Ayumi.Plans`): 更新関数で `Repo.update` の前に `Ecto.Changeset.optimistic_lock(:lock_version)` を噛ませ、`Ecto.StaleEntryError` を rescue して `{:error, :stale}` を返す。

```elixir
def update_service_user(%ServiceUser{} = service_user, attrs) do
  service_user
  |> ServiceUser.changeset(drop_blank_certificates(attrs))
  |> Ecto.Changeset.optimistic_lock(:lock_version)
  |> Repo.update()
rescue
  Ecto.StaleEntryError -> {:error, :stale}
end
```

`optimistic_lock` は `changeset.data`（＝読込時 struct）の `lock_version` から `WHERE` を組み、更新成功時に値を +1 する。LiveView は読込時 struct を assign に保持し続け、それを更新ベースに渡すため **hidden フィールドは不要**。

4. **LiveView**: 編集 `save` に第3分岐を追加。

```elixir
{:error, :stale} ->
  {:noreply,
   socket
   |> put_flash(:error, "他のスタッフが先にこの利用者を更新しました。最新を読み込みました。内容を確認して保存し直してください。")
   |> reload_and_assign_form()}  # get_service_user! し直して最新をフォームに反映
```

自動マージはしない（検知＋再編集を促す）。

## 案B：編集中表示（Phoenix.Presence）

外部依存ゼロ・完全オフライン。`Phoenix.PubSub`（`Ayumi.PubSub`）は既に supervision tree に存在する。

1. `AyumiWeb.Presence`（`use Phoenix.Presence, otp_app: :ayumi, pubsub_server: Ayumi.PubSub`）を新設し、`application.ex` の supervision tree（PubSub の後）に追加。
2. **トピック**: `"editing:service_user:#{id}"`（後で `"editing:support_plan:#{id}"` も同形）。トピック生成は小さなヘルパに集約。
3. 編集フォーム `apply_action(:edit)` で `connected?(socket)` のとき:
   - 当該トピックを `subscribe`。
   - `AyumiWeb.Presence.track(self(), topic, user_id, %{name: display_name})`。
   - `Presence.list(topic)` から**自分以外**を集めて `:other_editors` に assign。
4. `%Phoenix.Socket.Broadcast{event: "presence_diff"}` を `handle_info` で受け、`:other_editors` を再計算して assign。
5. **表示**: `@other_editors != []` のとき警告バナー「⚠ ○○さん が現在この利用者を編集中です。同時に保存すると一方の変更が反映されない場合があります。」。保存ボタンは活かす（ソフト）。
6. **自動解除**: LiveView プロセス終了（離脱・切断・タブ閉じ）で Presence が自動 untrack。手動掃除不要。

Presence のキーは `current_scope.user.id`、メタは `%{name: User.display_name(user)}`。`@current_scope` は編集フォームで利用可能。

## データフロー（A・B が利用者#5 を同時編集、lock_version=3）

1. 両者が編集画面を開く → 互いに「⚠ ○○さん編集中」を見る。
2. A が保存 → `UPDATE ... WHERE id=5 AND lock_version=3` 成立 → 4 に増分・成功・離脱。
3. B が保存（ベースは 3）→ 0 件一致 → `StaleEntryError` → `{:error, :stale}` → B にフラッシュ＋最新(=A の内容, lv4)を再読込 → B が再適用して保存 → 成功(lv5)。

結果: 黙った上書きゼロ。B は気づいて再適用できる。

## エラー処理

- `{:error, %Ecto.Changeset{}}` = 検証エラー（従来どおり）。
- `{:error, :stale}` = 同時更新（新規）。
- Presence / PubSub 障害は非致命（UX 層）。落ちても編集は可能、表示が出ないだけ。
- `StaleEntryError` 以外の DB 例外は握りつぶさず素通しさせる。

## テスト（TDD・`mix review` がゲート）

- **コンテキスト**（`async: false`）:
  - 更新で `lock_version` が +1 される。
  - 同一行を二重読込 → 先勝ち成功・後勝ちが `{:error, :stale}`。
- **changeset**: `lock_version` が cast 対象外（フォーム改ざん不可）。
- **LiveView**:
  - 編集成功パスが従来どおり動く。
  - mount と保存の間に裏で更新 → stale フラッシュ＋最新再読込を検証。
  - 同一トピックに 2 つ mount → 「編集中」警告が出る。

## スコープ

- マイグレーションは **3本体すべて**に `lock_version` を先置き（1本で済み、将来分も揃う）。
- 配線（案A の optimistic_lock + stale 処理、案B の Presence）は **今編集 UI がある画面だけ**に入れる。
  - まず **利用者(`service_user`)の編集** に案A＋案Bを実装。
  - `support_plan` / `goal` は更新関数・編集 UI が付く段で同パターンを適用（列は先に用意済み）。

## 変更ファイル（見込み）

- 新規マイグレーション: `service_users` / `support_plans` / `goals` に `lock_version`。
- `lib/ayumi/plans/service_user.ex` / `support_plan.ex` / `goal.ex`: `field :lock_version`。
- `lib/ayumi/plans.ex`: `update_service_user/2` に optimistic_lock + stale rescue。
- `lib/ayumi_web/live/service_user_live/form.ex`: stale 分岐、Presence track/subscribe/diff、警告バナー。
- `lib/ayumi_web/presence.ex`（新規）。
- `lib/ayumi/application.ex`: `AyumiWeb.Presence` を supervision tree に追加。
- テスト: `test/ayumi/plans_test.exs`、`test/ayumi_web/live/service_user_live_test.exs`。
