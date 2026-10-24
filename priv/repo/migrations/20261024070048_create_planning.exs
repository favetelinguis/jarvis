defmodule Jarvis.Repo.Migrations.CreatePlanning do
  use Ecto.Migration

  def change do
    create table(:goals) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :number, :integer, null: false
      add :title, :text, null: false
      add :intent, :text
      add :scope, :text
      add :glossary, :text
      add :decisions, :text
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:goals, [:project_id, :number])

    create table(:tasks) do
      add :goal_id, references(:goals, on_delete: :delete_all), null: false
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :worktree_id, references(:worktrees, on_delete: :nilify_all)
      add :number, :integer, null: false
      add :title, :text, null: false
      add :status, :text, null: false, default: "todo"

      for field <- ~w(intent requirements examples constraints assumptions out_of_scope
                      open_questions sketch tests)a do
        add field, :text
      end

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:tasks, [:goal_id, :number])
    create index(:tasks, [:project_id])

    alter table(:agent_sessions) do
      add :task_id, references(:tasks, on_delete: :nilify_all)
    end

    create table(:comments) do
      add :goal_id, references(:goals, on_delete: :delete_all), null: false
      add :task_id, references(:tasks, on_delete: :delete_all)
      add :agent_session_id, references(:agent_sessions, on_delete: :nilify_all)
      add :author, :text, null: false
      add :body, :text, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:comments, [:goal_id])
    create index(:comments, [:task_id])

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
  end
end
