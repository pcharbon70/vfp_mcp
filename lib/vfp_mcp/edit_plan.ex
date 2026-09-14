defmodule VfpMcp.EditPlan.BytePatch do
  @moduledoc """
  Exact before/after replacement at one DBF byte range.
  """

  @enforce_keys [:offset, :before, :after, :reason]
  defstruct [:offset, :before, :after, :reason]

  @type t :: %__MODULE__{
          offset: non_neg_integer(),
          before: binary(),
          after: binary(),
          reason: atom()
        }
end

defmodule VfpMcp.EditPlan.MemoAppend do
  @moduledoc """
  Planned aligned bytes appended to the companion FPT member.
  """

  @enforce_keys [:offset, :bytes, :block_type, :block_size]
  defstruct [:offset, :bytes, :block_type, :block_size]

  @type t :: %__MODULE__{
          offset: non_neg_integer(),
          bytes: binary(),
          block_type: non_neg_integer(),
          block_size: pos_integer()
        }
end

defmodule VfpMcp.EditPlan.Postcondition do
  @moduledoc """
  Semantic assertion that must hold after pure materialization and reparse.
  """

  @enforce_keys [:kind, :target, :expected]
  defstruct [:kind, :target, :expected]

  @type t :: %__MODULE__{
          kind: :property | :method,
          target: map(),
          expected: term()
        }
end

defmodule VfpMcp.EditPlan do
  @moduledoc """
  Pure, source-bound result of a future property or method planner.

  The structure contains data only. Production locking, backup, journaling,
  filesystem replacement, and rollback belong to a later milestone.
  """

  # specled covers:
  # - vfp_mcp.codec.pure_planning

  alias VfpMcp.EditPlan.{BytePatch, MemoAppend, Postcondition}
  alias VfpMcp.Finding
  alias VfpMcp.Source.{PairIdentity, Span}

  @enforce_keys [:source_identity, :postcondition]
  defstruct [
    :source_identity,
    :postcondition,
    dbf_patches: [],
    memo_appends: [],
    expected_footprint: %{dbf: [], fpt: []},
    findings: []
  ]

  @type t :: %__MODULE__{
          source_identity: PairIdentity.t(),
          postcondition: Postcondition.t(),
          dbf_patches: [BytePatch.t()],
          memo_appends: [MemoAppend.t()],
          expected_footprint: %{dbf: [Span.t()], fpt: [Span.t()]},
          findings: [Finding.t()]
        }

  @spec new(PairIdentity.t(), Postcondition.t(), keyword()) :: t()
  def new(%PairIdentity{} = source_identity, %Postcondition{} = postcondition, opts \\ []) do
    struct!(__MODULE__,
      source_identity: source_identity,
      postcondition: postcondition,
      dbf_patches: Keyword.get(opts, :dbf_patches, []),
      memo_appends: Keyword.get(opts, :memo_appends, []),
      expected_footprint: Keyword.get(opts, :expected_footprint, %{dbf: [], fpt: []}),
      findings: Keyword.get(opts, :findings, [])
    )
  end
end
