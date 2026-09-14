defmodule VfpMcp.Acceptance.Evidence do
  @moduledoc """
  Deterministic validation for hash-bound JSON evidence and Markdown signoff.
  """

  # specled covers:
  # - vfp_mcp.acceptance.evidence_bundle_integrity
  # - vfp_mcp.acceptance.version_native_handoff

  alias VfpMcp.Finding
  alias VfpMcp.Source.PairSnapshot

  @schema_version 1
  @hash_pattern ~r/\A[0-9a-f]{64}\z/
  @signoff_marker "<!-- vfp-mcp-native-signoff:v1 -->"

  @required_actions %{
    "fixture_authoring" => ~w(create save close hash review),
    "property_edit" => ~w(open inspect save close reopen compile),
    "method_edit" => ~w(open inspect save close reopen compile)
  }

  @required_record_fields ~w(
    schema_version
    evidence_id
    scenario_id
    vfp_version
    ide_version
    operator
    recorded_at
    outcome
    source_pair
    actions
    observations
    signoff_file
  )

  @type evidence_record :: %{required(String.t()) => term()}
  @type artifacts :: %{
          required(:source_pair) => PairSnapshot.t(),
          optional(:result_pair) => PairSnapshot.t()
        }
  @type result :: {:ok, map()} | {:error, [Finding.t()]}

  @spec decode_json(binary()) :: {:ok, evidence_record()} | {:error, [Finding.t()]}
  def decode_json(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, record} when is_map(record) ->
        {:ok, record}

      {:ok, _other} ->
        {:error, [error(:evidence_invalid_json_root, "JSON root must be an object")]}

      {:error, _reason} ->
        {:error, [error(:evidence_invalid_json, "evidence JSON is invalid")]}
    end
  end

  @spec encode_json(evidence_record()) :: binary()
  def encode_json(record) when is_map(record) do
    Jason.encode!(record, pretty: true) <> "\n"
  end

  @spec validate(evidence_record()) :: result()
  def validate(record) when is_map(record) do
    findings =
      []
      |> validate_required_fields(record)
      |> validate_scalar_fields(record)
      |> validate_scenario(record)
      |> validate_pair(record, "source_pair", true)
      |> validate_result_pair(record)
      |> validate_actions(record)
      |> Enum.sort_by(&{Atom.to_string(&1.code), inspect(&1.evidence)})

    if findings == [], do: {:ok, summary(record)}, else: {:error, findings}
  end

  def validate(_record) do
    {:error, [error(:evidence_invalid_record, "evidence must be a map")]}
  end

  @spec validate_bundle(evidence_record(), binary()) :: result()
  def validate_bundle(record, markdown) when is_map(record) and is_binary(markdown) do
    record_findings = result_findings(validate(record))
    signoff_findings = validate_signoff(record, markdown)
    findings = sort_findings(record_findings ++ signoff_findings)

    if findings == [], do: {:ok, summary(record)}, else: {:error, findings}
  end

  @doc """
  Validates an evidence bundle and binds its declared hashes to pair snapshots.

  Passing snapshots keeps file access outside this pure boundary while proving
  that the evidence describes the exact bytes supplied by the caller.
  """
  @spec validate_bundle(evidence_record(), binary(), artifacts()) :: result()
  def validate_bundle(record, markdown, artifacts)
      when is_map(record) and is_binary(markdown) and is_map(artifacts) do
    record_findings = result_findings(validate(record))
    signoff_findings = validate_signoff(record, markdown)
    artifact_findings = validate_artifacts(record, artifacts)
    findings = sort_findings(record_findings ++ signoff_findings ++ artifact_findings)

    if findings == [], do: {:ok, summary(record)}, else: {:error, findings}
  end

  def validate_bundle(_record, _markdown, _artifacts) do
    {:error, [error(:evidence_invalid_artifacts, "evidence artifacts must be a map")]}
  end

  @doc """
  Creates the JSON representation of a complete source pair from its snapshot.
  """
  @spec pair_record(PairSnapshot.t(), String.t(), String.t()) :: map()
  def pair_record(%PairSnapshot{} = snapshot, dbf_name, fpt_name)
      when is_binary(dbf_name) and is_binary(fpt_name) do
    identity = snapshot.identity

    %{
      "kind" => Atom.to_string(identity.kind),
      "pair_sha256" => identity.pair_sha256,
      "dbf" => %{
        "name" => dbf_name,
        "sha256" => identity.dbf.sha256,
        "bytes" => identity.dbf.byte_size
      },
      "fpt" => %{
        "name" => fpt_name,
        "sha256" => identity.fpt.sha256,
        "bytes" => identity.fpt.byte_size
      }
    }
  end

  @spec summary(evidence_record()) :: map()
  def summary(record) do
    %{
      "evidence_id" => record["evidence_id"],
      "scenario_id" => record["scenario_id"],
      "vfp_version" => record["vfp_version"],
      "outcome" => record["outcome"],
      "source_pair_sha256" => pair_hash(record, "source_pair"),
      "result_pair_sha256" => pair_hash(record, "result_pair"),
      "actions" => action_ids(record["actions"])
    }
  end

  @spec required_actions(String.t()) :: [String.t()]
  def required_actions(scenario_id), do: Map.get(@required_actions, scenario_id, [])

  defp validate_required_fields(findings, record) do
    missing = Enum.reject(@required_record_fields, &Map.has_key?(record, &1))

    Enum.reduce(missing, findings, fn field, acc ->
      [error(:evidence_missing_field, "required evidence field is missing", field: field) | acc]
    end)
  end

  defp validate_scalar_fields(findings, record) do
    findings
    |> add_unless(
      record["schema_version"] == @schema_version,
      :evidence_invalid_schema_version,
      %{
        expected: @schema_version
      }
    )
    |> add_unless(record["vfp_version"] in [6, 9], :evidence_invalid_vfp_version, %{})
    |> add_unless(record["outcome"] in ["pass", "fail"], :evidence_invalid_outcome, %{})
    |> add_unless(non_empty?(record["evidence_id"]), :evidence_invalid_id, %{field: "evidence_id"})
    |> add_unless(non_empty?(record["operator"]), :evidence_invalid_operator, %{})
    |> add_unless(non_empty?(record["ide_version"]), :evidence_invalid_ide_version, %{})
    |> add_unless(valid_timestamp?(record["recorded_at"]), :evidence_invalid_timestamp, %{})
    |> add_unless(non_empty?(record["signoff_file"]), :evidence_invalid_signoff_file, %{})
    |> add_unless(is_map(record["observations"]), :evidence_invalid_observations, %{})
  end

  defp validate_scenario(findings, record) do
    add_unless(
      findings,
      Map.has_key?(@required_actions, record["scenario_id"]),
      :evidence_invalid_scenario,
      %{}
    )
  end

  defp validate_result_pair(findings, record) do
    if record["scenario_id"] in ["property_edit", "method_edit"] do
      validate_pair(findings, record, "result_pair", true)
    else
      validate_pair(findings, record, "result_pair", false)
    end
  end

  defp validate_pair(findings, record, field, required?) do
    pair = record[field]

    cond do
      is_nil(pair) and not required? ->
        findings

      not is_map(pair) ->
        [error(:evidence_incomplete_pair, "pair evidence is incomplete", field: field) | findings]

      true ->
        kind = pair["kind"]
        expected_extensions = if kind == "scx", do: [".scx", ".sct"], else: [".vcx", ".vct"]

        findings
        |> add_unless(kind in ["scx", "vcx"], :evidence_invalid_pair_kind, %{field: field})
        |> validate_artifact(pair["dbf"], field, "dbf", Enum.at(expected_extensions, 0))
        |> validate_artifact(pair["fpt"], field, "fpt", Enum.at(expected_extensions, 1))
        |> add_unless(valid_hash?(pair["pair_sha256"]), :evidence_invalid_hash, %{
          field: "#{field}.pair_sha256"
        })
    end
  end

  defp validate_artifact(findings, artifact, pair_field, role, extension) do
    if is_map(artifact) do
      findings
      |> add_unless(non_empty?(artifact["name"]), :evidence_incomplete_pair, %{
        field: "#{pair_field}.#{role}.name"
      })
      |> add_unless(valid_extension?(artifact["name"], extension), :evidence_invalid_pair_name, %{
        field: "#{pair_field}.#{role}.name"
      })
      |> add_unless(valid_hash?(artifact["sha256"]), :evidence_invalid_hash, %{
        field: "#{pair_field}.#{role}.sha256"
      })
      |> add_unless(valid_size?(artifact["bytes"]), :evidence_invalid_artifact_size, %{
        field: "#{pair_field}.#{role}.bytes"
      })
    else
      [
        error(:evidence_incomplete_pair, "pair member evidence is missing",
          field: "#{pair_field}.#{role}"
        )
        | findings
      ]
    end
  end

  defp validate_actions(findings, record) do
    actions = record["actions"]

    if is_list(actions) do
      required = required_actions(record["scenario_id"])

      findings = validate_action_collection(findings, actions)

      Enum.reduce(required, findings, fn id, acc ->
        action = Enum.find(actions, fn action -> is_map(action) and action["id"] == id end)

        cond do
          is_nil(action) ->
            [error(:evidence_missing_action, "required action is missing", action: id) | acc]

          action["outcome"] not in ["pass", "fail"] ->
            [error(:evidence_invalid_action, "action outcome is invalid", action: id) | acc]

          record["outcome"] == "pass" and action["outcome"] != "pass" ->
            [
              error(:evidence_failed_required_action, "passing evidence has a failed action",
                action: id
              )
              | acc
            ]

          not non_empty?(action["observation"]) ->
            [error(:evidence_invalid_action, "action observation is missing", action: id) | acc]

          true ->
            acc
        end
      end)
    else
      [error(:evidence_invalid_actions, "actions must be a list") | findings]
    end
  end

  defp validate_action_collection(findings, actions) do
    valid_actions =
      Enum.filter(actions, fn action ->
        is_map(action) and non_empty?(action["id"])
      end)

    findings =
      add_unless(
        findings,
        length(valid_actions) == length(actions),
        :evidence_invalid_action,
        %{reason: "action entries must be objects with ids"}
      )

    ids = Enum.map(valid_actions, & &1["id"])

    add_unless(
      findings,
      length(ids) == length(Enum.uniq(ids)),
      :evidence_invalid_action,
      %{reason: "action ids must be unique"}
    )
  end

  defp validate_signoff(record, markdown) do
    expected_result = pair_hash(record, "result_pair") || "none"

    expected = %{
      "Evidence ID" => record["evidence_id"],
      "Source pair SHA-256" => pair_hash(record, "source_pair"),
      "Result pair SHA-256" => expected_result
    }

    findings =
      if String.contains?(markdown, @signoff_marker) do
        []
      else
        [error(:evidence_invalid_signoff, "signoff version marker is missing")]
      end

    findings =
      Enum.reduce(expected, findings, fn {label, value}, acc ->
        if signoff_value(markdown, label) == value do
          acc
        else
          [
            error(:evidence_signoff_mismatch, "signoff does not match JSON evidence",
              field: label
            )
            | acc
          ]
        end
      end)

    findings =
      findings
      |> add_unless(non_empty?(signoff_value(markdown, "Reviewer")), :evidence_invalid_signoff, %{
        field: "Reviewer"
      })
      |> add_unless(
        valid_timestamp?(signoff_value(markdown, "Reviewed at")),
        :evidence_invalid_signoff,
        %{
          field: "Reviewed at"
        }
      )

    unchecked = Regex.scan(~r/^- \[ \] /m, markdown) |> length()
    checked = Regex.scan(~r/^- \[[xX]\] /m, markdown) |> length()

    findings
    |> add_unless(unchecked == 0, :evidence_signoff_unchecked, %{unchecked: unchecked})
    |> add_unless(checked >= 6, :evidence_signoff_incomplete, %{checked: checked})
  end

  defp validate_artifacts(record, artifacts) do
    required =
      if record["scenario_id"] in ["property_edit", "method_edit"] do
        [:source_pair, :result_pair]
      else
        [:source_pair]
      end

    Enum.reduce(required, [], fn role, findings ->
      field = Atom.to_string(role)

      case artifact(artifacts, role) do
        %PairSnapshot{} = snapshot ->
          compare_snapshot(findings, record, field, snapshot)

        nil ->
          [
            error(:evidence_artifact_missing, "required pair snapshot is missing", field: field)
            | findings
          ]

        _other ->
          [
            error(:evidence_invalid_artifacts, "evidence artifact is not a pair snapshot",
              field: field
            )
            | findings
          ]
      end
    end)
  end

  defp compare_snapshot(findings, record, field, snapshot) do
    pair = record[field]

    if PairSnapshot.validate(snapshot) == :ok and is_map(pair) do
      identity = snapshot.identity

      comparisons = [
        {"#{field}.kind", pair["kind"], Atom.to_string(identity.kind)},
        {"#{field}.pair_sha256", pair["pair_sha256"], identity.pair_sha256},
        {"#{field}.dbf.sha256", nested_value(pair, "dbf", "sha256"), identity.dbf.sha256},
        {"#{field}.dbf.bytes", nested_value(pair, "dbf", "bytes"), identity.dbf.byte_size},
        {"#{field}.fpt.sha256", nested_value(pair, "fpt", "sha256"), identity.fpt.sha256},
        {"#{field}.fpt.bytes", nested_value(pair, "fpt", "bytes"), identity.fpt.byte_size},
        {"#{field}.vfp_version", record["vfp_version"], identity.declared_vfp_version}
      ]

      Enum.reduce(comparisons, findings, fn {path, declared, actual}, acc ->
        if declared == actual do
          acc
        else
          [
            error(:evidence_artifact_mismatch, "evidence does not match supplied pair bytes",
              field: path,
              declared: declared,
              actual: actual
            )
            | acc
          ]
        end
      end)
    else
      [
        error(:evidence_artifact_mismatch, "evidence pair snapshot is incomplete or invalid",
          field: field
        )
        | findings
      ]
    end
  end

  defp artifact(artifacts, role) do
    Map.get(artifacts, role) || Map.get(artifacts, Atom.to_string(role))
  end

  defp nested_value(map, outer, inner) do
    case map[outer] do
      nested when is_map(nested) -> nested[inner]
      _other -> nil
    end
  end

  defp signoff_value(markdown, label) do
    escaped = Regex.escape(label)

    case Regex.run(~r/^- #{escaped}: `([^`]*)`\s*$/m, markdown) do
      [_, value] -> value
      _missing -> nil
    end
  end

  defp result_findings({:ok, _summary}), do: []
  defp result_findings({:error, findings}), do: findings

  defp sort_findings(findings) do
    Enum.sort_by(findings, &{Atom.to_string(&1.code), inspect(&1.evidence)})
  end

  defp add_unless(findings, true, _code, _evidence), do: findings

  defp add_unless(findings, false, code, evidence) do
    [error(code, "evidence validation failed", evidence) | findings]
  end

  defp error(code, message, evidence \\ %{}) do
    normalized_evidence = if is_list(evidence), do: Map.new(evidence), else: evidence
    Finding.new(code, :error, :mutation_blocked, message, evidence: normalized_evidence)
  end

  defp non_empty?(value), do: is_binary(value) and String.trim(value) != ""

  defp pair_hash(record, field) when is_map(record) do
    case record[field] do
      pair when is_map(pair) -> pair["pair_sha256"]
      _other -> nil
    end
  end

  defp action_ids(actions) when is_list(actions) do
    actions
    |> Enum.filter(&is_map/1)
    |> Enum.map(& &1["id"])
  end

  defp action_ids(_actions), do: []

  defp valid_hash?(value), do: is_binary(value) and Regex.match?(@hash_pattern, value)
  defp valid_size?(value), do: is_integer(value) and value >= 0

  defp valid_extension?(name, extension) when is_binary(name) do
    String.downcase(Path.extname(name)) == extension
  end

  defp valid_extension?(_name, _extension), do: false

  defp valid_timestamp?(value) when is_binary(value) do
    match?({:ok, _datetime, _offset}, DateTime.from_iso8601(value))
  end

  defp valid_timestamp?(_value), do: false
end
