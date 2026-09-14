defmodule VfpMcp.Limits do
  @moduledoc """
  Resource limits shared by pure parsers, validators, and planners.
  """

  # specled covers:
  # - vfp_mcp.codec.pure_planning

  alias VfpMcp.Finding

  @defaults [
    member_bytes: 64 * 1024 * 1024,
    records: 100_000,
    fields: 256,
    memo_payload_bytes: 16 * 1024 * 1024,
    memo_blocks: 100_000,
    findings: 1_000,
    hierarchy_depth: 256,
    parsed_text_bytes: 16 * 1024 * 1024
  ]

  @keys Keyword.keys(@defaults)

  defstruct @defaults

  @type key ::
          :member_bytes
          | :records
          | :fields
          | :memo_payload_bytes
          | :memo_blocks
          | :findings
          | :hierarchy_depth
          | :parsed_text_bytes

  @type t :: %__MODULE__{
          member_bytes: pos_integer(),
          records: pos_integer(),
          fields: pos_integer(),
          memo_payload_bytes: pos_integer(),
          memo_blocks: pos_integer(),
          findings: pos_integer(),
          hierarchy_depth: pos_integer(),
          parsed_text_bytes: pos_integer()
        }

  @spec keys() :: [key()]
  def keys, do: @keys

  @spec new(keyword()) :: {:ok, t()} | {:error, :invalid_limits}
  def new(overrides \\ []) when is_list(overrides) do
    with {:ok, values} <- Keyword.validate(overrides, @defaults),
         true <- Enum.all?(values, fn {_key, value} -> is_integer(value) and value > 0 end) do
      {:ok, struct!(__MODULE__, values)}
    else
      _error -> {:error, :invalid_limits}
    end
  end

  @spec new!(keyword()) :: t()
  def new!(overrides \\ []) do
    case new(overrides) do
      {:ok, limits} -> limits
      {:error, :invalid_limits} -> raise ArgumentError, "limits must be known positive integers"
    end
  end

  @spec check(t(), key(), non_neg_integer(), VfpMcp.Finding.location()) ::
          :ok | {:error, Finding.t()}
  def check(%__MODULE__{} = limits, key, actual, location \\ nil)
      when key in @keys and is_integer(actual) and actual >= 0 do
    maximum = Map.fetch!(limits, key)

    if actual <= maximum do
      :ok
    else
      {:error,
       Finding.fatal(exceeded_code(key), "#{key} limit exceeded",
         location: location,
         evidence: %{actual: actual, maximum: maximum}
       )}
    end
  end

  @spec exceeded_code(key()) :: atom()
  def exceeded_code(:member_bytes), do: :limit_member_bytes_exceeded
  def exceeded_code(:records), do: :limit_records_exceeded
  def exceeded_code(:fields), do: :limit_fields_exceeded
  def exceeded_code(:memo_payload_bytes), do: :limit_memo_payload_bytes_exceeded
  def exceeded_code(:memo_blocks), do: :limit_memo_blocks_exceeded
  def exceeded_code(:findings), do: :limit_findings_exceeded
  def exceeded_code(:hierarchy_depth), do: :limit_hierarchy_depth_exceeded
  def exceeded_code(:parsed_text_bytes), do: :limit_parsed_text_bytes_exceeded
end
