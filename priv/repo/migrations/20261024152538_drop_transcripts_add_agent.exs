defmodule Jarvis.Repo.Migrations.DropTranscriptsAddAgent do
  use Ecto.Migration

  def up do
    # The session mirror is gone; this deletes every stored copy of session contents.
    drop table(:transcript_lines)
    drop table(:transcripts)

    alter table(:agent_sessions) do
      add :agent, :text, null: false, default: "pi"
    end
  end

  def down do
    alter table(:agent_sessions) do
      remove :agent
    end

    raise Ecto.MigrationError, "stored transcripts were deleted and cannot be restored"
  end
end
