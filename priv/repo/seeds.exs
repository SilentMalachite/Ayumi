# Script for populating the database. Run it directly with:
#
#     mix run priv/repo/seeds.exs
#
# It also runs automatically as part of `mix setup` and `mix ecto.reset`.
#
# Demo staff accounts and sample service users are created in the :dev
# environment ONLY. In :test and :prod the demo data is skipped — there create
# staff accounts with `mix ayumi.create_user`.
#
# The script is idempotent: staff are matched by email and sample domain data is
# only inserted when no service users exist yet, so re-running is safe.

alias Ayumi.Accounts
alias Ayumi.Plans

demo_password = "ayumi-dev-1234"

ensure_staff = fn email, name, role ->
  case Accounts.get_user_by_email(email) do
    nil ->
      {:ok, user} =
        Accounts.register_staff_user(%{
          email: email,
          name: name,
          password: demo_password,
          role: role
        })

      IO.puts("  職員を作成: #{user.email}（#{user.role}）")
      user

    user ->
      IO.puts("  職員は既に存在: #{user.email}")
      user
  end
end

if Mix.env() == :dev do
  IO.puts("デモデータを投入します (MIX_ENV=dev)")

  admin = ensure_staff.("admin@ayumi.local", "管理 太郎", "manager")
  _staff = ensure_staff.("staff@ayumi.local", "支援 花子", "supporter")

  if Plans.list_service_users() == [] do
    today = Date.utc_today()

    {:ok, yamada} =
      Plans.create_service_user(%{
        name: "山田 太郎",
        name_kana: "やまだ たろう",
        gender: :male,
        birthdate: ~D[1990-05-01]
      })

    {:ok, sato} =
      Plans.create_service_user(%{
        name: "佐藤 花子",
        name_kana: "さとう はなこ",
        gender: :female,
        birthdate: ~D[1985-11-20]
      })

    {:ok, _suzuki} =
      Plans.create_service_user(%{
        name: "鈴木 一郎",
        name_kana: "すずき いちろう",
        gender: :male,
        birthdate: ~D[1978-02-15]
      })

    # 山田さん: モニタリング予定日が近い計画
    {:ok, plan1} =
      Plans.create_support_plan(%{
        service_user_id: yamada.id,
        staff_id: admin.id,
        period_start: ~D[2026-04-01],
        period_end: ~D[2026-09-30],
        long_term_goal: "安定した通所リズムを確立する",
        next_monitoring_date: Date.add(today, 5)
      })

    {:ok, _} = Plans.create_goal(%{support_plan_id: plan1.id, description: "毎日昼食を完食する"})
    {:ok, _} = Plans.create_goal(%{support_plan_id: plan1.id, description: "週4日通所する"})

    # 佐藤さん: モニタリング予定日が過ぎた計画（期限超過の確認用）
    {:ok, plan2} =
      Plans.create_support_plan(%{
        service_user_id: sato.id,
        staff_id: admin.id,
        period_start: ~D[2026-01-01],
        period_end: ~D[2026-06-30],
        long_term_goal: "作業に集中できる時間を延ばす",
        next_monitoring_date: Date.add(today, -3)
      })

    {:ok, _} = Plans.create_goal(%{support_plan_id: plan2.id, description: "30分間集中して作業する"})

    IO.puts("  利用者・支援計画・目標のサンプルを作成しました")
  else
    IO.puts("  利用者データが既にあるため、サンプルの投入はスキップしました")
  end

  IO.puts("""

  開発用ログイン:
    admin@ayumi.local / #{demo_password} (manager)
    staff@ayumi.local / #{demo_password} (supporter)
  """)
else
  IO.puts("""
  MIX_ENV=#{Mix.env()}: デモデータの投入はスキップします。
  職員アカウントは次のコマンドで作成してください:
      mix ayumi.create_user
  """)
end
