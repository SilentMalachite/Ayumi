# Web層UI文字列の gettext 化 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Wrap the ~108 scattered Japanese UI string literals in the Web layer (LiveViews + the shared layout) in `gettext(...)`, then extract `priv/gettext/default.pot` — without changing any rendered text.

**Architecture:** Behavior-preserving refactor. `gettext/1` returns the msgid verbatim when there is no translation, and we keep Japanese as the msgid and create no `ja` locale — so every screen renders byte-for-byte the same text. The existing test suite (188) is the safety net: it must stay green **unmodified** at every step, which is precisely what proves the rendering is unchanged. `gettext/1` is already imported into all LiveViews and components via `use Gettext, backend: AyumiWeb.Gettext` in `lib/ayumi_web.ex` (the `:live_view` and `:html` quotes), so no per-file imports are added.

**Tech Stack:** Elixir, Phoenix 1.8 LiveView, Gettext 0.26 (`AyumiWeb.Gettext`).

**Out of scope (per design):** enum label modules (`Gender`/`SupportCategory`/`CertificateKind`), changeset validation messages, `accounts.ex`, and the `mix ayumi.create_user` CLI task — all already centralized or non-UI.

---

## Transformation Rules (apply consistently in every task)

These are the only four shapes you will encounter. Text inside the quotes must be copied **byte-for-byte** (same characters, punctuation, spaces) so msgids match what tests assert.

1. **Elixir body** (`assign`, `put_flash`, helper return):
   `assign(:page_title, "利用者の編集")` → `assign(:page_title, gettext("利用者の編集"))`
2. **HEEx element body**:
   `<h2 class="...">基本</h2>` → `<h2 class="...">{gettext("基本")}</h2>`
   (Also applies to text inside `<.button>…</.button>`, `<.link>…</.link>`, `<.header>…</.header>`, and bare text nodes.)
3. **HEEx / slot attribute** (`label=`, `prompt=`, `title=`, `phx-disable-with=`):
   `label="氏名"` → `label={gettext("氏名")}`
4. **Interpolation** — gettext uses `%{name}` placeholders; bindings are passed as the 2nd arg. Shown in full where it occurs (Tasks 2, 3, 5).

Repeated msgids across files are fine — gettext collapses them into one `default.pot` entry with multiple file references.

**Per-task discipline (behavior-preserving refactor, not new behavior):**
- First run the file's existing tests to confirm a GREEN baseline.
- Apply the wraps.
- Run the tests again — they must still pass **with no edits to the test files**. Green = rendered text unchanged.
- `mix compile --warnings-as-errors --force` must be clean.
- Commit.

---

## Task 1: `service_user_live/index.ex` (establish the pattern)

**Files:**
- Modify: `lib/ayumi_web/live/service_user_live/index.ex`
- Test (baseline + verify, do not edit): `test/ayumi_web/live/service_user_live_test.exs`

- [x] **Step 1: Confirm GREEN baseline**

Run: `mix test test/ayumi_web/live/service_user_live_test.exs`
Expected: PASS (all tests).

- [x] **Step 2: Wrap each Japanese literal**

Apply these exact edits in `lib/ayumi_web/live/service_user_live/index.ex`:

- L10 (body): `assign(:page_title, "利用者一覧")` → `assign(:page_title, gettext("利用者一覧"))`
- L19 (HEEx body): `利用者一覧` → `{gettext("利用者一覧")}`
- L21 (HEEx body): `<.button navigate={~p"/service_users/new"}>新規登録</.button>` → `<.button navigate={~p"/service_users/new"}>{gettext("新規登録")}</.button>`
- L26 (attr): `<:col :let={su} label="氏名">` → `<:col :let={su} label={gettext("氏名")}>`
- L29 (attr): `<:col :let={su} label="ふりがな">{su.name_kana}</:col>` → `label={gettext("ふりがな")}`
- L30 (attr): `<:col :let={su} label="受給者証番号">{su.recipient_cert_number}</:col>` → `label={gettext("受給者証番号")}`

- [x] **Step 3: Verify GREEN + clean compile**

