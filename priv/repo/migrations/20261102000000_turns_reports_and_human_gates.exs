defmodule Jarvis.Repo.Migrations.TurnsReportsAndHumanGates do
  @moduledoc """
  Whose turn it is in a task, the human's quiz skip and view of a pull request,
  moves as messages to the listening session, and turn reports. The Feature
  step Review is now Acceptance; PR reviews already past the quiz keep showing
  their findings without asking for the human's view.
  """
  use Ecto.Migration

  def up do
    alter table(:tasks) do
      add :turn, :text
      add :quiz_skipped, :boolean, null: false, default: false
      add :picture, :map, null: false, default: %{}
    end

    alter table(:comments) do
      add :transition, :text
      add :to_step, :text
    end

    alter table(:agent_sessions) do
      add :turn, :integer, null: false, default: 0
    end

    create table(:reports) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :goal_id, references(:goals, on_delete: :delete_all), null: false
      add :task_id, references(:tasks, on_delete: :delete_all)
      add :agent_session_id, references(:agent_sessions, on_delete: :nilify_all)
      add :turn, :integer, null: false
      add :entries, :map, null: false, default: %{}
      add :needs, :text
      add :closed_at, :utc_datetime_usec
      add :read_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create index(:reports, [:goal_id, :task_id])
    create index(:reports, [:agent_session_id, :turn])

    execute "UPDATE tasks SET step = 'acceptance' WHERE type = 'feature' AND step = 'review'"

    execute "UPDATE tasks SET previous_step = 'acceptance' WHERE type = 'feature' AND previous_step = 'review'"

    execute """
    UPDATE tasks SET picture = '{"state":"not_asked"}'
    WHERE type = 'pr_review' AND step IN ('findings', 'done')
    """
  end

  def down do
    execute "UPDATE tasks SET step = 'review' WHERE type = 'feature' AND step = 'acceptance'"
    drop table(:reports)

    alter table(:agent_sessions) do
      remove :turn
    end

    alter table(:comments) do
      remove :transition
      remove :to_step
    end

    alter table(:tasks) do
      remove :turn
      remove :quiz_skipped
      remove :picture
    end
  end
end
