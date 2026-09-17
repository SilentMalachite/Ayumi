defmodule Ayumi.Imports.ServiceUserResolver do
  @moduledoc """
  Finds the service user a CSV row refers to, for the log imports.

  `利用者ID` is authoritative. `氏名` alone is accepted only when it is unique, and
  when both are given they must agree — a guard against a pasted id column that
  has slipped by a row. Withdrawn service users are included; whether they may
  receive a row is the caller's rule.
  """

  alias Ayumi.Imports.Matching
  alias Ayumi.Plans

  @doc "Loads every service user once, indexed for `resolve/3`."
  def directory do
    service_users = Plans.list_service_users(include_withdrawn: true)

    %{
      by_id: Map.new(service_users, &{&1.id, &1}),
      by_name: Enum.group_by(service_users, &Matching.name_key(&1.name))
    }
  end

  @doc """
  Resolves parsed `:service_user_id` / `:service_user_name`. `header_for` maps those
  keys to the dataset's column headers for the error.
  """
  def resolve(%{service_user_id: nil, service_user_name: nil}, _directory, header_for) do
    error(header_for, :service_user_id, "利用者ID か氏名を入力してください")
  end

  def resolve(%{service_user_id: nil, service_user_name: name}, directory, header_for) do
    case Map.get(directory.by_name, Matching.name_key(name), []) do
      [service_user] ->
        {:ok, service_user}

      [] ->
        error(header_for, :service_user_name, "氏名「#{name}」の利用者が見つかりません")

      _several ->
        error(
          header_for,
          :service_user_name,
          "氏名「#{name}」の利用者が複数います。利用者ID を入力してください"
        )
    end
  end

  def resolve(%{service_user_id: id, service_user_name: name}, directory, header_for) do
    case Map.get(directory.by_id, id) do
      nil -> error(header_for, :service_user_id, "利用者ID #{id} は登録されていません")
      service_user -> check_name(service_user, name, header_for)
    end
  end

  defp check_name(service_user, nil, _header_for), do: {:ok, service_user}

  defp check_name(service_user, name, header_for) do
    if Matching.name_key(service_user.name) == Matching.name_key(name) do
      {:ok, service_user}
    else
      error(
        header_for,
        :service_user_name,
        "利用者ID #{service_user.id} の氏名は「#{service_user.name}」です。ID か氏名を確認してください"
      )
    end
  end

  defp error(header_for, key, message) do
    {:error, [%{column: header_for.(key), message: message}]}
  end
end
