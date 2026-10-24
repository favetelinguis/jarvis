defmodule Jarvis.Repo.Migrations.CreateSchema do
  @moduledoc """
  The whole schema in one step, for SQLite. The PostgreSQL migrations that came
  before it are gone: their data is not carried over.
  """
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

    create table(:goals) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :number, :integer, null: false
      add :title, :text, null: false
      add :poc, :boolean, null: false, default: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:goals, [:project_id, :number])

    create table(:tasks) do
      add :goal_id, references(:goals, on_delete: :delete_all), null: false
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :worktree_id, references(:worktrees, on_delete: :nilify_all)
      add :number, :integer, null: false
      add :title, :text, null: false
      add :type, :text, null: false
      add :step, :text, null: false
      add :previous_step, :text
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:tasks, [:goal_id, :number])
    create index(:tasks, [:project_id])

    create table(:agent_sessions) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :worktree_id, references(:worktrees, on_delete: :delete_all), null: false
      add :task_id, references(:tasks, on_delete: :nilify_all)
      add :pi_session_id, :text, null: false
      add :agent, :text, null: false, default: "pi"
      add :name, :text
      add :state, :text, null: false, default: "idle"
      add :last_seen_at, :utc_datetime_usec, null: false
      add :inbox_cursor, :bigint, null: false, default: 0
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:agent_sessions, [:pi_session_id])
    create index(:agent_sessions, [:project_id, :last_seen_at])

    create table(:widgets) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :goal_id, references(:goals, on_delete: :delete_all), null: false
      add :task_id, references(:tasks, on_delete: :delete_all)
      add :section, :text, null: false
      add :position, :integer, null: false
      add :kind, :text, null: false
      add :data, :map, null: false, default: %{}
      add :human, :map, null: false, default: %{}
      timestamps(type: :utc_datetime_usec)
    end

    create index(:widgets, [:goal_id, :task_id, :section, :position])

    create table(:comments) do
      add :goal_id, references(:goals, on_delete: :delete_all), null: false
      add :task_id, references(:tasks, on_delete: :delete_all)
      add :agent_session_id, references(:agent_sessions, on_delete: :nilify_all)
      add :widget_id, references(:widgets, on_delete: :nilify_all)
      add :reply_to_id, references(:comments, on_delete: :nilify_all)
      add :author, :text, null: false
      add :body, :text, null: false
      add :part, :text
      add :anchor_label, :text
      add :anchor_text, :text
      add :deliver, :boolean, null: false, default: false
      add :delivered_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:comments, [:goal_id])
    create index(:comments, [:task_id])
    create index(:comments, [:widget_id])

    create table(:events) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :goal_id, references(:goals, on_delete: :delete_all)
      add :task_id, references(:tasks, on_delete: :delete_all)
      add :agent_session_id, references(:agent_sessions, on_delete: :nilify_all)
      add :actor, :text, null: false
      add :summary, :text, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:events, [:project_id, :inserted_at])

    create table(:settings, primary_key: false) do
      add :key, :text, primary_key: true
      add :value, :map, null: false
      timestamps(type: :utc_datetime_usec)
    end
  end
end
