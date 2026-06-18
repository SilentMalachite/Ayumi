# 利用者 基本情報の拡充 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** `service_user`（利用者）にフェイスシート相当の編集可能な基本情報（連絡先・受給者証・医療・その他）と 1 対多の障害者手帳（`disability_certificate`）を持たせ、専用の新規登録/編集/詳細画面から扱えるようにする。

**Architecture:** 列挙は専用モジュール（`all/0`・`label/1`・`options/0`）に集約し `Ecto.Enum` で参照。基本情報は append-only ではなく編集可能な本体として `service_user` を拡張。手帳はスキーマ上 1 対多（`has_many` + `cast_assoc` + `on_replace: :delete`）だが UI は手帳 1 行（B 案）。空の手帳行は永続化前にコンテキストの純関数で除去。登録は一覧のインラインから `ServiceUserLive.Form`（`:new`/`:edit` を `live_action` で分岐）へ移行。

**Tech Stack:** Elixir / Phoenix LiveView / Ecto + SQLite（`ecto_sqlite3`）。テストは ExUnit。品質ゲートは `mix review`。

---

## 既知の注意点（着手前に読む）

- **SQLite × async（[[sqlite-ecto-gotchas]]）**: 純粋な changeset/enum/age のテストは DB に触れないので `async: true`（既存 `service_user_test.exs` と同じ）。DB に触れる**コンテキスト/LiveView テスト**は既存ファイル（`plans_test.exs` は `async: true`、`*_live_test.exs` は `ConnCase` で非 async）に追記する。`mix review` 実行時に SQLite の `database is locked` / `database busy` が出たら、その**ファイルだけ** `async: false` に下げる（メモリの記録どおり）。
- **FK 違反は raise**: 手帳は `cast_assoc` 経由で必ず正しい親に紐づくため直接の FK テストは不要。`get_service_user!/1` の未存在 ID は `Ecto.NoResultsError` を raise（既存方針）。
- **ユーザー向け文字列は日本語、コード識別子は英語**（CLAUDE.md）。ラベルの集約先は enum モジュール。フォーム項目ラベルは既存 LiveView と同じくテンプレート内のインライン日本語リテラルで揃える。
- **最小差分・1 機能ずつ**。各タスク完了時に「変更したファイル/関数」を報告する。

---

## File Structure

新規作成:
- `lib/ayumi/plans/gender.ex` — 性別の列挙（`male`/`female`/`other`）。
- `lib/ayumi/plans/support_category.ex` — 障害支援区分（`not_applicable`/`category_1..6`）。
- `lib/ayumi/plans/certificate_kind.ex` — 手帳種類（`physical`/`intellectual`/`mental`）。
- `lib/ayumi/plans/disability_certificate.ex` — 障害者手帳スキーマ（1 対多の子）。
- `priv/repo/migrations/20260614010000_add_basic_info_to_service_users.exs` — `service_user` のフラット項目追加。
- `priv/repo/migrations/20260614010100_create_disability_certificates.exs` — 手帳テーブル。
- `lib/ayumi_web/live/service_user_live/form.ex` — 新規登録/編集フォーム（`:new`/`:edit`）。
- `test/ayumi/plans/enumerations_test.exs` — 3 列挙モジュールのテスト。
- `test/ayumi/plans/disability_certificate_test.exs` — 手帳 changeset のテスト。

変更:
- `lib/ayumi/plans/service_user.ex` — フラット項目・`has_many`・`cast_assoc`・`age/2`。
- `lib/ayumi/plans.ex` — `update_service_user/2`、`get_service_user!/1` preload、`create_service_user/1` の空手帳除去、`drop_blank_certificates/1`。
- `lib/ayumi_web/live/service_user_live/index.ex` — インラインフォーム撤去・「新規登録」ボタン・受給者証番号列。
- `lib/ayumi_web/live/service_user_live/show.ex` — 基本情報グループ表示・手帳一覧・「編集」ボタン。
- `lib/ayumi_web/router.ex` — `:new`/`:edit` ルート追加（順序に注意）。
- `test/support/fixtures/plans_fixtures.ex` — 手帳付き利用者フィクスチャ。
- `test/ayumi/plans/service_user_test.exs` — changeset/age の追加テスト。
- `test/ayumi/plans_test.exs` — コンテキストの追加テスト。
- `test/ayumi_web/live/service_user_live_test.exs` — 画面フローの更新/追加テスト。

---

## Task 1: 列挙モジュール（Gender / SupportCategory / CertificateKind）

各モジュールは「値→日本語ラベル」を 1 つの順序付きキーワードリストに持ち、`all/0`・`label/1`・`options/0` を提供する。`label/1` は表示用なので未知値・`nil` には `nil` を返す（`Keyword.get`）。

**Files:**
- Create: `lib/ayumi/plans/gender.ex`
- Create: `lib/ayumi/plans/support_category.ex`
- Create: `lib/ayumi/plans/certificate_kind.ex`
- Test: `test/ayumi/plans/enumerations_test.exs`

- [x] **Step 1: 失敗するテストを書く**

`test/ayumi/plans/enumerations_test.exs`:

```elixir
defmodule Ayumi.Plans.EnumerationsTest do
  use ExUnit.Case, async: true

  alias Ayumi.Plans.{CertificateKind, Gender, SupportCategory}

  describe "Gender" do
    test "all/0 lists values in display order" do
      assert Gender.all() == [:male, :female, :other]
    end

    test "label/1 returns the Japanese label" do
      assert Gender.label(:male) == "男性"
      assert Gender.label(:other) == "その他"
    end

    test "label/1 returns nil for unknown or nil" do
      assert Gender.label(nil) == nil
      assert Gender.label(:bogus) == nil
    end

    test "options/0 returns {label, value} pairs for selects" do
      assert {"男性", :male} in Gender.options()
      assert length(Gender.options()) == 3
    end
  end

  describe "SupportCategory" do
    test "all/0 covers not_applicable and category_1..6" do
      assert SupportCategory.all() ==
               [:not_applicable, :category_1, :category_2, :category_3, :category_4, :category_5, :category_6]
    end

    test "label/1 maps values to Japanese" do
      assert SupportCategory.label(:not_applicable) == "非該当"
      assert SupportCategory.label(:category_3) == "区分3"
    end
  end

  describe "CertificateKind" do
    test "all/0 lists the three certificate kinds" do
      assert CertificateKind.all() == [:physical, :intellectual, :mental]
    end

    test "label/1 maps values to Japanese" do
      assert CertificateKind.label(:physical) == "身体障害者手帳"
      assert CertificateKind.label(:intellectual) == "療育手帳"
      assert CertificateKind.label(:mental) == "精神障害者保健福祉手帳"
    end
  end
end
```

