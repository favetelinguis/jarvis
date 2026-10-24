defmodule Jarvis.Workspaces.Git do
  @moduledoc """
  Finds the project and worktree a directory belongs to.

  All worktrees of a repository share its git common dir, which becomes the
  project key. Directories outside git become a project of their own.
  """

  @type location :: %{
          project_key: String.t(),
          project_name: String.t(),
          worktree_path: String.t(),
          branch: String.t() | nil
        }

  @doc "Resolves `cwd`, which must be an existing absolute directory."
  @spec resolve(String.t()) :: {:ok, location} | {:error, :invalid_cwd}
  def resolve(cwd) when is_binary(cwd) do
    if Path.type(cwd) == :absolute and File.dir?(cwd) do
      {:ok, git(cwd) || plain(cwd)}
    else
      {:error, :invalid_cwd}
    end
  end

  def resolve(_), do: {:error, :invalid_cwd}

  defp git(cwd) do
    case run(cwd, ~w(rev-parse --path-format=absolute --git-common-dir --show-toplevel)) do
      {out, 0} ->
        [common, toplevel] = out |> String.split("\n", trim: true) |> Enum.take(-2)
        key = project_dir(common)

        # symbolic-ref also names the branch of a repository without commits; it fails when detached.
        branch =
          case run(cwd, ~w(symbolic-ref --short -q HEAD)) do
            {name, 0} -> name |> String.split("\n", trim: true) |> List.last()
            _ -> nil
          end

        %{
          project_key: key,
          project_name: key |> Path.basename() |> String.replace_suffix(".git", ""),
          worktree_path: toplevel,
          branch: branch
        }

      _ ->
        nil
    end
  rescue
    # git missing from PATH, or a bare repository without a work tree
    _ -> nil
  end

  defp run(cwd, args), do: System.cmd("git", ["-C", cwd | args], stderr_to_stdout: true)

  # `<repo>/.git` and `<repo>/.bare` name the repository by their parent directory.
  defp project_dir(common) do
    if Path.basename(common) in [".git", ".bare"], do: Path.dirname(common), else: common
  end

  defp plain(cwd) do
    %{project_key: cwd, project_name: Path.basename(cwd), worktree_path: cwd, branch: nil}
  end
end
