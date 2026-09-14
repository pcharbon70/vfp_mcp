defmodule VfpMcp.Source.MemberIdentity do
  @moduledoc """
  Identity of one immutable DBF or FPT member supplied by a caller.
  """

  @enforce_keys [:role, :byte_size, :sha256]
  defstruct [:role, :path, :modified_at, :byte_size, :sha256]

  @type t :: %__MODULE__{
          role: :dbf | :fpt,
          path: Path.t() | nil,
          modified_at: DateTime.t() | nil,
          byte_size: non_neg_integer(),
          sha256: String.t()
        }
end

defmodule VfpMcp.Source.PairIdentity do
  @moduledoc """
  Logical and content identity for a complete Visual FoxPro source pair.
  """

  alias VfpMcp.Source.MemberIdentity

  @enforce_keys [:source_id, :kind, :pair_sha256, :dbf, :fpt]
  defstruct [:source_id, :kind, :declared_vfp_version, :pair_sha256, :dbf, :fpt]

  @type t :: %__MODULE__{
          source_id: String.t(),
          kind: :scx | :vcx,
          declared_vfp_version: 6 | 9 | nil,
          pair_sha256: String.t(),
          dbf: MemberIdentity.t(),
          fpt: MemberIdentity.t()
        }
end

defmodule VfpMcp.Source.PairSnapshot do
  @moduledoc """
  Immutable caller-supplied bytes and their complete pair identity.
  """

  # specled covers:
  # - vfp_mcp.read.immutable_snapshot
  # - vfp_mcp.codec.pure_planning

  alias VfpMcp.Source.{MemberIdentity, PairIdentity}

  @enforce_keys [:identity, :dbf_bytes, :fpt_bytes]
  defstruct [:identity, :dbf_bytes, :fpt_bytes]

  @type t :: %__MODULE__{
          identity: PairIdentity.t(),
          dbf_bytes: binary(),
          fpt_bytes: binary()
        }

  @type create_error :: :invalid_kind | :invalid_source_id | :invalid_bytes | :invalid_version

  @spec new(:scx | :vcx, String.t(), binary(), binary(), keyword()) ::
          {:ok, t()} | {:error, create_error()}
  def new(kind, source_id, dbf_bytes, fpt_bytes, opts \\ [])

  def new(kind, source_id, dbf_bytes, fpt_bytes, opts)
      when kind in [:scx, :vcx] and is_binary(source_id) and source_id != "" and
             is_binary(dbf_bytes) and is_binary(fpt_bytes) and is_list(opts) do
    version = Keyword.get(opts, :declared_vfp_version)

    if version in [nil, 6, 9] do
      dbf = member_identity(:dbf, dbf_bytes, opts)
      fpt = member_identity(:fpt, fpt_bytes, opts)

      identity = %PairIdentity{
        source_id: source_id,
        kind: kind,
        declared_vfp_version: version,
        pair_sha256: pair_hash(kind, dbf_bytes, fpt_bytes),
        dbf: dbf,
        fpt: fpt
      }

      {:ok, %__MODULE__{identity: identity, dbf_bytes: dbf_bytes, fpt_bytes: fpt_bytes}}
    else
      {:error, :invalid_version}
    end
  end

  def new(kind, _source_id, _dbf_bytes, _fpt_bytes, _opts) when kind not in [:scx, :vcx],
    do: {:error, :invalid_kind}

  def new(_kind, source_id, _dbf_bytes, _fpt_bytes, _opts)
      when not is_binary(source_id) or source_id == "",
      do: {:error, :invalid_source_id}

  def new(_kind, _source_id, _dbf_bytes, _fpt_bytes, _opts), do: {:error, :invalid_bytes}

  @spec validate(t()) ::
          :ok | {:error, :snapshot_identity_mismatch | :pair_member_extension_mismatch}
  def validate(%__MODULE__{
        identity: %PairIdentity{dbf: %MemberIdentity{}, fpt: %MemberIdentity{}} = identity,
        dbf_bytes: dbf_bytes,
        fpt_bytes: fpt_bytes
      })
      when is_binary(dbf_bytes) and is_binary(fpt_bytes) and identity.kind in [:scx, :vcx] do
    expected_dbf = hash(dbf_bytes)
    expected_fpt = hash(fpt_bytes)
    expected_pair = pair_hash(identity.kind, dbf_bytes, fpt_bytes)

    valid? =
      identity.dbf.role == :dbf and
        identity.dbf.byte_size == byte_size(dbf_bytes) and
        identity.dbf.sha256 == expected_dbf and
        identity.fpt.role == :fpt and
        identity.fpt.byte_size == byte_size(fpt_bytes) and
        identity.fpt.sha256 == expected_fpt and
        identity.pair_sha256 == expected_pair

    cond do
      not valid? -> {:error, :snapshot_identity_mismatch}
      not compatible_paths?(identity) -> {:error, :pair_member_extension_mismatch}
      true -> :ok
    end
  end

  def validate(%__MODULE__{}), do: {:error, :snapshot_identity_mismatch}

  defp member_identity(role, bytes, opts) do
    {path_key, modified_at_key} =
      case role do
        :dbf -> {:dbf_path, :dbf_modified_at}
        :fpt -> {:fpt_path, :fpt_modified_at}
      end

    %MemberIdentity{
      role: role,
      path: Keyword.get(opts, path_key),
      modified_at: Keyword.get(opts, modified_at_key),
      byte_size: byte_size(bytes),
      sha256: hash(bytes)
    }
  end

  defp compatible_paths?(%PairIdentity{kind: kind, dbf: dbf, fpt: fpt}) do
    {dbf_extension, fpt_extension} =
      case kind do
        :scx -> {".scx", ".sct"}
        :vcx -> {".vcx", ".vct"}
      end

    compatible_extension?(dbf.path, dbf_extension) and
      compatible_extension?(fpt.path, fpt_extension)
  end

  defp compatible_extension?(nil, _expected), do: true

  defp compatible_extension?(path, expected) when is_binary(path) do
    path |> Path.extname() |> String.downcase() == expected
  end

  defp compatible_extension?(_path, _expected), do: false

  defp pair_hash(kind, dbf_bytes, fpt_bytes) do
    hash([
      "vfp_mcp_pair_v1\0",
      Atom.to_string(kind),
      <<byte_size(dbf_bytes)::unsigned-big-64>>,
      dbf_bytes,
      <<byte_size(fpt_bytes)::unsigned-big-64>>,
      fpt_bytes
    ])
  end

  defp hash(bytes) do
    :sha256
    |> :crypto.hash(bytes)
    |> Base.encode16(case: :lower)
  end
end