- [x] **Step 2: テストが失敗することを確認**

Run: `mix test test/ayumi/plans/enumerations_test.exs`
Expected: FAIL（`Ayumi.Plans.Gender` is undefined など）

- [x] **Step 3: 3 モジュールを実装**

`lib/ayumi/plans/gender.ex`:

```elixir
defmodule Ayumi.Plans.Gender do
  @moduledoc "Gender enumeration for a service user. Labels live here, not in views."

  @labels [male: "男性", female: "女性", other: "その他"]

  @doc "All values, in display order."
  def all, do: Keyword.keys(@labels)

  @doc "Japanese label for a value; nil for unknown/nil."
  def label(value), do: Keyword.get(@labels, value)

  @doc "`[{label, value}]` pairs for `<.input type=\"select\">`."
  def options, do: Enum.map(@labels, fn {value, label} -> {label, value} end)
end
```

`lib/ayumi/plans/support_category.ex`:

```elixir
defmodule Ayumi.Plans.SupportCategory do
  @moduledoc "Disability support category (障害支援区分) enumeration. Labels live here."

  @labels [
    not_applicable: "非該当",
    category_1: "区分1",
    category_2: "区分2",
    category_3: "区分3",
    category_4: "区分4",
    category_5: "区分5",
    category_6: "区分6"
  ]

  @doc "All values, in display order."
  def all, do: Keyword.keys(@labels)

  @doc "Japanese label for a value; nil for unknown/nil."
  def label(value), do: Keyword.get(@labels, value)

  @doc "`[{label, value}]` pairs for `<.input type=\"select\">`."
  def options, do: Enum.map(@labels, fn {value, label} -> {label, value} end)
end
```

`lib/ayumi/plans/certificate_kind.ex`:

```elixir
defmodule Ayumi.Plans.CertificateKind do
  @moduledoc "Disability certificate (障害者手帳) kind enumeration. Labels live here."

  @labels [
    physical: "身体障害者手帳",
    intellectual: "療育手帳",
    mental: "精神障害者保健福祉手帳"
  ]

  @doc "All values, in display order."
  def all, do: Keyword.keys(@labels)

  @doc "Japanese label for a value; nil for unknown/nil."
  def label(value), do: Keyword.get(@labels, value)

  @doc "`[{label, value}]` pairs for `<.input type=\"select\">`."
  def options, do: Enum.map(@labels, fn {value, label} -> {label, value} end)
end
```

- [x] **Step 4: テストが通ることを確認**

Run: `mix test test/ayumi/plans/enumerations_test.exs`
Expected: PASS

- [x] **Step 5: コミット**

```bash
git add lib/ayumi/plans/gender.ex lib/ayumi/plans/support_category.ex \
        lib/ayumi/plans/certificate_kind.ex test/ayumi/plans/enumerations_test.exs
git commit -m "feat: add Gender/SupportCategory/CertificateKind enum modules"
```

---

## Task 2: `service_user` のフラット項目・age/2

`service_user` に基本情報のフラット列をすべて任意で追加し、`changeset` の cast を拡張、表示用の純関数 `age/2` を加える。手帳の `has_many`/`cast_assoc` は Task 3 で追加するため、ここでは触れない。

**Files:**
- Create: `priv/repo/migrations/20260614010000_add_basic_info_to_service_users.exs`
- Modify: `lib/ayumi/plans/service_user.ex`
- Test: `test/ayumi/plans/service_user_test.exs`（既存に追記）

- [x] **Step 1: 失敗するテストを書く（changeset 拡張・enum・age）**

`test/ayumi/plans/service_user_test.exs` を次の内容に**置き換える**:

```elixir
defmodule Ayumi.Plans.ServiceUserTest do
  use Ayumi.DataCase, async: true

  alias Ayumi.Plans.ServiceUser

  @full_attrs %{
    name: "山田 太郎",
    name_kana: "やまだ たろう",
    birthdate: ~D[1990-05-20],
    gender: :male,
    postal_code: "100-0001",
    address: "東京都千代田区1-1",
    phone: "03-0000-0000",
    emergency_contact_name: "山田 花子",
    emergency_contact_relation: "母",
    emergency_contact_phone: "090-0000-0000",
    recipient_cert_number: "R-12345",
    recipient_cert_municipality: "千代田区",
    disability_support_category: :category_3,
    benefit_amount: "週5日",
    recipient_cert_expiry: ~D[2027-03-31],
    clinic_name: "千代田クリニック",
    attending_physician: "田中 医師",
    medication_notes: "毎朝1錠",
    consultation_office: "ちよだ相談支援",
    consultation_staff: "鈴木 相談員",
    notes: "備考テキスト"
  }

  test "requires name" do
    changeset = ServiceUser.changeset(%ServiceUser{}, %{})
    refute changeset.valid?
    assert %{name: ["can't be blank"]} = errors_on(changeset)
  end

  test "name_kana is optional" do
    changeset = ServiceUser.changeset(%ServiceUser{}, %{name: "山田 太郎"})
    assert changeset.valid?
  end

  test "accepts a full set of basic-info attributes" do
    changeset = ServiceUser.changeset(%ServiceUser{}, @full_attrs)
    assert changeset.valid?
    assert get_change(changeset, :gender) == :male
    assert get_change(changeset, :disability_support_category) == :category_3
  end

  test "rejects an invalid gender" do
    changeset = ServiceUser.changeset(%ServiceUser{}, %{name: "山田", gender: "bogus"})
    refute changeset.valid?
    assert %{gender: ["is invalid"]} = errors_on(changeset)
  end

  describe "age/2" do
    test "returns nil when birthdate is nil" do
      assert ServiceUser.age(%ServiceUser{birthdate: nil}, ~D[2026-06-14]) == nil
    end

    test "counts a birthday that already passed this year" do
      su = %ServiceUser{birthdate: ~D[1990-05-20]}
      assert ServiceUser.age(su, ~D[2026-06-14]) == 36
    end

    test "does not count a birthday that has not arrived yet" do
      su = %ServiceUser{birthdate: ~D[1990-07-20]}
      assert ServiceUser.age(su, ~D[2026-06-14]) == 35
    end

    test "counts the birthday itself" do
      su = %ServiceUser{birthdate: ~D[1990-06-14]}
      assert ServiceUser.age(su, ~D[2026-06-14]) == 36
    end
  end