Run: `mix test test/ayumi_web/live/service_user_live_test.exs`
Expected: PASS (unchanged count; tests not edited).
Run: `mix compile --warnings-as-errors --force`
Expected: clean.

- [x] **Step 4: Commit**

```bash
git add lib/ayumi_web/live/service_user_live/index.ex
git commit -m "refactor: gettext-wrap UI strings in service-user index"
```

---

## Task 2: `service_user_live/form.ex` (incl. interpolated presence banner)

**Files:**
- Modify: `lib/ayumi_web/live/service_user_live/form.ex`
- Test (baseline + verify, do not edit): `test/ayumi_web/live/service_user_live_test.exs`

- [x] **Step 1: Confirm GREEN baseline**

Run: `mix test test/ayumi_web/live/service_user_live_test.exs`
Expected: PASS.

- [x] **Step 2: Wrap the Elixir-body strings**

- L22: `assign(:page_title, "利用者の新規登録")` → `assign(:page_title, gettext("利用者の新規登録"))`
- L32: `assign(:page_title, "利用者の編集")` → `assign(:page_title, gettext("利用者の編集"))`
- L58: `put_flash(:info, "利用者を登録しました")` → `put_flash(:info, gettext("利用者を登録しました"))`
- L71: `put_flash(:info, "利用者情報を更新しました")` → `put_flash(:info, gettext("利用者情報を更新しました"))`
- L79 (stale flash): the literal
  `"他のスタッフが先にこの利用者を更新しました。最新を読み込みました。内容を確認して保存し直してください。"`
  → wrap as `gettext("他のスタッフが先にこの利用者を更新しました。最新を読み込みました。内容を確認して保存し直してください。")`

- [x] **Step 3: Wrap the interpolated presence banner (L153)**

Change:
```heex
        ⚠ {Enum.join(@other_editors, "、")} さんが現在この利用者を編集中です。同時に保存すると、一方の変更が反映されない場合があります。
```
to:
```heex
        {gettext("⚠ %{names} さんが現在この利用者を編集中です。同時に保存すると、一方の変更が反映されない場合があります。", names: Enum.join(@other_editors, "、"))}
```

- [x] **Step 4: Wrap the section headers (HEEx body)**

For each `<h2 class="text-lg font-semibold mb-2">X</h2>`, change `X` → `{gettext("X")}`, with X ∈:
`基本` (L158), `連絡先` (L172), `受給者証` (L182), `障害者手帳` (L197), `医療` (L213), `その他` (L220).

- [x] **Step 5: Wrap the input labels (attributes)**

For each `label="X"`, change to `label={gettext("X")}`, with X ∈:
`氏名`, `ふりがな`, `生年月日`, `性別`, `郵便番号`, `住所`, `電話番号`, `緊急連絡先 氏名`, `続柄`, `緊急連絡先 電話`, `受給者証番号`, `支給市町村`, `障害支援区分`, `支給量`, `受給者証 有効期限`, `手帳の種類`, `手帳番号`, `障害種類・障害名`, `等級`, `通院先`, `主治医`, `服薬・特記`, `相談支援事業所`, `担当相談員`, `備考`.

- [x] **Step 6: Wrap the three prompts and the save button**

- Each `prompt="選択してください"` (L167, L190, L204) → `prompt={gettext("選択してください")}`
- L226: `<.button phx-disable-with="保存中...">保存</.button>` → `<.button phx-disable-with={gettext("保存中...")}>{gettext("保存")}</.button>`

- [x] **Step 7: Verify GREEN + clean compile**

Run: `mix test test/ayumi_web/live/service_user_live_test.exs`
Expected: PASS (unchanged; tests not edited). The page-title and flash assertions (`"利用者の編集"`, `"利用者情報を更新しました"`) and the stale/presence tests still pass — same rendered text.
Run: `mix compile --warnings-as-errors --force`
Expected: clean.

- [x] **Step 8: Commit**

```bash
git add lib/ayumi_web/live/service_user_live/form.ex
git commit -m "refactor: gettext-wrap UI strings in service-user form"
```

---

## Task 3: `service_user_live/show.ex` (incl. interpolated `format_birthdate`)

**Files:**
- Modify: `lib/ayumi_web/live/service_user_live/show.ex`
- Test (baseline + verify, do not edit): `test/ayumi_web/live/service_user_live_test.exs`

