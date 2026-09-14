defmodule VfpMcp.Source.Span do
  @moduledoc """
  Exact half-open byte range within one pair member.
  """

  @enforce_keys [:member, :offset, :length]
  defstruct [:member, :offset, :length]

  @type t :: %__MODULE__{
          member: :dbf | :fpt,
          offset: non_neg_integer(),
          length: non_neg_integer()
        }

  @spec new(:dbf | :fpt, non_neg_integer(), non_neg_integer()) :: t()
  def new(member, offset, length)
      when member in [:dbf, :fpt] and is_integer(offset) and offset >= 0 and
             is_integer(length) and length >= 0 do
    %__MODULE__{member: member, offset: offset, length: length}
  end
end

defmodule VfpMcp.Source.MemoRef do
  @moduledoc """
  Provenance for one DBF memo pointer and its resolved FPT payload.
  """

  alias VfpMcp.Source.Span

  @enforce_keys [:field, :pointer, :pointer_bytes, :pointer_span]
  defstruct [
    :field,
    :pointer,
    :pointer_bytes,
    :pointer_span,
    :block_type,
    :block_span,
    :payload_span,
    :payload_bytes
  ]

  @type t :: %__MODULE__{
          field: String.t(),
          pointer: non_neg_integer(),
          pointer_bytes: binary(),
          pointer_span: Span.t(),
          block_type: non_neg_integer() | nil,
          block_span: Span.t() | nil,
          payload_span: Span.t() | nil,
          payload_bytes: binary() | nil
        }
end