end
```

- [x] **Step 2: テストが失敗することを確認**

Run: `mix test test/ayumi/plans/service_user_test.exs`
Expected: FAIL（`age/2` 未定義・新フィールドが cast されず full attrs が無効など）

- [x] **Step 3: マイグレーションを作成**

`priv/repo/migrations/20260614010000_add_basic_info_to_service_users.exs`:

```elixir
defmodule Ayumi.Repo.Migrations.AddBasicInfoToServiceUsers do
  use Ecto.Migration

  def change do
    alter table(:service_users) do
      add :birthdate, :date
      add :gender, :string
      add :postal_code, :string
      add :address, :string
      add :phone, :string
      add :emergency_contact_name, :string
      add :emergency_contact_relation, :string
      add :emergency_contact_phone, :string
      add :recipient_cert_number, :string
      add :recipient_cert_municipality, :string
      add :disability_support_category, :string
      add :benefit_amount, :string
      add :recipient_cert_expiry, :date
      add :clinic_name, :string
      add :attending_physician, :string
      add :medication_notes, :text
      add :consultation_office, :string
      add :consultation_staff, :string
      add :notes, :text
    end
  end
end
```

- [x] **Step 4: スキーマ・changeset・age を実装**

`lib/ayumi/plans/service_user.ex` を次の内容に**置き換える**（手帳の `has_many`/`cast_assoc` は Task 3 で足すのでまだ書かない）:

```elixir
defmodule Ayumi.Plans.ServiceUser do
  @moduledoc "A service user (利用者) with editable basic info, tracked across support plans."
  use Ecto.Schema
  import Ecto.Changeset

  alias Ayumi.Plans.{Gender, SupportCategory}

  @flat_fields [
    :name,
    :name_kana,
    :birthdate,
    :gender,
    :postal_code,
    :address,
    :phone,
    :emergency_contact_name,
    :emergency_contact_relation,
    :emergency_contact_phone,
    :recipient_cert_number,
    :recipient_cert_municipality,
    :disability_support_category,
    :benefit_amount,
    :recipient_cert_expiry,
    :clinic_name,
    :attending_physician,
    :medication_notes,
    :consultation_office,
    :consultation_staff,
    :notes
  ]

  schema "service_users" do
    field :name, :string
    field :name_kana, :string
    field :birthdate, :date
    field :gender, Ecto.Enum, values: Gender.all()
    field :postal_code, :string
    field :address, :string
    field :phone, :string
    field :emergency_contact_name, :string
    field :emergency_contact_relation, :string
    field :emergency_contact_phone, :string
    field :recipient_cert_number, :string
    field :recipient_cert_municipality, :string
    field :disability_support_category, Ecto.Enum, values: SupportCategory.all()
    field :benefit_amount, :string
    field :recipient_cert_expiry, :date
    field :clinic_name, :string
    field :attending_physician, :string
    field :medication_notes, :string
    field :consultation_office, :string
    field :consultation_staff, :string
    field :notes, :string

    has_many :support_plans, Ayumi.Plans.SupportPlan

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(service_user, attrs) do
    service_user
    |> cast(attrs, @flat_fields)
    |> validate_required([:name])
  end

  @doc """
  Age in whole years on `today`, derived from `birthdate`. Display-only; never
  stored. Returns nil when no birthdate is set.
  """
  def age(%__MODULE__{birthdate: nil}, %Date{}), do: nil

  def age(%__MODULE__{birthdate: %Date{} = birthdate}, %Date{} = today) do
    years = today.year - birthdate.year

    if {today.month, today.day} < {birthdate.month, birthdate.day} do
      years - 1
    else
      years
    end
  end
end
```

- [x] **Step 5: マイグレーション + テストが通ることを確認**

Run: `mix test test/ayumi/plans/service_user_test.exs`
Expected: PASS（`mix test` エイリアスが `ecto.create --quiet` → `ecto.migrate --quiet` を先に実行する）

- [x] **Step 6: コミット**

```bash
git add priv/repo/migrations/20260614010000_add_basic_info_to_service_users.exs \
        lib/ayumi/plans/service_user.ex test/ayumi/plans/service_user_test.exs
git commit -m "feat: add basic-info fields and age/2 to service_user"
```

---

## Task 3: `disability_certificate` スキーマ・cast_assoc・空手帳除去

手帳テーブルとスキーマを作り、`ServiceUser` に `has_many ... on_replace: :delete` と `cast_assoc` を足す。空の手帳行を除去する純関数 `Plans.drop_blank_certificates/1` を定義（この時点では create/update への配線はしない＝関数を直接テスト）。

**Files:**
- Create: `priv/repo/migrations/20260614010100_create_disability_certificates.exs`
- Create: `lib/ayumi/plans/disability_certificate.ex`
- Modify: `lib/ayumi/plans/service_user.ex`（`has_many` + `cast_assoc`）
- Modify: `lib/ayumi/plans.ex`（`drop_blank_certificates/1`）
- Test: `test/ayumi/plans/disability_certificate_test.exs`
- Test: `test/ayumi/plans/service_user_test.exs`（cast_assoc の 1 行追加）
- Test: `test/ayumi/plans_test.exs`（`drop_blank_certificates/1` の純テスト）

- [x] **Step 1: 手帳 changeset の失敗テストを書く**

`test/ayumi/plans/disability_certificate_test.exs`:

```elixir
defmodule Ayumi.Plans.DisabilityCertificateTest do
  use ExUnit.Case, async: true

  alias Ayumi.Plans.DisabilityCertificate, as: Cert

  test "requires kind" do
    changeset = Cert.changeset(%Cert{}, %{number: "B-1"})
    refute changeset.valid?
    assert {"can't be blank", _} = changeset.errors[:kind]
  end

  test "kind only is valid; other fields are optional" do
    changeset = Cert.changeset(%Cert{}, %{kind: :physical})
    assert changeset.valid?
  end

  test "rejects an invalid kind" do
    changeset = Cert.changeset(%Cert{}, %{kind: :bogus})
    refute changeset.valid?
  end
end
```

- [x] **Step 2: cast_assoc / drop_blank の失敗テストを書く**

`test/ayumi/plans/service_user_test.exs` の末尾（`end` の直前、最後の `describe` の後）に追記:

```elixir
  test "casts a nested disability certificate" do
    attrs = %{
      name: "山田 太郎",
      disability_certificates: [%{kind: :physical, number: "B-1", grade: "2級"}]
    }

    changeset = ServiceUser.changeset(%ServiceUser{}, attrs)
    assert changeset.valid?
    assert [cert_cs] = get_change(changeset, :disability_certificates)
    assert get_change(cert_cs, :kind) == :physical
  end