- [x] **Step 1: Confirm GREEN baseline**

Run: `mix test test/ayumi_web/live/service_user_live_test.exs`
Expected: PASS.

- [x] **Step 2: Wrap the section headers (HEEx body)**

For each `<h2 class="text-lg font-semibold mb-2">X</h2>`, change `X` → `{gettext("X")}`, with X ∈:
`基本` (L36), `連絡先` (L44), `受給者証` (L60), `障害者手帳` (L73), `医療` (L90), `その他` (L99), `支援計画` (L108).

- [x] **Step 3: Wrap the body text nodes / button / link**

- L28: `<.button navigate={~p"/service_users/#{@service_user.id}/edit"}>編集</.button>` → inner `編集` → `{gettext("編集")}`
- L30 (body): `支援計画を作成` → `{gettext("支援計画を作成")}`
- L85 (body): `登録なし` → `{gettext("登録なし")}`
- L117: `<.link navigate={~p"/support_plans/#{plan.id}"}>詳細</.link>` → inner `詳細` → `{gettext("詳細")}`

- [x] **Step 4: Wrap the `field_row` labels (attributes)**

For each `<.field_row label="X">`, change to `label={gettext("X")}`, with X ∈:
`生年月日`, `性別`, `郵便番号`, `住所`, `電話番号`, `緊急連絡先 氏名`, `続柄`, `緊急連絡先 電話`, `受給者証番号`, `支給市町村`, `障害支援区分`, `支給量`, `有効期限`, `通院先`, `主治医`, `服薬・特記`, `相談支援事業所`, `担当相談員`, `備考`.

- [x] **Step 5: Wrap the table `:col` labels (attributes)**

For each `<:col … label="X">`, change to `label={gettext("X")}`, with X ∈:
`種類` (L79), `手帳番号` (L80), `障害名` (L81), `等級` (L82), `計画期間` (L110), `担当者` (L113), `長期目標` (L114), `次回モニタリング` (L115).

- [x] **Step 6: Wrap the interpolated `format_birthdate/2` helper (L140)**

Change:
```elixir
  defp format_birthdate(%ServiceUser{birthdate: birthdate} = service_user, today),
    do: "#{birthdate}（#{ServiceUser.age(service_user, today)}歳）"
```
to:
```elixir
  defp format_birthdate(%ServiceUser{birthdate: birthdate} = service_user, today),
    do:
      gettext("%{birthdate}（%{age}歳）",
        birthdate: birthdate,
        age: ServiceUser.age(service_user, today)
      )
```
(The `nil` clause `format_birthdate(%ServiceUser{birthdate: nil}, _today), do: nil` is unchanged.) Both `birthdate` (a `Date`) and `age` (an integer) implement `String.Chars`, so gettext interpolation produces the same `"2000-01-01（25歳）"` text.

- [x] **Step 7: Verify GREEN + clean compile**

Run: `mix test test/ayumi_web/live/service_user_live_test.exs`
Expected: PASS (unchanged). The detail-page assertions (`"男性"`, field values, `"編集"`, `"登録なし"`) still pass.
Run: `mix compile --warnings-as-errors --force`
Expected: clean.

- [x] **Step 8: Commit**

```bash
git add lib/ayumi_web/live/service_user_live/show.ex
git commit -m "refactor: gettext-wrap UI strings in service-user show"
```

---

## Task 4: `support_plan_live/form.ex`

**Files:**
- Modify: `lib/ayumi_web/live/support_plan_live/form.ex`
- Test (baseline + verify, do not edit): `test/ayumi_web/live/support_plan_live_test.exs`

- [x] **Step 1: Confirm GREEN baseline**

Run: `mix test test/ayumi_web/live/support_plan_live_test.exs`
Expected: PASS.

- [x] **Step 2: Wrap the Elixir-body strings**

- L15: `assign(:page_title, "支援計画の作成")` → `assign(:page_title, gettext("支援計画の作成"))`
- L37: `put_flash(:info, "支援計画を作成しました")` → `put_flash(:info, gettext("支援計画を作成しました"))`

