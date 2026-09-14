defmodule VfpMcp.SemanticValue do
  @moduledoc "A decoded semantic value with exact physical provenance."

  alias VfpMcp.Source.{MemoRef, Span}

  @enforce_keys [:field, :value, :raw_bytes, :span]
  defstruct [:field, :value, :raw_bytes, :span, :field_index, :memo_ref]

  @type t :: %__MODULE__{
          field: String.t(),
          value: String.t(),
          raw_bytes: binary(),
          span: Span.t(),
          field_index: non_neg_integer() | nil,
          memo_ref: MemoRef.t() | nil
        }
end

defmodule VfpMcp.SemanticRecord do
  @moduledoc "A conservative classification of one physical source record."

  alias VfpMcp.Codec.Dbf
  alias VfpMcp.SemanticValue
  alias VfpMcp.Source.{MemoRef, Span}

  @enforce_keys [
    :semantic_index,
    :record_index,
    :category,
    :physical_record,
    :raw_fields,
    :memo_refs,
    :spans
  ]
  defstruct @enforce_keys ++ [identity_fields: %{}]

  @type category ::
          :object
          | :data_environment
          | :data_environment_entry
          | :bookend_open
          | :bookend_close
          | :comment
          | :unknown

  @type t :: %__MODULE__{
          semantic_index: non_neg_integer(),
          record_index: non_neg_integer(),
          category: category(),
          physical_record: Dbf.Record.t(),
          identity_fields: %{optional(atom()) => SemanticValue.t()},
          raw_fields: [Dbf.FieldValue.t()],
          memo_refs: [MemoRef.t()],
          spans: [Span.t()]
        }
end

defmodule VfpMcp.SourceObject do
  @moduledoc """
  Semantic object with retained physical provenance.
  """

  alias VfpMcp.SemanticValue
  alias VfpMcp.Source.{MemoRef, Span}

  @enforce_keys [:record_index]
  defstruct [
    :semantic_index,
    :record_index,
    :category,
    :active?,
    :path,
    :parent_record_index,
    :edit_eligibility,
    :property_memo,
    :method_memo,
    identity_fields: %{},
    raw_fields: [],
    properties: [],
    methods: [],
    memo_refs: [],
    spans: []
  ]

  @type t :: %__MODULE__{
          semantic_index: non_neg_integer(),
          record_index: non_neg_integer(),
          category: VfpMcp.SemanticRecord.category(),
          active?: boolean() | nil,
          path: String.t() | nil,
          parent_record_index: non_neg_integer() | nil,
          edit_eligibility: :eligible | {:blocked, [atom()]} | nil,
          property_memo: VfpMcp.Codec.Properties.Memo.t() | nil,
          method_memo: VfpMcp.Codec.Methods.Memo.t() | nil,
          identity_fields: %{optional(atom()) => SemanticValue.t()},
          raw_fields: [VfpMcp.Codec.Dbf.FieldValue.t()],
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

  alias VfpMcp.{Finding, SemanticRecord, SourceObject}
  alias VfpMcp.Source.PairIdentity

  @enforce_keys [:pair, :physical]
  defstruct [
    :pair,
    :physical,
    :version,
    :encoding,
    schema: [],
    records: [],
    semantic_records: [],
    objects: [],
    data_environment: [],
    tree: %{},
    path_index: %{},
    findings: [],
    inspectability: :inspectable,
    edit_eligibility: :eligible
  ]

  @type t :: %__MODULE__{
          pair: PairIdentity.t(),
          physical: map(),
          version: 6 | 9 | nil,
          encoding: atom() | nil,
          schema: [map()],
          records: [map()],
          semantic_records: [SemanticRecord.t()],
          objects: [SourceObject.t()],
          data_environment: [SemanticRecord.t()],
          tree: map(),
          path_index: %{optional(String.t()) => SourceObject.t()},
          findings: [Finding.t()],
          inspectability: :inspectable,
          edit_eligibility: :eligible | {:blocked, [atom()]}
        }
end
