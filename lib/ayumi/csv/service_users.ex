defmodule Ayumi.CSV.ServiceUsers do
  @moduledoc """
  CSV layout for the service user master (利用者台帳). Columns follow the
  registration form, top to bottom, under the form's labels. Service users must
  have `:disability_certificates` preloaded.

  The import reads every column except 障害者手帳, which is an export-only summary
  of a has_many. Parsed keys are the schema's field names, plus `:id` from 利用者ID,
  which the importer uses only to recognize an existing service user.
  """

  alias Ayumi.CSV.Cell
  alias Ayumi.CSV.Columns
  alias Ayumi.Plans.CertificateKind
  alias Ayumi.Plans.EnrollmentStatus
  alias Ayumi.Plans.Gender
  alias Ayumi.Plans.SupportCategory

  @doc "The header row."
  def headers, do: Columns.headers(columns())

  @doc "Renders service users as rows of cells aligned with `headers/0`."
  def dump(service_users), do: Columns.dump(columns(), service_users)

  @doc "Headers the import reads. A file must contain all of them."
  def required_headers, do: Columns.required_headers(columns())

  @doc "Parses one row's cells into attrs, or returns every cell error at once."
  def parse(cells), do: Columns.parse_row(columns(), cells)

  @doc "The header of the column stored under a field; nil when there is none."
  def header_for(key), do: Columns.header_for(columns(), key)

  defp columns do
    [
      {"利用者ID", &Cell.format_id(&1.id), key: :id, parse: &Cell.parse_id/1},
      {"氏名", &Cell.format_text(&1.name), key: :name, parse: &Cell.parse_text/1, required: true},
      text("ふりがな", :name_kana),
      date("生年月日", :birthdate),
      enum("性別", :gender, Gender),
      enum("在籍状態", :enrollment_status, EnrollmentStatus),
      date("利用開始日", :enrollment_start_date),
      text("郵便番号", :postal_code),
      text("住所", :address),
      text("電話番号", :phone),
      text("緊急連絡先氏名", :emergency_contact_name),
      text("緊急連絡先続柄", :emergency_contact_relation),
      text("緊急連絡先電話", :emergency_contact_phone),
      text("受給者証番号", :recipient_cert_number),
      text("支給市町村", :recipient_cert_municipality),
      enum("障害支援区分", :disability_support_category, SupportCategory),
      text("支給量", :benefit_amount),
      date("受給者証有効期限", :recipient_cert_expiry),
      text("通院先", :clinic_name),
      text("主治医", :attending_physician),
      text("服薬・特記", :medication_notes),
      text("相談支援事業所", :consultation_office),
      text("担当相談員", :consultation_staff),
      text("備考", :notes),
      {"障害者手帳", &certificates_summary(&1.disability_certificates)}
    ]
  end

  defp text(header, field) do
    {header, &Cell.format_text(Map.fetch!(&1, field)), key: field, parse: &Cell.parse_text/1}
  end

  defp date(header, field) do
    {header, &Cell.format_date(Map.fetch!(&1, field)), key: field, parse: &Cell.parse_date/1}
  end

  defp enum(header, field, enum_module) do
    {header, &Cell.format_enum(Map.fetch!(&1, field), enum_module),
     key: field, parse: &Cell.parse_enum(&1, enum_module)}
  end

  # One cell for a has_many: certificates joined by " / ", each as its non-blank
  # parts (kind, number, disability name, grade) joined by a space.
  defp certificates_summary(certificates) do
    Enum.map_join(certificates, " / ", fn certificate ->
      [
        CertificateKind.label(certificate.kind),
        certificate.number,
        certificate.disability_name,
        certificate.grade
      ]
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.join(" ")
    end)
  end
end
