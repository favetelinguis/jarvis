defmodule Jarvis.Repo.Migrations.AddPocToGoals do
  use Ecto.Migration

  def up do
    alter table(:goals) do
      add :poc, :boolean, null: false, default: false
    end

    # Every goal that exists today was built without the normal review steps.
    execute "UPDATE goals SET poc = true"
  end

  def down do
    alter table(:goals) do
      remove :poc
    end
  end
end