```

`test/ayumi/plans_test.exs` の `describe "service users" do ... end` の中に追記:

```elixir
    test "drop_blank_certificates/1 removes an all-blank certificate row" do
      attrs = %{
        "name" => "山田",
        "disability_certificates" => %{
          "0" => %{"kind" => "", "number" => "", "disability_name" => "", "grade" => ""}
        }
      }

      assert %{"disability_certificates" => certs} = Plans.drop_blank_certificates(attrs)
      assert certs == %{}
    end

    test "drop_blank_certificates/1 keeps a row that has any content" do
      attrs = %{
        "name" => "山田",
        "disability_certificates" => %{
          "0" => %{"kind" => "physical", "number" => "", "disability_name" => "", "grade" => ""}
        }
      }

      assert %{"disability_certificates" => %{"0" => kept}} = Plans.drop_blank_certificates(attrs)
      assert kept["kind"] == "physical"
    end

    test "drop_blank_certificates/1 passes through attrs without the key" do
      attrs = %{"name" => "山田"}
      assert Plans.drop_blank_certificates(attrs) == attrs
    end
```

- [x] **Step 3: テストが失敗することを確認**

Run: `mix test test/ayumi/plans/disability_certificate_test.exs test/ayumi/plans/service_user_test.exs test/ayumi/plans_test.exs`
Expected: FAIL（`DisabilityCertificate` 未定義・`drop_blank_certificates/1` 未定義・`cast_assoc` 未設定）

- [x] **Step 4: マイグレーションを作成**

`priv/repo/migrations/20260614010100_create_disability_certificates.exs`:

```elixir
defmodule Ayumi.Repo.Migrations.CreateDisabilityCertificates do
  use Ecto.Migration

  def change do
    create table(:disability_certificates) do
      add :service_user_id, references(:service_users, on_delete: :delete_all), null: false
      add :kind, :string, null: false
      add :number, :string
      add :disability_name, :string
      add :grade, :string

      timestamps(type: :utc_datetime)
    end

    create index(:disability_certificates, [:service_user_id])
  end
end
```

- [x] **Step 5: 手帳スキーマを実装**

`lib/ayumi/plans/disability_certificate.ex`:

```elixir
defmodule Ayumi.Plans.DisabilityCertificate do
  @moduledoc "A disability certificate (障害者手帳) belonging to a service user."
  use Ecto.Schema
  import Ecto.Changeset

  alias Ayumi.Plans.CertificateKind

  schema "disability_certificates" do
    field :kind, Ecto.Enum, values: CertificateKind.all()
    field :number, :string
    field :disability_name, :string
    field :grade, :string

    belongs_to :service_user, Ayumi.Plans.ServiceUser

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(certificate, attrs) do
    certificate
    |> cast(attrs, [:kind, :number, :disability_name, :grade])
    |> validate_required([:kind])
  end
end
```

- [x] **Step 6: `ServiceUser` に has_many + cast_assoc を追加**

`lib/ayumi/plans/service_user.ex` の `has_many :support_plans, ...` の直後に手帳の関連を追加:

```elixir
    has_many :support_plans, Ayumi.Plans.SupportPlan

    has_many :disability_certificates, Ayumi.Plans.DisabilityCertificate,
      on_replace: :delete
```

同ファイルの `changeset/2` に `cast_assoc` を追加:

```elixir
  @doc false
  def changeset(service_user, attrs) do
    service_user
    |> cast(attrs, @flat_fields)
    |> validate_required([:name])
    |> cast_assoc(:disability_certificates,
      with: &Ayumi.Plans.DisabilityCertificate.changeset/2
    )
  end
```

- [x] **Step 7: `Plans.drop_blank_certificates/1` を実装**

`lib/ayumi/plans.ex` の `## Service users` セクション（`change_service_user/2` の後）に追記:

```elixir
  @doc """
  Removes all-blank disability-certificate rows from form params so an untouched
  certificate row is never persisted. A row is blank when every content field
  (`kind`/`number`/`disability_name`/`grade`) is empty. The key is kept (possibly
  as an empty map) so `cast_assoc` still runs and deletes unmatched existing rows
  on update. Pure and string-keyed (the form path); atom-keyed params pass through
  unchanged. Safe to unit-test.
  """
  def drop_blank_certificates(attrs) when is_map(attrs) do
    case Map.pop(attrs, "disability_certificates") do
      {certs, rest} when is_map(certs) ->
        kept =
          certs
          |> Enum.reject(fn {_index, cert} -> blank_certificate?(cert) end)
          |> Map.new()

        Map.put(rest, "disability_certificates", kept)

      {_other, _rest} ->
        attrs
    end
  end

  defp blank_certificate?(cert) when is_map(cert) do
    ~w(kind number disability_name grade)
    |> Enum.all?(fn key -> blank_value?(Map.get(cert, key)) end)
  end

  defp blank_certificate?(_), do: false

  defp blank_value?(nil), do: true
  defp blank_value?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank_value?(_), do: false
```

- [x] **Step 8: テストが通ることを確認**

Run: `mix test test/ayumi/plans/disability_certificate_test.exs test/ayumi/plans/service_user_test.exs test/ayumi/plans_test.exs`
Expected: PASS

- [x] **Step 9: コミット**

```bash
git add priv/repo/migrations/20260614010100_create_disability_certificates.exs \
        lib/ayumi/plans/disability_certificate.ex lib/ayumi/plans/service_user.ex \
        lib/ayumi/plans.ex test/ayumi/plans/disability_certificate_test.exs \
        test/ayumi/plans/service_user_test.exs test/ayumi/plans_test.exs
git commit -m "feat: add disability_certificate schema, cast_assoc, blank-row pruning"
```

---

## Task 4: コンテキスト配線（create 除去・update 新設・preload）

`create_service_user/1` で空手帳を除去、`update_service_user/2` を新設（`on_replace: :delete` で手帳の更新/削除に対応）、`get_service_user!/1` で手帳を preload。手帳付き利用者のフィクスチャを追加。

**Files:**
- Modify: `lib/ayumi/plans.ex`
- Modify: `test/support/fixtures/plans_fixtures.ex`
- Test: `test/ayumi/plans_test.exs`

- [x] **Step 1: 失敗するコンテキストテストを書く**

`test/ayumi/plans_test.exs` の `describe "service users" do ... end` の中に追記:

