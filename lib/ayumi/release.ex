defmodule Ayumi.Release do
  @moduledoc """
  Release helpers callable via `bin/ayumi eval`.

  Mix tasks are unavailable in a compiled release, so this module
  exposes the operations needed to bootstrap a production instance:

      bin/ayumi eval "Ayumi.Release.migrate()"
      bin/ayumi eval "Ayumi.Release.create_user()"
  """

  @app :ayumi

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  def create_user do
    load_app()
    {:ok, _} = Application.ensure_all_started(@app)

    email = prompt("メールアドレス: ")
    name = prompt("氏名: ")
    password = prompt("パスワード（12文字以上）: ")
    role = prompt_role()

    case Ayumi.Accounts.register_staff_user(%{
           email: email,
           name: name,
           password: password,
           role: role
         }) do
      {:ok, user} ->
        IO.puts("職員アカウントを作成しました: #{user.email}（#{user.role}）")

      {:error, changeset} ->
        IO.puts("作成に失敗しました:")
        print_errors(changeset)
    end
  end

  defp print_errors(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.each(fn {field, messages} ->
      IO.puts("  - #{field}: #{Enum.join(messages, ", ")}")
    end)
  end

  defp prompt(label) do
    IO.write(label)

    case IO.read(:stdio, :line) do
      :eof -> ""
      {:error, _} -> ""
      data -> String.trim(data)
    end
  end

  defp prompt_role do
    IO.puts("ロールを選択してください:")
    IO.puts("  1) supporter（支援者）")
    IO.puts("  2) manager（サービス管理責任者）")

    case prompt("番号を入力 [1]: ") do
      "" ->
        "supporter"

      "1" ->
        "supporter"

      "2" ->
        "manager"

      _ ->
        IO.puts("1 または 2 を入力してください。")
        prompt_role()
    end
  end

  defp load_app do
    Application.load(@app)
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end
end
