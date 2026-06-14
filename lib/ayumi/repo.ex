defmodule Ayumi.Repo do
  use Ecto.Repo,
    otp_app: :ayumi,
    adapter: Ecto.Adapters.SQLite3
end
