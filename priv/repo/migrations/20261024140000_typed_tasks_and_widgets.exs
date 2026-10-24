defmodule Jarvis.Repo.Migrations.TypedTasksAndWidgets do
  @moduledoc """
  Goal 3: tasks get a type and a lifecycle step, and goal and task sections
  become widgets. A clean break: every goal, task, comment, and event is
  dropped. Projects, worktrees, sessions, and transcripts stay.
  """
  use Ecto.Migration

  def up do
    alter table(:agent_sessions) do
      remove :task_id
    end

    drop table(:events)
    drop table(:comments)
    drop table(:tasks)
    drop table(:goals)

    create table(:goals) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :number, :integer, null: false
      add :title, :text, null: false
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

    alter table(:agent_sessions) do
      add :task_id, references(:tasks, on_delete: :nilify_all)
    end

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

  def down, do: raise(Ecto.MigrationError, "Goal 3 dropped the old planning data; no way back")
end