- [x] **Step 3: Wrap the HEEx body, labels, prompt, button**

- L59 (body): `支援計画の作成` → `{gettext("支援計画の作成")}`
- L67 (attr): `label="担当者"` → `label={gettext("担当者")}`
- L69 (attr): `prompt="選択してください"` → `prompt={gettext("選択してください")}`
- L71 (attr): `label="計画開始日"` → `label={gettext("計画開始日")}`
- L72 (attr): `label="計画終了日"` → `label={gettext("計画終了日")}`
- L73 (attr): `label="長期目標"` → `label={gettext("長期目標")}`
- L77 (attr): `label="次回モニタリング予定日"` → `label={gettext("次回モニタリング予定日")}`
- L79: `<.button phx-disable-with="保存中...">保存</.button>` → `<.button phx-disable-with={gettext("保存中...")}>{gettext("保存")}</.button>`

- [x] **Step 4: Verify GREEN + clean compile**

Run: `mix test test/ayumi_web/live/support_plan_live_test.exs`
Expected: PASS (unchanged).
Run: `mix compile --warnings-as-errors --force`
Expected: clean.

- [x] **Step 5: Commit**

```bash
git add lib/ayumi_web/live/support_plan_live/form.ex
git commit -m "refactor: gettext-wrap UI strings in support-plan form"
```

---

## Task 5: `support_plan_live/show.ex` (incl. mixed-interpolation subtitle)

**Files:**
- Modify: `lib/ayumi_web/live/support_plan_live/show.ex`
- Test (baseline + verify, do not edit): `test/ayumi_web/live/support_plan_live_test.exs`

- [x] **Step 1: Confirm GREEN baseline**

Run: `mix test test/ayumi_web/live/support_plan_live_test.exs`
Expected: PASS.

- [x] **Step 2: Wrap the Elixir-body strings**

- L22: `put_flash(:info, "短期目標を追加しました")` → `put_flash(:info, gettext("短期目標を追加しました"))`
- L34: `assign(:page_title, "支援計画")` → `assign(:page_title, gettext("支援計画"))`

- [x] **Step 3: Wrap the mixed-interpolation subtitle (L47)**

Change:
```heex
          {@support_plan.service_user.name} ／ 担当 {User.display_name(@support_plan.staff)}
```
to:
```heex
          {gettext("%{user} ／ 担当 %{staff}", user: @support_plan.service_user.name, staff: User.display_name(@support_plan.staff))}
```

- [x] **Step 4: Wrap the remaining body text, item titles, col label, input label, button**

- L45 (body, inside `<.header>`): `支援計画` → `{gettext("支援計画")}`
- L52 (attr): `<:item title="計画期間">` → `title={gettext("計画期間")}`
- L53 (attr): `<:item title="長期目標">` → `title={gettext("長期目標")}`
- L54 (attr): `<:item title="次回モニタリング予定日">` → `title={gettext("次回モニタリング予定日")}`
- L58: `<.header>短期目標</.header>` → `<.header>{gettext("短期目標")}</.header>`
- L62 (attr): `<:col :let={goal} label="内容">` → `label={gettext("内容")}`
- L71 (attr): `label="短期目標を追加"` → `label={gettext("短期目標を追加")}`
- L72: `<.button>追加</.button>` → `<.button>{gettext("追加")}</.button>`

- [x] **Step 5: Verify GREEN + clean compile**

Run: `mix test test/ayumi_web/live/support_plan_live_test.exs`
Expected: PASS (unchanged).
Run: `mix compile --warnings-as-errors --force`
Expected: clean.

- [x] **Step 6: Commit**

```bash
git add lib/ayumi_web/live/support_plan_live/show.ex
git commit -m "refactor: gettext-wrap UI strings in support-plan show"
```

---

## Task 6: `components/layouts.ex` (shared nav)

**Files:**
- Modify: `lib/ayumi_web/components/layouts.ex`
- Test (baseline + verify, do not edit): full suite (shared component)

- [x] **Step 1: Confirm GREEN baseline**

Run: `mix test`
Expected: PASS (188).

- [x] **Step 2: Wrap the nav link (L48)**

