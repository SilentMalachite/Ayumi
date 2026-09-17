defmodule AyumiWeb.ImportLive.Index do
  use AyumiWeb, :live_view

  alias Ayumi.Imports
  alias Ayumi.Imports.Dataset
  alias Ayumi.Imports.Preview

  # Long error lists are cut off on screen; the counts above still show the total.
  @max_listed_errors 100

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("CSV取込"))
     |> assign(:max_rows, Imports.max_rows())
     |> assign(:dataset_options, Dataset.options())
     |> assign(:dataset, :attendance)
     |> reset()
     |> allow_upload(:csv,
       accept: ~w(.csv),
       max_entries: 1,
       max_file_size: Imports.max_bytes()
     )}
  end

  defp reset(socket) do
    socket
    |> assign(:preview, nil)
    |> assign(:counts, nil)
    |> assign(:file_error, nil)
    |> assign(:stale?, false)
    |> assign(:result, nil)
  end

  # Required by live uploads; the file is only read on submit. Changing the
  # dataset discards a pending preview, which belongs to the previous choice.
  @impl true
  def handle_event("validate", params, socket) do
    case Dataset.from_param(params["dataset"]) do
      {:ok, dataset} when dataset != socket.assigns.dataset ->
        {:noreply, socket |> reset() |> assign(:dataset, dataset)}

      _same_or_unknown ->
        {:noreply, socket}
    end
  end

  def handle_event("preview", _params, socket) do
    uploaded =
      consume_uploaded_entries(socket, :csv, fn %{path: path}, _entry ->
        {:ok, File.read!(path)}
      end)

    {:noreply, preview(reset(socket), uploaded)}
  end

  def handle_event("commit", _params, %{assigns: %{preview: %Preview{} = preview}} = socket) do
    case Imports.commit(socket.assigns.current_scope, preview) do
      {:ok, result} ->
        {:noreply,
         socket
         |> reset()
         |> assign(:result, result)
         |> put_flash(:info, gettext("取込が完了しました"))}

      {:error, :stale, fresh} ->
        {:noreply, socket |> assign_preview(fresh) |> assign(:stale?, true)}

      {:error, message} ->
        {:noreply, socket |> reset() |> assign(:file_error, message)}
    end
  end

  def handle_event("commit", _params, socket), do: {:noreply, socket}

  def handle_event("cancel", _params, socket), do: {:noreply, reset(socket)}

  defp preview(socket, [binary]) do
    case Imports.preview(socket.assigns.current_scope, socket.assigns.dataset, binary) do
      {:ok, preview} -> assign_preview(socket, preview)
      {:error, message} -> assign(socket, :file_error, message)
    end
  end

  defp preview(socket, []) do
    assign(socket, :file_error, gettext("ファイルを選択してください。"))
  end

  defp assign_preview(socket, %Preview{} = preview) do
    socket
    |> assign(:preview, preview)
    |> assign(:counts, Preview.counts(preview))
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :max_listed_errors, @max_listed_errors)

    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <.header>
        {gettext("CSV取込")}
        <:subtitle>
          {gettext("Excel で作成・編集した CSV を取り込みます。")}
        </:subtitle>
      </.header>

      <ul class="mt-4 list-disc pl-5 text-sm text-base-content/70 space-y-1">
        <li>
          {gettext("「CSV出力」で保存したファイルを Excel で編集し、そのまま取り込めます。見出しの行は変えないでください。")}
        </li>
        <li>
          {gettext("Excel で保存するときは、ファイルの種類を「CSV UTF-8（コンマ区切り）」にしてください。")}
        </li>
        <li :if={@dataset == :attendance}>
          {gettext("すでに記録のある利用日は、訂正として追記されます（元の記録は履歴に残ります）。")}
        </li>
        <li :if={@dataset == :support_records}>
          {gettext("支援日・区分・内容は必須です。記録者は取り込んだ人、記録日時は取り込んだ時刻になります。")}
        </li>
        <li :if={@dataset == :support_records}>
          {gettext("利用者・支援日・区分・内容がすべて同じ記録が既にある行は取り込みません。内容を書き換えた行は、元の記録を残したまま新しい記録として追加されます。")}
        </li>
        <li :if={@dataset == :support_records}>
          {gettext("未来の支援日は取り込めません。退所した利用者の過去の記録は取り込めます（画面からの入力はできません）。")}
        </li>
        <li :if={@dataset == :service_users}>
          {gettext(
            "新しい利用者だけを追加します。登録済みの利用者（利用者ID・受給者証番号・氏名と生年月日のいずれかが一致）は変更しません。変更は利用者の編集画面で行ってください。"
          )}
        </li>
        <li :if={@dataset == :service_users}>
          {gettext("新しい利用者は利用者ID を空欄にしてください。障害者手帳の列は取り込まれません。")}
        </li>
        <li :if={@dataset == :service_users}>
          {gettext("受給者証番号・電話番号・郵便番号の列は、Excel で「文字列」にしておくと先頭の 0 が消えません。")}
        </li>
        <li>
          {gettext("CSV から行を消しても、記録は削除されません。")}
        </li>
        <li>
          {gettext("1 行でもエラーがあると、ファイル全体を取り込みません。上限は %{rows} 行です。",
            rows: @max_rows
          )}
        </li>
      </ul>

      <form id="import-form" phx-change="validate" phx-submit="preview" class="mt-6 space-y-4">
        <div>
          <label for="import-dataset" class="block text-sm font-medium">
            {gettext("取り込むデータ")}
          </label>
          <select id="import-dataset" name="dataset" class="select select-bordered w-full mt-1">
            <option
              :for={{label, value} <- @dataset_options}
              value={value}
              selected={value == @dataset}
            >
              {label}
            </option>
          </select>
        </div>

        <.live_file_input upload={@uploads.csv} class="file-input file-input-bordered w-full" />

        <p :for={entry <- @uploads.csv.entries} class="text-sm">
          {entry.client_name}
          <span :for={error <- upload_errors(@uploads.csv, entry)} class="text-error">
            — {upload_error_message(error)}
          </span>
        </p>
        <p :for={error <- upload_errors(@uploads.csv)} class="text-sm text-error">
          {upload_error_message(error)}
        </p>

        <button type="submit" class="btn btn-primary">{gettext("内容を確認")}</button>
      </form>

      <div :if={@file_error} id="import-file-error" class="mt-6 alert alert-error">
        <p>{@file_error}</p>
      </div>

      <div :if={@result} id="import-result" class="mt-6 alert alert-success">
        <div>
          <p class="font-semibold">{gettext("取込が完了しました")}</p>
          <p class="text-sm">
            {gettext(
              "追加 %{inserted} 件（うち訂正 %{corrections} 件）／変更なし %{unchanged} 件／既存 %{skipped} 件",
              inserted: @result.inserted,
              corrections: @result.corrections,
              unchanged: @result.unchanged,
              skipped: @result.skipped
            )}
          </p>
        </div>
      </div>

      <section :if={@preview} id="import-preview" class="mt-6 space-y-4">
        <h2 class="text-lg font-semibold">{gettext("取込内容の確認")}</h2>

        <div :if={@stale?} id="import-stale" class="alert alert-warning">
          <p>
            {gettext("確認のあとに記録が変更されたため、内容を計算し直しました。もう一度確認してから実行してください。")}
          </p>
        </div>

        <p id="import-counts">
          {gettext(
            "全 %{total} 行: 追加 %{inserted} 件（うち訂正 %{corrections} 件）／変更なし %{unchanged} 件／既存 %{skipped} 件／エラー %{errors} 件",
            total: @preview.total_rows,
            inserted: @counts.new + @counts.corrections,
            corrections: @counts.corrections,
            unchanged: @counts.unchanged,
            skipped: @counts.skipped,
            errors: @counts.errors
          )}
        </p>

        <p :if={@preview.ignored_headers != []} class="text-sm text-base-content/70">
          {gettext("次の列は取り込まれません: %{headers}",
            headers: Enum.join(@preview.ignored_headers, "、")
          )}
        </p>

        <div :if={@counts.errors > 0}>
          <p class="text-error">
            {gettext("エラーを修正して、もう一度ファイルを選択してください。何も取り込まれていません。")}
          </p>
          <table id="import-errors" class="table table-sm mt-2">
            <thead>
              <tr>
                <th>{gettext("行")}</th>
                <th>{gettext("列")}</th>
                <th>{gettext("内容")}</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={error <- Enum.take(@preview.errors, @max_listed_errors)}>
                <td>{error.row}</td>
                <td>{error.column}</td>
                <td>{error.message}</td>
              </tr>
            </tbody>
          </table>
          <p :if={@counts.errors > @max_listed_errors} class="text-sm text-base-content/70">
            {gettext("他 %{count} 件", count: @counts.errors - @max_listed_errors)}
          </p>
        </div>

        <div :if={@preview.warnings != []}>
          <p class="text-warning">
            {gettext("次の行は取り込めますが、内容を確認してください。")}
          </p>
          <table id="import-warnings" class="table table-sm mt-2">
            <tbody>
              <tr :for={warning <- Enum.take(@preview.warnings, @max_listed_errors)}>
                <td>{warning.row}</td>
                <td>{warning.column}</td>
                <td>{warning.message}</td>
              </tr>
            </tbody>
          </table>
        </div>

        <div :if={@preview.skipped != []}>
          <p class="text-sm text-base-content/70">
            {gettext("次の行は登録済みのため取り込まれません（変更もされません）。")}
          </p>
          <table id="import-skipped" class="table table-sm mt-2">
            <tbody>
              <tr :for={skipped <- Enum.take(@preview.skipped, @max_listed_errors)}>
                <td>{skipped.row}</td>
                <td>{skipped.reason}</td>
              </tr>
            </tbody>
          </table>
        </div>

        <p :if={@counts.errors == 0 and @preview.to_insert == []}>
          {gettext("取り込む変更はありません。")}
        </p>

        <div class="flex gap-2">
          <button
            :if={@counts.errors == 0 and @preview.to_insert != []}
            id="import-commit"
            type="button"
            phx-click="commit"
            phx-disable-with={gettext("取込中…")}
            class="btn btn-primary"
          >
            {gettext("取込を実行")}
          </button>
          <button id="import-cancel" type="button" phx-click="cancel" class="btn btn-ghost">
            {gettext("やめる")}
          </button>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp upload_error_message(:too_large), do: gettext("ファイルが大きすぎます。月ごとに分けて取り込んでください。")
  defp upload_error_message(:not_accepted), do: gettext("CSV ファイル（.csv）を選択してください。")
  defp upload_error_message(:too_many_files), do: gettext("ファイルは 1 つだけ選択してください。")
  defp upload_error_message(_other), do: gettext("ファイルを読み込めませんでした。")
end
