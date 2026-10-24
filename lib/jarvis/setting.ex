defmodule Jarvis.Setting do
  @moduledoc "A global setting of the Jarvis install, stored as a JSON value under a key."
  use Ecto.Schema

  @primary_key {:key, :string, autogenerate: false}
  schema "settings" do
    field :value, :map
    timestamps(type: :utc_datetime_usec)
  end
end