```elixir
    test "create_service_user/1 persists a nested certificate" do
      assert {:ok, su} =
               Plans.create_service_user(%{
                 name: "手帳 太郎",
                 disability_certificates: [%{kind: :physical, number: "B-1", grade: "2級"}]
               })

      su = Plans.get_service_user!(su.id)
      assert [%Ayumi.Plans.DisabilityCertificate{kind: :physical, number: "B-1"}] =
               su.disability_certificates
    end

    test "create_service_user/1 drops an all-blank certificate row" do
      attrs = %{
        "name" => "空手帳 太郎",
        "disability_certificates" => %{
          "0" => %{"kind" => "", "number" => "", "disability_name" => "", "grade" => ""}
        }
      }

      assert {:ok, su} = Plans.create_service_user(attrs)
      assert Plans.get_service_user!(su.id).disability_certificates == []
    end

    test "get_service_user!/1 preloads disability_certificates" do
      su = service_user_with_certificate_fixture()
      loaded = Plans.get_service_user!(su.id)
      assert [%Ayumi.Plans.DisabilityCertificate{}] = loaded.disability_certificates
    end

    test "update_service_user/2 changes flat fields" do
      su = service_user_fixture()
      assert {:ok, updated} = Plans.update_service_user(su, %{phone: "03-1111-2222"})
      assert updated.phone == "03-1111-2222"
    end

    test "update_service_user/2 updates an existing certificate" do
      su = service_user_with_certificate_fixture()
      su = Plans.get_service_user!(su.id)
      [cert] = su.disability_certificates

      params = %{
        "disability_certificates" => %{
          "0" => %{"id" => to_string(cert.id), "kind" => "physical", "grade" => "1級"}
        }
      }

      assert {:ok, _} = Plans.update_service_user(su, params)
      assert [%{grade: "1級"}] = Plans.get_service_user!(su.id).disability_certificates
    end

    test "update_service_user/2 deletes a certificate when its row is blanked" do
      su = service_user_with_certificate_fixture()
      su = Plans.get_service_user!(su.id)
      [cert] = su.disability_certificates

      params = %{
        "disability_certificates" => %{
          "0" => %{"id" => to_string(cert.id), "kind" => "", "number" => "", "disability_name" => "", "grade" => ""}
        }
      }

      assert {:ok, _} = Plans.update_service_user(su, params)
      assert Plans.get_service_user!(su.id).disability_certificates == []
    end
```

- [x] **Step 2: フィクスチャを追加**

`test/support/fixtures/plans_fixtures.ex` の `service_user_fixture/1` の直後に追記:

```elixir
  def service_user_with_certificate_fixture(attrs \\ %{}) do
    {:ok, service_user} =
      %{
        name: "手帳 太郎",
        name_kana: "てちょう たろう",
        disability_certificates: [%{kind: :physical, number: "B-123", grade: "2級"}]
      }
      |> Map.merge(Map.new(attrs))
      |> Plans.create_service_user()

    service_user
  end
```

- [x] **Step 3: テストが失敗することを確認**

Run: `mix test test/ayumi/plans_test.exs`
Expected: FAIL（`update_service_user/2` 未定義・`get_service_user!` が手帳を preload しない・create が空手帳を除去しない）

- [x] **Step 4: コンテキストを実装**

`lib/ayumi/plans.ex` の該当 3 関数を**置き換える**:

```elixir
  @doc "Gets a single service user with certificates preloaded. Raises if not found."
  def get_service_user!(id) do
    ServiceUser
    |> preload(:disability_certificates)
    |> Repo.get!(id)
  end

  @doc "Creates a service user. Blank certificate rows are dropped before insert."
  def create_service_user(attrs) do
    %ServiceUser{}
    |> ServiceUser.changeset(drop_blank_certificates(attrs))
    |> Repo.insert()
  end

  @doc """
  Updates a service user's basic info and certificates. The struct must have
  `:disability_certificates` preloaded so `on_replace: :delete` can delete rows
  that were blanked out. Blank certificate rows are dropped before update.
  """
  def update_service_user(%ServiceUser{} = service_user, attrs) do
    service_user
    |> ServiceUser.changeset(drop_blank_certificates(attrs))
    |> Repo.update()
  end
```

> 注: `drop_blank_certificates/1` は文字列キーの `"disability_certificates"` だけを処理する。フィクスチャ/テストのアトムキー（`:disability_certificates`）はそのまま通過し、実体のある手帳として保存される（意図どおり）。

- [x] **Step 5: テストが通ることを確認**

Run: `mix test test/ayumi/plans_test.exs`
Expected: PASS

- [x] **Step 6: コミット**

```bash
git add lib/ayumi/plans.ex test/support/fixtures/plans_fixtures.ex test/ayumi/plans_test.exs
git commit -m "feat: wire create/update_service_user and certificate preload"
```

---

## Task 5: ルート + 一覧（Index）の改修

一覧のインライン作成フォームを撤去し「新規登録」ボタン（`/service_users/new` へ navigate）と受給者証番号列を足す。ルートに `:new`/`:edit` を追加（`/new` を `/:id` より前に置く）。

**Files:**
- Modify: `lib/ayumi_web/router.ex`
- Modify: `lib/ayumi_web/live/service_user_live/index.ex`
- Test: `test/ayumi_web/live/service_user_live_test.exs`

- [x] **Step 1: 既存テストを新フローへ書き換える**

`test/ayumi_web/live/service_user_live_test.exs` の `test "creates a service user", ...` ブロックを**次に置き換える**（インラインフォームは無くなるため、導線テストにする）:

```elixir
  test "shows a 新規登録 link to the new form", %{conn: conn} do
    {:ok, lv, html} = live(conn, ~p"/service_users")
    refute has_element?(lv, "#service-user-form")
    assert html =~ "新規登録"

    {:ok, _form_lv, form_html} =
      lv |> element("a", "新規登録") |> render_click() |> follow_redirect(conn)

    assert form_html =~ "利用者の新規登録"
  end
```

- [x] **Step 2: テストが失敗することを確認**

Run: `mix test test/ayumi_web/live/service_user_live_test.exs:15`
Expected: FAIL（`/service_users/new` ルート未定義・`新規登録` リンク無し）

- [x] **Step 3: ルートを追加**

`lib/ayumi_web/router.ex` の `live "/service_users", ...` ブロックを**次の順序に置き換える**（`/new` と `/:id/edit` を `/:id` より前に）:

```elixir
      live "/service_users", ServiceUserLive.Index, :index
      live "/service_users/new", ServiceUserLive.Form, :new
      live "/service_users/:id/edit", ServiceUserLive.Form, :edit
      live "/service_users/:id", ServiceUserLive.Show, :show
      live "/service_users/:service_user_id/support_plans/new", SupportPlanLive.Form, :new
      live "/support_plans/:id", SupportPlanLive.Show, :show
```

- [x] **Step 4: Index LiveView を改修**

`lib/ayumi_web/live/service_user_live/index.ex` を次の内容に**置き換える**:

