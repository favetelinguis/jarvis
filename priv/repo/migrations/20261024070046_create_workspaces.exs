defmodule Jarvis.Repo.Migrations.CreateWorkspaces do
  use Ecto.Migration

  def change do
    create table(:projects) do
      add :key, :text, null: false
      add :name, :text, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:projects, [:key])

    create table(:worktrees) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :path, :text, null: false
      add :name, :text, null: false
      add :branch, :text
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:worktrees, [:path])
    create index(:worktrees, [:project_id])

    create table(:agent_sessions) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :worktree_id, references(:worktrees, on_delete: :delete_all), null: false
      add :pi_session_id, :text, null: false
      add :name, :text
      add :state, :text, null: false, default: "idle"
      add :last_seen_at, :utc_datetime_usec, null: false
      add :inbox_cursor, :bigint, null: false, default: 0
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:agent_sessions, [:pi_session_id])
    create index(:agent_sessions, [:project_id, :last_seen_at])
  end
end