Change:
```heex
            <.link navigate={~p"/service_users"} class="font-semibold">利用者</.link>
```
to:
```heex
            <.link navigate={~p"/service_users"} class="font-semibold">{gettext("利用者")}</.link>
```

- [x] **Step 3: Verify GREEN + clean compile**

Run: `mix test`
Expected: PASS (188, unchanged).
Run: `mix compile --warnings-as-errors --force`
Expected: clean.

- [x] **Step 4: Commit**

```bash
git add lib/ayumi_web/components/layouts.ex
git commit -m "refactor: gettext-wrap nav label in layout"
```

---

## Task 7: Extract `default.pot` + final gate

**Files:**
- Create: `priv/gettext/default.pot` (generated)

- [x] **Step 1: Confirm no inline Japanese remains in the in-scope files**

Run:
```bash
grep -rn '"[^"]*[ぁ-んァ-ヶ一-龯][^"]*"' \
  lib/ayumi_web/live/service_user_live lib/ayumi_web/live/support_plan_live \
  lib/ayumi_web/components/layouts.ex | grep -v 'gettext('
```
Expected: no output (every Japanese string literal in these files now sits inside a `gettext(...)` call). If any line prints, wrap it per the rules and re-run.

- [x] **Step 2: Generate the POT manifest**

Run: `mix gettext.extract`
Expected: writes/updates `priv/gettext/default.pot` containing the app msgids (`利用者の編集`, `氏名`, etc.) with file references. (It also lists already-wrapped framework strings — expected; it is the full manifest.)

- [x] **Step 3: Confirm the POT is in sync with the code**

Run: `mix gettext.extract --check-up-to-date`
Expected: exits 0 (no "POT files are not up to date" error). If it fails, run `mix gettext.extract` again and re-check.

- [x] **Step 4: Run the full quality gate**

Run: `mix review`
Expected: `format --check-formatted` clean, `compile --warnings-as-errors --force` clean, `credo` no issues, `test` 188 passed. Run `mix format` and fix anything flagged, then re-run until clean.

- [x] **Step 5: Commit**

```bash
git add priv/gettext/default.pot
git commit -m "chore: extract gettext default.pot for app UI strings"
```

---

## Self-Review

**1. Spec coverage (design → task):**
- 日本語 msgid 戦略 → all tasks use `gettext("…日本語…")`; no `ja` locale created, no `default_locale` change. ✅
- 範囲 = Web層6ファイル → Task 1 (index), 2 (form), 3 (show), 4 (sp form), 5 (sp show), 6 (layouts). ✅
- 対象外（enum ラベル / 検証メッセージ / accounts.ex / CLI）→ no task touches them. ✅
- 補間（`%{}`）の3ケース → Task 2 banner, Task 3 `format_birthdate`, Task 5 subtitle, each shown in full. ✅
- `default.pot` 生成 → Task 7. `--check-up-to-date` で同期確認 → Task 7 Step 3. ✅
- 安全網（既存テスト無改変で緑）→ every file task asserts PASS with tests not edited; the design's "rendered text identical" requirement is enforced as the verification. ✅
- `mix review` ゲート → Task 7 Step 4. ✅

**2. Placeholder scan:** No TBD/"handle the rest"/"similar to Task N". Every string to wrap is enumerated explicitly with its exact characters; the uniform attribute/body transforms are shown once in the rules and applied to listed strings. ✅

**3. Consistency:** The four transformation shapes (body, HEEx body, attribute, interpolation) are used identically across all tasks. Interpolation always uses gettext `%{name}` syntax with a bindings keyword list. The same msgid appearing in multiple files (e.g. `氏名`, `性別`, `受給者証`, `長期目標`, `選択してください`, `保存中...`/`保存`) is intentional and collapses to one POT entry. ✅

---

## Notes for the reviewer

- This is a **behavior-preserving refactor**: no test file is edited. If any existing assertion breaks, it means a msgid was altered (a typo, changed punctuation/space, or a missed `%{}` placeholder) — fix the wrap to restore byte-identical text, do not change the test.
- Dropdown option text rendered from enum labels (e.g. `男性`, `身体障害者手帳`) is intentionally **not** in `default.pot` — those labels live centralized in the domain enum modules and are out of scope by design.
