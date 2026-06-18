# 利用者 基本情報の拡充 設計仕様

- 日付: 2026-06-14
- 対象: `service_user`（利用者）に就労継続支援B型のフェイスシート相当の基本情報を持たせ、
  登録時に入力できるようにする。
- 前提: 既存の Ayumi（Step 0+1 完了済み・`main`）。`service_user` は現状 `name`/`name_kana` のみ。
- ステータス: 実装完了（2026-06-14）
- 関連: [[sqlite-ecto-gotchas]]（FK は raise / DB テストは async:false）。

## 0. 確定した決定事項（ブレインストーミング結果）

1. **障害者手帳は別テーブルで 1 対多**（`disability_certificate`）。今は複数所持者はいないが将来あり得る
   ため、最初から 1 対多にしてマイグレーション不要にする。
2. **手帳の登録UIは B 案**: スキーマは 1 対多だが、登録/編集フォームでは**手帳 1 件分の入力欄**を出す。
   複数対応（行の追加/削除）は将来フォームを拡張するだけで足り、データ移行は不要。
3. **受給者証は `service_user` に直接持つ**（この事業の受給者証は 1 人 1 枚）。
4. **基本情報は append-only ではなく編集可能な本体**。情報は変わるため、**編集画面を新設**する。
   （append-only はあくまで `plan_phase_event`/`goal_progress` の話。）
5. **必須は氏名のみ**。他はすべて任意（空欄可・後から追記）。
6. **画面**: 登録を一覧上のインラインから**専用ページ**へ移行。`/service_users/new`（新規登録）と
   `/service_users/:id/edit`（編集、同じフォーム部品を共有）。一覧は「新規登録」ボタン＋一覧。
   詳細は基本情報＋手帳＋（既存の）計画履歴を表示。
7. **列挙は専用モジュールに集約**。手帳種類・性別・障害支援区分は Ecto.Enum。**等級は自由入力**
   （身体 1〜6 級／精神 1〜3 級／療育は自治体差…と幅があるため硬直化させない）。障害名・通院先等も自由入力。
8. **コンテキストは現状どおり `Ayumi.Plans`** に置く（今は分割しない）。`plans.ex` が肥大化したら将来
   `Ayumi.People`（service_user + disability_certificate）への切り出しを検討（本仕様ではやらない）。

## 1. スキーマ

### service_user（拡張・編集可能な本体）

既存: `name`（★必須）, `name_kana`。以下を**すべて任意（nullable）**で追加:

| 列 | 型 | 区分 | 説明 |
|---|---|---|---|
| birthdate | date | 基本 | 生年月日 |
| gender | Ecto.Enum | 基本 | 性別（`male`/`female`/`other`） |
| postal_code | string | 連絡先 | 郵便番号 |
| address | string | 連絡先 | 住所（本人連絡先住所） |
| phone | string | 連絡先 | 電話番号 |
| emergency_contact_name | string | 連絡先 | 緊急連絡先 氏名 |
| emergency_contact_relation | string | 連絡先 | 続柄 |
| emergency_contact_phone | string | 連絡先 | 緊急連絡先 電話 |
| recipient_cert_number | string | 受給者証 | 受給者証番号 |
| recipient_cert_municipality | string | 受給者証 | 支給（発行）市町村 |
| disability_support_category | Ecto.Enum | 受給者証 | 障害支援区分（`not_applicable`/`category_1`..`category_6`） |
| benefit_amount | string | 受給者証 | 支給量（自由入力） |
| recipient_cert_expiry | date | 受給者証 | 受給者証 有効期限 |
| clinic_name | string | 医療 | 通院先（医療機関名） |
| attending_physician | string | 医療 | 主治医 |
| medication_notes | text | 医療 | 服薬・特記 |
| consultation_office | string | その他 | 相談支援事業所 |
| consultation_staff | string | その他 | 担当相談員 |
| notes | text | その他 | 備考 |

関連: `has_many :support_plans`（既存）, `has_many :disability_certificates, on_replace: :delete`。

### disability_certificate（障害者手帳・新規・1 対多）

| 列 | 型 | 必須 | 説明 |
|---|---|---|---|
| service_user_id | FK → service_users（`on_delete: :delete_all`） | ✓ | 親 |
| kind | Ecto.Enum（`physical`/`intellectual`/`mental`） | ✓ | 手帳の種類 |
| number | string | | 手帳番号 |
| disability_name | string | | 障害種類・障害名 |
| grade | string | | 等級（自由入力） |
| timestamps | | | |

- `on_delete: :delete_all`：手帳は親に従属する構成要素（親無しでは意味を持たない）。
- changeset: `cast([:kind, :number, :disability_name, :grade])` → `validate_required([:kind])`。
- インデックス: `index(:disability_certificates, [:service_user_id])`。

## 2. 列挙とラベルの集約（専用モジュール）

既存の方針（ラベルを 1 か所に集約・JP は散らさない）に従う。各モジュールは
`all/0`・`label/1`・`options/0`（select 用 `[{label, value}]`）を提供。スキーマは
`field :x, Ecto.Enum, values: Mod.all()`。

- `Ayumi.Plans.Gender` — `male`/`female`/`other`（男性／女性／その他）
- `Ayumi.Plans.SupportCategory` — `not_applicable`/`category_1`..`category_6`（非該当／区分1〜6）
- `Ayumi.Plans.CertificateKind` — `physical`/`intellectual`/`mental`
  （身体障害者手帳／療育手帳／精神障害者保健福祉手帳）

## 3. 任意の手帳 1 件（B 案）の取り扱い

