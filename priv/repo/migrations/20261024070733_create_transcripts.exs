defmodule Jarvis.Repo.Migrations.CreateTranscripts do
  use Ecto.Migration

  def change do
    create table(:transcripts) do
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      add :worktree_id, references(:worktrees, on_delete: :nilify_all)
      add :harness, :text, null: false
      add :external_id, :text, null: false
      add :path, :text, null: false
      add :cwd, :text, null: false
      add :title, :text
      add :line_count, :integer, null: false, default: 0
      add :byte_offset, :bigint, null: false, default: 0
      add :last_line_offset, :bigint, null: false, default: 0
      add :last_line_hash, :binary
      add :last_entry_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:transcripts, [:harness, :external_id])
    create index(:transcripts, [:project_id, :updated_at])

    create table(:transcript_lines, primary_key: false) do
      add :transcript_id, references(:transcripts, on_delete: :delete_all), primary_key: true
      add :seq, :integer, primary_key: true
      add :line, :text, null: false
      add :role, :text, null: false
      add :text, :text
      add :at, :utc_datetime_usec
    end
  end
end
