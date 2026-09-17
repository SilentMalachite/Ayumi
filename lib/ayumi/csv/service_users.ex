defmodule Ayumi.CSV.ServiceUsers do
  @moduledoc """
  CSV layout for the service user master (利用者台帳). Columns follow the
  registration form, top to bottom, under the form's labels. Service users must
  have `:disability_certificates` preloaded.
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

  defp columns do
    [
      {"利用者ID", &Cell.format_id(&1.id)},
      {"氏名", &Cell.format_text(&1.name)},
      {"ふりがな", &Cell.format_text(&1.name_kana)},
      {"生年月日", &Cell.format_date(&1.birthdate)},
      {"性別", &Cell.format_enum(&1.gender, Gender)},
      {"在籍状態", &Cell.format_enum(&1.enrollment_status, EnrollmentStatus)},
      {"利用開始日", &Cell.format_date(&1.enrollment_start_date)},
      {"郵便番号", &Cell.format_text(&1.postal_code)},
      {"住所", &Cell.format_text(&1.address)},
      {"電話番号", &Cell.format_text(&1.phone)},
      {"緊急連絡先氏名", &Cell.format_text(&1.emergency_contact_name)},
      {"緊急連絡先続柄", &Cell.format_text(&1.emergency_contact_relation)},
      {"緊急連絡先電話", &Cell.format_text(&1.emergency_contact_phone)},
      {"受給者証番号", &Cell.format_text(&1.recipient_cert_number)},
      {"支給市町村", &Cell.format_text(&1.recipient_cert_municipality)},
      {"障害支援区分", &Cell.format_enum(&1.disability_support_category, SupportCategory)},
      {"支給量", &Cell.format_text(&1.benefit_amount)},
      {"受給者証有効期限", &Cell.format_date(&1.recipient_cert_expiry)},
      {"通院先", &Cell.format_text(&1.clinic_name)},
      {"主治医", &Cell.format_text(&1.attending_physician)},
      {"服薬・特記", &Cell.format_text(&1.medication_notes)},
      {"相談支援事業所", &Cell.format_text(&1.consultation_office)},
      {"担当相談員", &Cell.format_text(&1.consultation_staff)},
      {"備考", &Cell.format_text(&1.notes)},
      {"障害者手帳", &certificates_summary(&1.disability_certificates)}
    ]
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
