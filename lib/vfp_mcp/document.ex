defmodule VfpMcp.SourceObject do
  @moduledoc """
  Semantic object with retained physical provenance.
  """

  alias VfpMcp.Source.{MemoRef, Span}

  @enforce_keys [:record_index]
  defstruct [
    :record_index,
    :path,
    identity_fields: %{},
    raw_fields: %{},
    properties: [],
    methods: [],
    memo_refs: [],
    spans: []
  ]

  @type t :: %__MODULE__{
          record_index: non_neg_integer(),
          path: String.t() | nil,
          identity_fields: map(),
          raw_fields: map(),
          properties: [map()],
          methods: [map()],
          memo_refs: [MemoRef.t()],
          spans: [Span.t()]
        }
end

defmodule VfpMcp.Document do
  @moduledoc """
  Semantic Visual FoxPro document retaining its physical source model.

  Successful codec results own non-fatal findings in this structure. Fatal
  findings are returned by the codec error tuple instead.
  """

  # specled covers:
  # - vfp_mcp.codec.semantic_document
  # - vfp_mcp.codec.pure_planning

  alias VfpMcp.{Finding, SourceObject}
  alias VfpMcp.Source.PairIdentity

  @enforce_keys [:pair, :physical]
  defstruct [
    :pair,
    :physical,
    :version,
    :encoding,
    schema: [],
    records: [],
    objects: [],
    tree: %{},
    path_index: %{},
    findings: []
  ]

  @type t :: %__MODULE__{
          pair: PairIdentity.t(),
          physical: map(),
          version: 6 | 9 | nil,
          encoding: atom() | nil,
          schema: [map()],
          records: [map()],
          objects: [SourceObject.t()],
          tree: map(),
          path_index: %{optional(String.t()) => SourceObject.t()},
          findings: [Finding.t()]
        }
end
