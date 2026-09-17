defmodule Ayumi.Imports.ServiceUsersPlan do
  @moduledoc """
  Plans a service user master import. Create-only: a row for someone who is
  already registered is skipped, never applied as an update — the master is
  edited on screen, where optimistic locking and the certificate rows live.

  A row counts as already registered when any of these holds:

    * its 利用者ID exists (an unknown id is an error — ids are never assigned by a file)
    * its 受給者証番号 matches, ignoring leading zeros, which Excel drops
    * its 氏名 and 生年月日 both match, ignoring width and spacing

  Reads the database but never writes.
  """

  alias Ayumi.CSV.ServiceUsers
  alias Ayumi.Imports.Matching
  alias Ayumi.Imports.Preview
  alias Ayumi.Plans
  alias Ayumi.Plans.ServiceUser

  @cert_number_digits 10

  @doc "Builds the preview for decoded `rows` (`[{row_number, cells}]`)."
  def build(rows, ignored_headers) do
    directory = directory()
    results = Enum.map(rows, &plan_row(&1, directory))

    {candidates, duplicate_errors} =
      reject_duplicates(for {:insert, candidate} <- results, do: candidate)

    row_errors = for {:error, errors} <- results, error <- errors, do: error

    %Preview{
      dataset: :service_users,
      total_rows: length(rows),
      rows: rows,
      to_insert: Enum.map(candidates, &%{row: &1.row, kind: :new, attrs: &1.attrs}),
      skipped: for({:skip, skipped} <- results, do: skipped),
      errors: Enum.sort_by(row_errors ++ duplicate_errors, & &1.row),
      warnings: Enum.flat_map(candidates, &warnings(&1, directory)),
      ignored_headers: ignored_headers
    }
  end

  defp plan_row({row, cells}, directory) do
    with {:ok, parsed} <- ServiceUsers.parse(cells),
         :new <- find_existing(parsed, directory),
         attrs = insert_attrs(parsed),
         :ok <- validate(attrs) do
      {:insert, %{row: row, attrs: attrs}}
    else
      {:existing, reason} -> {:skip, %{row: row, reason: reason}}
      {:error, errors} -> {:error, Enum.map(errors, &Map.put(&1, :row, row))}
    end
  end

  # Blank cells are left out rather than sent as nil, so schema defaults (在籍状態
  # defaults to 在籍) still apply. 利用者ID is never written.
  defp insert_attrs(parsed) do
    parsed
    |> Map.delete(:id)
    |> Map.reject(fn {_key, value} -> is_nil(value) end)
  end

  # Validation stays in the changeset; this only maps its errors onto columns.
  defp validate(attrs) do
    changeset = Plans.change_service_user(%ServiceUser{}, attrs)

    if changeset.valid?,
      do: :ok,
      else: {:error, Ayumi.Imports.changeset_errors(changeset, &ServiceUsers.header_for/1)}
  end

  ## Recognizing registered service users

  defp directory do
    service_users = Plans.list_service_users(include_withdrawn: true)

    %{
      by_id: Map.new(service_users, &{&1.id, &1}),
      by_cert: index_by(service_users, &Matching.cert_key(&1.recipient_cert_number)),
      by_person: index_by(service_users, &person_key/1),
      by_name: Enum.group_by(service_users, &Matching.name_key(&1.name))
    }
  end

  defp index_by(service_users, key_fun) do
    for service_user <- service_users, key = key_fun.(service_user), into: %{} do
      {key, service_user}
    end
  end

  defp person_key(%{name: name, birthdate: %Date{} = birthdate}) when is_binary(name) do
    {Matching.name_key(name), birthdate}
  end

  defp person_key(_), do: nil

  defp find_existing(%{id: id}, directory) when is_integer(id) do
    case Map.get(directory.by_id, id) do
      nil ->
        {:error,
         [
           %{
             column: ServiceUsers.header_for(:id),
             message: "利用者ID #{id} は登録されていません。新しい利用者は利用者ID を空欄にしてください"
           }
         ]}

      service_user ->
        {:existing, "利用者ID #{id}（#{service_user.name}）は登録済みです"}
    end
  end

  defp find_existing(parsed, directory) do
    by_cert = Map.get(directory.by_cert, Matching.cert_key(parsed.recipient_cert_number))
    by_person = Map.get(directory.by_person, person_key(parsed))

    cond do
      by_cert -> {:existing, "受給者証番号が同じ利用者（ID #{by_cert.id} #{by_cert.name}）が登録済みです"}
      by_person -> {:existing, "氏名と生年月日が同じ利用者（ID #{by_person.id}）が登録済みです"}
      true -> :new
    end
  end

  ## Duplicates within the file

  defp reject_duplicates(candidates) do
    {kept, errors, _seen} =
      Enum.reduce(candidates, {[], [], %{}}, fn candidate, {kept, errors, seen} ->
        case Enum.find(duplicate_keys(candidate.attrs), &Map.has_key?(seen, &1)) do
          nil -> {[candidate | kept], errors, remember(seen, candidate)}
          key -> {kept, [duplicate_error(candidate.row, key, seen[key]) | errors], seen}
        end
      end)

    {Enum.reverse(kept), errors}
  end

  defp duplicate_keys(attrs) do
    cert = Matching.cert_key(attrs[:recipient_cert_number])
    person = person_key(%{name: attrs[:name], birthdate: attrs[:birthdate]})

    Enum.reject([person && {:person, person}, cert && {:cert, cert}], &is_nil/1)
  end

  defp remember(seen, candidate) do
    Enum.reduce(duplicate_keys(candidate.attrs), seen, &Map.put_new(&2, &1, candidate.row))
  end

  defp duplicate_error(row, {:person, _key}, first_row) do
    %{
      row: row,
      column: ServiceUsers.header_for(:name),
      message: "#{first_row}行目と氏名・生年月日が同じです。1 つにまとめてください"
    }
  end

  defp duplicate_error(row, {:cert, _key}, first_row) do
    %{
      row: row,
      column: ServiceUsers.header_for(:recipient_cert_number),
      message: "#{first_row}行目と受給者証番号が同じです。1 つにまとめてください"
    }
  end

  ## Warnings (not blocking)

  defp warnings(candidate, directory) do
    [cert_digits_warning(candidate.attrs), same_name_warning(candidate.attrs, directory)]
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&Map.put(&1, :row, candidate.row))
  end

  defp cert_digits_warning(%{recipient_cert_number: number}) do
    digits = number |> String.normalize(:nfkc) |> String.replace(~r/\D/u, "")

    if String.length(digits) != @cert_number_digits do
      %{
        column: ServiceUsers.header_for(:recipient_cert_number),
        message: "受給者証番号が #{@cert_number_digits} 桁ではありません。Excel で先頭の 0 が消えていないか確認してください"
      }
    end
  end

  defp cert_digits_warning(_attrs), do: nil

  # Reached only when name + birthdate did not match: either side lacks a
  # birthdate, or the birthdates differ (then it is simply another person).
  defp same_name_warning(attrs, directory) do
    same_name = Map.get(directory.by_name, Matching.name_key(attrs.name), [])
    unverifiable = Enum.filter(same_name, &(is_nil(&1.birthdate) or is_nil(attrs[:birthdate])))

    case unverifiable do
      [] ->
        nil

      [service_user | _] ->
        %{
          column: ServiceUsers.header_for(:name),
          message:
            "同じ氏名の利用者（ID #{service_user.id}）が登録済みですが、生年月日で照合できないため" <>
              "新しい利用者として追加されます"
        }
    end
  end
end
