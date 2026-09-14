defmodule VfpMcp.Acceptance.FixtureSafety do
  @moduledoc """
  Pure validation of the safety-relevant fields in a fixture inventory.

  Inventory extraction belongs to the intake tooling and, later, the codec.
  This boundary accepts only already-extracted values, performs no file access,
  and never opens, compiles, or executes Visual FoxPro source.
  """

  # specled covers:
  # - vfp_mcp.acceptance.no_live_dependencies
  # - vfp_mcp.acceptance.fixture_review
  # - vfp_mcp.acceptance.phase1_safe_foundation

  alias VfpMcp.Finding

  @required_fields ~w(kind dbf_member fpt_member data_bindings class_locations commands path_references)a

  @type inventory :: %{
          required(:kind) => :scx | :vcx,
          required(:dbf_member) => String.t(),
          required(:fpt_member) => String.t(),
          required(:data_bindings) => [String.t()],
          required(:class_locations) => [String.t()],
          required(:commands) => [String.t()],
          required(:path_references) => [String.t()]
        }

  @spec validate(inventory() | map()) :: :ok | {:error, [Finding.t()]}
  def validate(inventory) when is_map(inventory) do
    findings =
      []
      |> validate_shape(inventory)
      |> validate_pair(inventory)
      |> reject_values(inventory, :data_bindings, :fixture_data_binding)
      |> reject_values(inventory, :class_locations, :fixture_external_classloc)
      |> reject_values(inventory, :commands, :fixture_data_command)
      |> reject_values(inventory, :path_references, :fixture_external_path)
      |> Enum.sort_by(&{Atom.to_string(&1.code), inspect(&1.evidence)})

    if findings == [], do: :ok, else: {:error, findings}
  end

  def validate(_inventory) do
    {:error, [error(:fixture_invalid_inventory, "fixture inventory must be a map")]}
  end

  defp validate_shape(findings, inventory) do
    Enum.reduce(@required_fields, findings, fn field, acc ->
      if Map.has_key?(inventory, field) do
        acc
      else
        [
          error(:fixture_invalid_inventory, "fixture inventory field is missing", field: field)
          | acc
        ]
      end
    end)
  end

  defp validate_pair(findings, inventory) do
    kind = inventory[:kind]
    dbf_member = inventory[:dbf_member]
    fpt_member = inventory[:fpt_member]

    cond do
      kind not in [:scx, :vcx] ->
        [error(:fixture_invalid_pair_kind, "fixture pair kind must be SCX or VCX") | findings]

      not non_empty?(dbf_member) or not non_empty?(fpt_member) ->
        [error(:fixture_pair_incomplete, "both fixture pair members are required") | findings]

      not matching_pair?(kind, dbf_member, fpt_member) ->
        [
          error(:fixture_pair_mismatch, "fixture pair names or extensions do not match",
            dbf_member: dbf_member,
            fpt_member: fpt_member
          )
          | findings
        ]

      true ->
        findings
    end
  end

  defp reject_values(findings, inventory, field, code) do
    case inventory[field] do
      values when is_list(values) ->
        values
        |> Enum.filter(&non_empty?/1)
        |> Enum.reduce(findings, fn value, acc ->
          [
            error(code, "fixture inventory contains a prohibited live dependency",
              field: field,
              value: value
            )
            | acc
          ]
        end)

      nil ->
        findings

      _other ->
        [
          error(:fixture_invalid_inventory, "fixture inventory values must be lists",
            field: field
          )
          | findings
        ]
    end
  end

  defp matching_pair?(kind, dbf_member, fpt_member) do
    {dbf_extension, fpt_extension} =
      case kind do
        :scx -> {".scx", ".sct"}
        :vcx -> {".vcx", ".vct"}
      end

    String.downcase(Path.extname(dbf_member)) == dbf_extension and
      String.downcase(Path.extname(fpt_member)) == fpt_extension and
      String.downcase(Path.rootname(Path.basename(dbf_member))) ==
        String.downcase(Path.rootname(Path.basename(fpt_member)))
  end

  defp non_empty?(value), do: is_binary(value) and String.trim(value) != ""

  defp error(code, message, evidence \\ []) do
    Finding.new(code, :error, :mutation_blocked, message, evidence: Map.new(evidence))
  end
end