```elixir
defmodule AyumiWeb.ServiceUserLive.Index do
  use AyumiWeb, :live_view

  alias Ayumi.Plans

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "利用者一覧")
     |> assign(:service_users, Plans.list_service_users())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        利用者一覧
        <:actions>
          <.button navigate={~p"/service_users/new"}>新規登録</.button>
        </:actions>
      </.header>

      <.table id="service-users" rows={@service_users}>
        <:col :let={su} label="氏名">
          <.link navigate={~p"/service_users/#{su.id}"}>{su.name}</.link>
        </:col>
        <:col :let={su} label="ふりがな">{su.name_kana}</:col>
        <:col :let={su} label="受給者証番号">{su.recipient_cert_number}</:col>
      </.table>
    </Layouts.app>
    """
  end
end
```

> Task 6 で `ServiceUserLive.Form` を作るまでルートはコンパイルエラーになる。Task 5 のテストは Task 6 完了後にまとめて緑にしてよい（または先に Task 6 を実装してから Step 5 を実行する）。コミットは Form 実装後の Task 6 末でまとめて行う。

- [x] **Step 5（Task 6 完了後に実行）: テスト確認 → コミット**は Task 6 の末尾でまとめて行う。

---

## Task 6: 新規登録/編集フォーム（`ServiceUserLive.Form`）

`:new`/`:edit` を `live_action` で分岐する単一フォーム。セクション分け（基本/連絡先/受給者証/手帳/医療/その他）。手帳は `inputs_for` で 1 行。0 件のときは空 1 行を用意（LiveView の責務）。保存成功で詳細へ `push_navigate`。

**Files:**
- Create: `lib/ayumi_web/live/service_user_live/form.ex`
- Test: `test/ayumi_web/live/service_user_live_test.exs`

- [x] **Step 1: フォームの失敗テストを書く**

`test/ayumi_web/live/service_user_live_test.exs` の末尾（最後の `end` の前）に追記:

```elixir
  test "creates a service user with a certificate via the new form", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/service_users/new")

    params = %{
      "name" => "新規 太郎",
      "name_kana" => "しんき たろう",
      "disability_certificates" => %{
        "0" => %{"kind" => "physical", "number" => "B-9", "grade" => "2級"}
      }
    }

    {:ok, _show_lv, html} =
      lv
      |> form("#service-user-form", service_user: params)
      |> render_submit()
      |> follow_redirect(conn)

    assert html =~ "新規 太郎"
    assert html =~ "B-9"
  end

  test "edits a service user via the edit form", %{conn: conn} do
    su = service_user_fixture(%{name: "編集前"})
    {:ok, lv, _html} = live(conn, ~p"/service_users/#{su.id}/edit")

    {:ok, _show_lv, html} =
      lv
      |> form("#service-user-form", service_user: %{"name" => "編集後", "phone" => "03-9999-0000"})
      |> render_submit()
      |> follow_redirect(conn)

    assert html =~ "編集後"
    assert html =~ "03-9999-0000"
  end
```

- [x] **Step 2: テストが失敗することを確認**

Run: `mix test test/ayumi_web/live/service_user_live_test.exs`
Expected: FAIL（`ServiceUserLive.Form` 未定義）

- [x] **Step 3: フォーム LiveView を実装**

`lib/ayumi_web/live/service_user_live/form.ex`:

```elixir
defmodule AyumiWeb.ServiceUserLive.Form do
  use AyumiWeb, :live_view

  alias Ayumi.Plans
  alias Ayumi.Plans.{CertificateKind, DisabilityCertificate, Gender, ServiceUser, SupportCategory}

  @impl true
  def mount(params, _session, socket) do
    {:ok, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    service_user = %ServiceUser{disability_certificates: [%DisabilityCertificate{}]}

    socket
    |> assign(:page_title, "利用者の新規登録")
    |> assign(:service_user, service_user)
    |> assign_form(Plans.change_service_user(service_user))
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    service_user = id |> Plans.get_service_user!() |> ensure_one_certificate()

    socket
    |> assign(:page_title, "利用者の編集")
    |> assign(:service_user, service_user)
    |> assign_form(Plans.change_service_user(service_user))
  end

  defp ensure_one_certificate(%ServiceUser{disability_certificates: []} = service_user),
    do: %{service_user | disability_certificates: [%DisabilityCertificate{}]}

  defp ensure_one_certificate(%ServiceUser{} = service_user), do: service_user

  @impl true
  def handle_event("validate", %{"service_user" => params}, socket) do
    changeset =
      socket.assigns.service_user
      |> Plans.change_service_user(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  @impl true
  def handle_event("save", %{"service_user" => params}, socket) do
    save_service_user(socket, socket.assigns.live_action, params)
  end

  defp save_service_user(socket, :new, params) do
    case Plans.create_service_user(params) do
      {:ok, service_user} ->
        {:noreply,
         socket
         |> put_flash(:info, "利用者を登録しました")
         |> push_navigate(to: ~p"/service_users/#{service_user.id}")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp save_service_user(socket, :edit, params) do
    case Plans.update_service_user(socket.assigns.service_user, params) do
      {:ok, service_user} ->
        {:noreply,
         socket
         |> put_flash(:info, "利用者情報を更新しました")
         |> push_navigate(to: ~p"/service_users/#{service_user.id}")}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, changeset), do: assign(socket, :form, to_form(changeset))

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>{@page_title}</.header>

      <.form for={@form} id="service-user-form" phx-change="validate" phx-submit="save">
        <section class="my-6">
          <h2 class="text-lg font-semibold mb-2">基本</h2>
          <.input field={@form[:name]} type="text" label="氏名" />
          <.input field={@form[:name_kana]} type="text" label="ふりがな" />
          <.input field={@form[:birthdate]} type="date" label="生年月日" />
          <.input
            field={@form[:gender]}
            type="select"
            label="性別"
            options={Gender.options()}
            prompt="選択してください"
          />
        </section>

        <section class="my-6">
          <h2 class="text-lg font-semibold mb-2">連絡先</h2>
          <.input field={@form[:postal_code]} type="text" label="郵便番号" />
          <.input field={@form[:address]} type="text" label="住所" />
          <.input field={@form[:phone]} type="text" label="電話番号" />
          <.input field={@form[:emergency_contact_name]} type="text" label="緊急連絡先 氏名" />
          <.input field={@form[:emergency_contact_relation]} type="text" label="続柄" />
          <.input field={@form[:emergency_contact_phone]} type="text" label="緊急連絡先 電話" />
        </section>

        <section class="my-6">
          <h2 class="text-lg font-semibold mb-2">受給者証</h2>
          <.input field={@form[:recipient_cert_number]} type="text" label="受給者証番号" />
          <.input field={@form[:recipient_cert_municipality]} type="text" label="支給市町村" />
          <.input
            field={@form[:disability_support_category]}
            type="select"
            label="障害支援区分"
            options={SupportCategory.options()}
            prompt="選択してください"
          />
          <.input field={@form[:benefit_amount]} type="text" label="支給量" />
          <.input field={@form[:recipient_cert_expiry]} type="date" label="受給者証 有効期限" />
        </section>

        <section class="my-6">
          <h2 class="text-lg font-semibold mb-2">障害者手帳</h2>
          <.inputs_for :let={cert} field={@form[:disability_certificates]}>
            <.input
              field={cert[:kind]}
              type="select"
              label="手帳の種類"
              options={CertificateKind.options()}
              prompt="選択してください"
            />
            <.input field={cert[:number]} type="text" label="手帳番号" />
            <.input field={cert[:disability_name]} type="text" label="障害種類・障害名" />
            <.input field={cert[:grade]} type="text" label="等級" />
          </.inputs_for>
        </section>

        <section class="my-6">
          <h2 class="text-lg font-semibold mb-2">医療</h2>
          <.input field={@form[:clinic_name]} type="text" label="通院先" />
          <.input field={@form[:attending_physician]} type="text" label="主治医" />
          <.input field={@form[:medication_notes]} type="textarea" label="服薬・特記" />
        </section>

        <section class="my-6">
          <h2 class="text-lg font-semibold mb-2">その他</h2>
          <.input field={@form[:consultation_office]} type="text" label="相談支援事業所" />
          <.input field={@form[:consultation_staff]} type="text" label="担当相談員" />
          <.input field={@form[:notes]} type="textarea" label="備考" />
        </section>

        <.button phx-disable-with="保存中...">保存</.button>
      </.form>
    </Layouts.app>
    """
  end
end
```