フォームは `<.inputs_for>` で**手帳 1 行**を描画し、`ServiceUser.changeset` 側で
`cast_assoc(:disability_certificates, with: &DisabilityCertificate.changeset/2)`。

- **空行は永続化しない**: 手帳欄が全項目空のときは手帳レコードを作らない。実装は、コンテキストの
  `create_service_user/1`・`update_service_user/2` が**純粋関数**で空の手帳エントリをパラメータから除去
  してから changeset を組む（除去関数は単体テスト可能）。
- 将来 A 案（複数行）へ拡張する場合は、フォームに「行の追加/削除」を足すだけ。`cast_assoc` と
  `on_replace: :delete` により**データ移行不要**。
- フォーム表示時、手帳が 0 件なら LiveView 側で空の手帳 1 行を changeset に足して `inputs_for` が
  1 行描画されるようにする（この“空 1 行”の用意は LiveView の責務、コンテキストではない）。

## 4. コンテキスト（`Ayumi.Plans`）の追加・変更

- `change_service_user/2`（既存）— 追加フィールドを cast、`cast_assoc(:disability_certificates)` を含む。
- `create_service_user/1`（既存・変更）— 空手帳を除去してから insert。
- `update_service_user/2`（**新規**）— 編集用。`on_replace: :delete` で手帳の更新/削除に対応。
- `get_service_user!/1`（既存・変更）— `:disability_certificates` を preload。
- `list_service_users/0`（既存）— 並び順は不変（ふりがな→氏名）。
- `ServiceUser.age(service_user, today)`（**新規・純関数**）— 生年月日→年齢（保存しない・表示用）。

## 5. 画面（LiveView は薄く・ロジックは context へ）

- **Index `/service_users`**: 一覧表示（氏名・ふりがな・受給者証番号 等）＋「新規登録」ボタン
  （`navigate` で `/service_users/new`）。**インライン作成フォームは撤去**。
- **Form `/service_users/new`（:new）/ `/service_users/:id/edit`（:edit）**: 単一の `ServiceUserLive.Form`
  を `live_action` で分岐。**セクション分け**したフォーム（基本／連絡先／受給者証／手帳／医療／その他）。
  手帳は `inputs_for` で 1 行。保存成功で詳細へ `push_navigate`。検証は changeset（`phx-change="validate"`）。
- **Show `/service_users/:id`**: 基本情報をグループ表示＋手帳一覧＋（既存の）計画履歴＋「編集」ボタン。

ルートは認証済み `live_session` 内に追加。`:id/edit` と `:id`（show）の順序に注意（より具体的な
`/new` を `:id` より前に置く）。

## 6. エラー処理・プライバシー

- 検証はすべて changeset。氏名のみ必須、他は任意。Enum は Ecto.Enum が検証。日付は Ecto が型検証。
- 未存在 ID は `get_service_user!/1` が 404 相当で raise（既存方針と一貫）。
- 機微情報（医療・個人連絡先・障害情報）を扱うが、単一ホスト・LAN・オフライン・ローカル口座という
  配備モデル上、追加のインフラ（暗号化基盤等）は本仕様では導入しない。DB ファイルの取り扱いは
  CLAUDE.md の配備ルール（ローカルディスク／共有フォルダ禁止）に従う。

## 7. テスト（TDD・先に失敗テスト）

- 列挙モジュール: `all/0`・`options/0`・`label/1`。
- `ServiceUser` changeset: フル属性で valid／氏名必須／enum 不正値を弾く／`cast_assoc` で手帳を組む／
  空手帳除去で手帳が作られない。
- `DisabilityCertificate` changeset: `kind` 必須、他任意。
- コンテキスト: create（手帳あり／空手帳ドロップ）、update（フィールド変更・手帳の追加/更新/削除）、
  `get_service_user!/1` の手帳 preload、`age/2` の境界（誕生日前後）。
- LiveView: 新規登録（基本＋手帳まで作成）／編集（更新）／一覧の「新規登録」導線／詳細の基本情報・手帳表示。
- **`mix review` 緑**（format／compile --warnings-as-errors／credo／test）。

## 8. ビルド順（1 機能・各段階 green かつ `mix review` クリーンで次へ）

1. 列挙 3 モジュール（Gender / SupportCategory / CertificateKind）＋テスト。
2. `service_user` フラット項目追加（マイグレーション＋schema＋changeset）＋テスト。
3. `disability_certificate`（schema＋マイグレーション＋changeset）＋ `has_many`/`cast_assoc`/空手帳除去＋テスト。
4. コンテキスト: `update_service_user/2`、create の手帳処理、`get_service_user!` preload、`age/2`＋テスト。
5. UI: Index 改修（新規登録ボタン・インライン撤去）、`ServiceUserLive.Form`（new/edit・セクション・手帳 inputs_for）、
   Show 改修（基本情報＋手帳表示）、ルート、LiveView テスト。
6. `mix review` ゲート。

## 9. 非目標 / 将来課題（実装をブロックしない）

- 手帳の複数行 UI（A 案）は将来。スキーマは対応済み。
- 受給者証の履歴管理（更新の度に履歴を残す）は本仕様では行わない（フラット保持）。
- 緊急連絡先の複数件管理（今は 1 件分のフラット項目）。
- 暗号化・監査ログ等のセキュリティ強化。
- `Ayumi.People` コンテキストへの切り出し（`plans.ex` 肥大化時に検討）。
- 性別・障害支援区分の選択肢は施設の実運用に合わせ後から調整可能（enum を 1 か所で変更）。
