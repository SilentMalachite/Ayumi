defmodule Mix.Tasks.Ayumi.CreateUser do
  @shortdoc "職員ログインアカウントを作成する（オフライン用）"

  @moduledoc """
  確認済み（メール確認不要）で、メールアドレス＋パスワードでログインできる職員
  アカウントを作成します。

  この施設はオフライン運用でメール送信を行わないため、通常のメールリンクによる
  登録は使えません。本タスクが本番環境での職員アカウント作成手段です。

  ## 使い方

  対話的に入力（引数を省略した項目は順に尋ねられます）:

      $ mix ayumi.create_user

  引数で指定（スクリプト向け。パスワードはシェル履歴に残る点に注意）:

      $ mix ayumi.create_user --email staff@example.com --name "支援 太郎" --password "12文字以上のパスワード"

  ## オプション

    * `--email`    メールアドレス（ログインID）
    * `--name`     氏名（担当者として表示されます）
    * `--password` パスワード（12文字以上）
    * `--role`     ロール（manager / supporter、省略時 supporter）
  """

  use Mix.Task

  alias Ayumi.Accounts

  @switches [email: :string, name: :string, password: :string, role: :string]

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _rest, _invalid} = OptionParser.parse(args, strict: @switches)

    email = opts[:email] || prompt_required("メールアドレス: ")
    name = opts[:name] || prompt_required("氏名: ")
    password = opts[:password] || prompt_password("パスワード（12文字以上）: ")
    role = opts[:role] || prompt_role()

    case Accounts.register_staff_user(%{email: email, name: name, password: password, role: role}) do
      {:ok, user} ->
        Mix.shell().info("職員アカウントを作成しました: #{user.email}（#{user.role}）")

      {:error, changeset} ->
        Mix.shell().error("作成に失敗しました:")

        Enum.each(format_errors(changeset), fn {field, messages} ->
          Mix.shell().error("  - #{field}: #{Enum.join(messages, ", ")}")
        end)

        exit({:shutdown, 1})
    end
  end

  defp prompt_required(label) do
    case String.trim(Mix.shell().prompt(label)) do
      "" ->
        Mix.shell().error("入力が必要です。")
        prompt_required(label)

      value ->
        value
    end
  end

  # Hide the password while typing where the terminal supports it; fall back to
  # a visible prompt otherwise (e.g. on Windows or when stdin is not a tty).
  defp prompt_password(label) do
    if disable_echo() do
      value = String.trim(Mix.shell().prompt(label))
      enable_echo()
      IO.write("\n")
      value
    else
      String.trim(Mix.shell().prompt(label))
    end
  end

  defp prompt_role do
    Mix.shell().info("ロールを選択してください:")
    Mix.shell().info("  1) supporter（支援者）")
    Mix.shell().info("  2) manager（サービス管理責任者）")

    case String.trim(Mix.shell().prompt("番号を入力 [1]: ")) do
      "" ->
        "supporter"

      "1" ->
        "supporter"

      "2" ->
        "manager"

      _ ->
        Mix.shell().error("1 または 2 を入力してください。")
        prompt_role()
    end
  end

  defp disable_echo, do: stty(["-echo"])
  defp enable_echo, do: stty(["echo"])

  defp stty(args) do
    case System.cmd("stty", args, stderr_to_stdout: true) do
      {_, 0} -> true
      _ -> false
    end
  rescue
    _ -> false
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