- [x] **Step 4: フォーム + Index のテストが通ることを確認**

Run: `mix test test/ayumi_web/live/service_user_live_test.exs`
Expected: PASS（Task 5 の導線テストもここで緑になる）

- [x] **Step 5: コミット（Task 5 + Task 6 をまとめて）**

```bash
git add lib/ayumi_web/router.ex lib/ayumi_web/live/service_user_live/index.ex \
        lib/ayumi_web/live/service_user_live/form.ex \
        test/ayumi_web/live/service_user_live_test.exs
git commit -m "feat: add service user new/edit form and route to it from the index"
```

---

## Task 7: 詳細（Show）の改修

詳細画面に基本情報のグループ表示・手帳一覧・「編集」ボタンを足し、既存の計画履歴は残す。`get_service_user!/1` が手帳を preload 済みなのでそれを表示。年齢は `ServiceUser.age/2`、性別・区分・手帳種類はラベルを enum モジュールから引く。

**Files:**
- Modify: `lib/ayumi_web/live/service_user_live/show.ex`
- Test: `test/ayumi_web/live/service_user_live_test.exs`

- [x] **Step 1: 詳細表示の失敗テストを書く**

`test/ayumi_web/live/service_user_live_test.exs` の `test "shows a service user with their support plans", ...` の直後に追記:

```elixir
  test "shows basic info and certificates on the detail page", %{conn: conn} do
    {:ok, su} =
      Ayumi.Plans.create_service_user(%{
        name: "詳細 太郎",
        name_kana: "しょうさい たろう",
        gender: :male,
        phone: "03-1234-5678",
        recipient_cert_number: "R-777",
        disability_certificates: [%{kind: :physical, number: "B-55", grade: "2級"}]
      })

    {:ok, _lv, html} = live(conn, ~p"/service_users/#{su.id}")

    assert html =~ "詳細 太郎"
    assert html =~ "男性"
    assert html =~ "03-1234-5678"
    assert html =~ "R-777"
    assert html =~ "身体障害者手帳"
    assert html =~ "B-55"
    assert html =~ "編集"
  end
```

- [x] **Step 2: テストが失敗することを確認**

Run: `mix test test/ayumi_web/live/service_user_live_test.exs`
Expected: FAIL（基本情報/手帳/編集ボタンが未表示）

- [x] **Step 3: Show LiveView を改修**

`lib/ayumi_web/live/service_user_live/show.ex` を次の内容に**置き換える**:

```elixir
defmodule AyumiWeb.ServiceUserLive.Show do
  use AyumiWeb, :live_view

  alias Ayumi.Accounts.User
  alias Ayumi.Plans
  alias Ayumi.Plans.{CertificateKind, Gender, ServiceUser, SupportCategory}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    service_user = Plans.get_service_user!(id)

    {:ok,
     socket
     |> assign(:page_title, service_user.name)
     |> assign(:service_user, service_user)
     |> assign(:today, Date.utc_today())
     |> assign(:support_plans, Plans.list_support_plans_for_user(service_user))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {@service_user.name}
        <:subtitle>{@service_user.name_kana}</:subtitle>
        <:actions>
          <.button navigate={~p"/service_users/#{@service_user.id}/edit"}>編集</.button>
          <.button navigate={~p"/service_users/#{@service_user.id}/support_plans/new"}>
            支援計画を作成
          </.button>
        </:actions>
      </.header>

      <section class="my-6">
        <h2 class="text-lg font-semibold mb-2">基本</h2>
        <dl>
          <.field_row label="生年月日">{format_birthdate(@service_user, @today)}</.field_row>
          <.field_row label="性別">{Gender.label(@service_user.gender)}</.field_row>
        </dl>
      </section>

      <section class="my-6">
        <h2 class="text-lg font-semibold mb-2">連絡先</h2>
        <dl>
          <.field_row label="郵便番号">{@service_user.postal_code}</.field_row>
          <.field_row label="住所">{@service_user.address}</.field_row>
          <.field_row label="電話番号">{@service_user.phone}</.field_row>
          <.field_row label="緊急連絡先 氏名">{@service_user.emergency_contact_name}</.field_row>
          <.field_row label="続柄">{@service_user.emergency_contact_relation}</.field_row>
          <.field_row label="緊急連絡先 電話">{@service_user.emergency_contact_phone}</.field_row>
        </dl>
      </section>

      <section class="my-6">
        <h2 class="text-lg font-semibold mb-2">受給者証</h2>
        <dl>
          <.field_row label="受給者証番号">{@service_user.recipient_cert_number}</.field_row>
          <.field_row label="支給市町村">{@service_user.recipient_cert_municipality}</.field_row>
          <.field_row label="障害支援区分">
            {SupportCategory.label(@service_user.disability_support_category)}
          </.field_row>
          <.field_row label="支給量">{@service_user.benefit_amount}</.field_row>
          <.field_row label="有効期限">{@service_user.recipient_cert_expiry}</.field_row>
        </dl>
      </section>

      <section class="my-6">
        <h2 class="text-lg font-semibold mb-2">障害者手帳</h2>
        <.table id="disability-certificates" rows={@service_user.disability_certificates}>
          <:col :let={cert} label="種類">{CertificateKind.label(cert.kind)}</:col>
          <:col :let={cert} label="手帳番号">{cert.number}</:col>
          <:col :let={cert} label="障害名">{cert.disability_name}</:col>
          <:col :let={cert} label="等級">{cert.grade}</:col>
        </.table>
      </section>

      <section class="my-6">
        <h2 class="text-lg font-semibold mb-2">医療</h2>
        <dl>
          <.field_row label="通院先">{@service_user.clinic_name}</.field_row>
          <.field_row label="主治医">{@service_user.attending_physician}</.field_row>
          <.field_row label="服薬・特記">{@service_user.medication_notes}</.field_row>
        </dl>
      </section>

      <section class="my-6">
        <h2 class="text-lg font-semibold mb-2">その他</h2>
        <dl>
          <.field_row label="相談支援事業所">{@service_user.consultation_office}</.field_row>
          <.field_row label="担当相談員">{@service_user.consultation_staff}</.field_row>
          <.field_row label="備考">{@service_user.notes}</.field_row>
        </dl>
      </section>

      <section class="my-6">
        <h2 class="text-lg font-semibold mb-2">支援計画</h2>
        <.table id="support-plans" rows={@support_plans}>
          <:col :let={plan} label="計画期間">
            {plan.period_start} 〜 {plan.period_end}
          </:col>
          <:col :let={plan} label="担当者">{User.display_name(plan.staff)}</:col>
          <:col :let={plan} label="長期目標">{plan.long_term_goal}</:col>
          <:col :let={plan} label="次回モニタリング">{plan.next_monitoring_date}</:col>
          <:col :let={plan} label="">
            <.link navigate={~p"/support_plans/#{plan.id}"}>詳細</.link>
          </:col>
        </.table>
      </section>
    </Layouts.app>
    """
  end

  attr :label, :string, required: true
  slot :inner_block, required: true

  defp field_row(assigns) do
    ~H"""
    <div class="flex gap-2 py-1">
      <dt class="w-40 shrink-0 font-medium text-base-content/70">{@label}</dt>
      <dd>{render_slot(@inner_block)}</dd>
    </div>
    """
  end

  defp format_birthdate(%ServiceUser{birthdate: nil}, _today), do: nil

  defp format_birthdate(%ServiceUser{birthdate: birthdate} = service_user, today),
    do: "#{birthdate}（#{ServiceUser.age(service_user, today)}歳）"
end
```

- [x] **Step 4: テストが通ることを確認**

Run: `mix test test/ayumi_web/live/service_user_live_test.exs`
Expected: PASS

- [x] **Step 5: コミット**

```bash
git add lib/ayumi_web/live/service_user_live/show.ex \
        test/ayumi_web/live/service_user_live_test.exs
git commit -m "feat: show basic info, certificates and edit link on detail page"
```

---

## Task 8: 品質ゲート（`mix review`）

全テスト・format・credo・warnings-as-errors を通す。`mix review` 緑で完了。

**Files:** （修正があれば該当ファイル）

- [x] **Step 1: フォーマット**

Run: `mix format`

- [x] **Step 2: `mix review` を実行**

Run: `mix review`
Expected: PASS（`format --check-formatted` / `compile --warnings-as-errors --force` / `credo` / `test` すべて緑）

- [x] **Step 3: 失敗が出たら対処**

- `database is locked` / `database busy`（SQLite）が出た場合: 該当する**DB に触れるテストファイル**（典型的には `test/ayumi/plans_test.exs`）の先頭を `use Ayumi.DataCase, async: false` に下げる（[[sqlite-ecto-gotchas]]）。純粋な changeset/enum/age テストは `async: true` のままでよい。
- credo 指摘（モジュール過大・alias 未使用など）は最小差分で解消する。
- 再度 `mix review` が緑になるまで繰り返す。

- [x] **Step 4: 最終コミット（差分があれば）**

```bash
git add -A
git commit -m "chore: pass mix review for service user basic info"
```

---

## Self-Review（spec 突合チェック結果）

- **スキーマ（spec §1）**: フラット項目 19 列は Task 2 のマイグレーション/スキーマ表と一致。`disability_certificate`（FK `on_delete: :delete_all`・`index`・`validate_required([:kind])`）は Task 3 で実装。✓
- **列挙（spec §2）**: `Gender`/`SupportCategory`/`CertificateKind` を `all/0`・`label/1`・`options/0` 付きで Task 1。等級・障害名等は自由入力（string）。✓
- **手帳 B 案（spec §3）**: `inputs_for` 1 行（Task 6）・`cast_assoc`（Task 3）・空行除去の純関数 `drop_blank_certificates/1`（Task 3 で定義・テスト、Task 4 で配線）・0 件時の空 1 行は LiveView の `ensure_one_certificate`（Task 6）。✓
- **コンテキスト（spec §4）**: `change_service_user`（cast_assoc 込み）・`create_service_user`（空手帳除去）・`update_service_user/2`（新規）・`get_service_user!`（preload）・`ServiceUser.age/2`（純関数）すべてカバー。✓
- **画面（spec §5）**: Index 改修（Task 5）・`ServiceUserLive.Form` の `:new`/`:edit` セクション分け（Task 6）・Show 改修（Task 7）・ルート順序（`/new`→`/:id/edit`→`/:id`）（Task 5）。✓
- **エラー/プライバシー（spec §6）**: 検証は changeset、氏名のみ必須、未存在 ID は raise。暗号化等の追加インフラは導入しない（変更なし）。✓
- **テスト（spec §7）**: 列挙・`ServiceUser` changeset・`DisabilityCertificate` changeset・コンテキスト（create/update/preload/空手帳）・`age/2` 境界・LiveView（新規/編集/一覧導線/詳細表示）すべてに対応タスクあり。✓
- **ビルド順（spec §8）**: Task 1→列挙、2→フラット、3→手帳/cast_assoc/除去、4→コンテキスト、5–7→UI、8→`mix review`。spec の順序と一致（age のみ schema 直近の Task 2 に前倒し配置——純関数で DB 非依存のため安全）。✓
- **非目標（spec §9）**: 手帳複数行 UI・受給者証履歴・緊急連絡先複数・暗号化・`Ayumi.People` 切り出しはいずれも未着手（計画に含めない）。✓

Placeholder/型整合スキャン: `drop_blank_certificates/1`・`ensure_one_certificate/1`・`age/2`・`field_row/1`・enum の `all`/`label`/`options` は定義箇所と参照箇所で名称一致。TODO/TBD なし。
