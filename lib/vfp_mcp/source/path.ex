defmodule VfpMcp.Source.Path do
  @moduledoc """
  Canonical escaping and comparison policy for semantic object paths.

  Display paths preserve source case. Lookup keys decode, case-fold, and
  re-encode every segment so construction and lookup cannot disagree.
  """

  # specled covers:
  # - vfp_mcp.codec.hierarchy_integrity
  # - vfp_mcp.codec.pure_planning
  # - vfp_mcp.read.full_path_identity

  import Bitwise

  @type error :: :empty_path | :empty_segment | :invalid_percent_escape | :invalid_utf8

  @spec build([String.t()]) :: String.t()
  def build([_first | _rest] = segments), do: Enum.map_join(segments, "/", &encode_segment/1)

  @spec parse(String.t()) :: {:ok, [String.t()]} | {:error, error()}
  def parse(path) when is_binary(path) and path != "" do
    path
    |> String.split("/", trim: false)
    |> Enum.reduce_while({:ok, []}, fn
      "", _acc ->
        {:halt, {:error, :empty_segment}}

      segment, {:ok, segments} ->
        case decode_segment(segment) do
          {:ok, decoded} -> {:cont, {:ok, [decoded | segments]}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
    end)
    |> case do
      {:ok, segments} -> {:ok, Enum.reverse(segments)}
      {:error, _reason} = error -> error
    end
  end

  def parse(_path), do: {:error, :empty_path}

  @spec canonicalize(String.t()) :: {:ok, String.t()} | {:error, error()}
  def canonicalize(path) do
    with {:ok, segments} <- parse(path) do
      {:ok, segments |> Enum.map(&String.downcase/1) |> build()}
    end
  end

  @spec encode_segment(String.t()) :: String.t()
  def encode_segment(segment) when is_binary(segment) and segment != "" do
    if String.valid?(segment) do
      segment
      |> :binary.bin_to_list()
      |> Enum.map_join(fn byte ->
        if unreserved?(byte), do: <<byte>>, else: "%" <> Base.encode16(<<byte>>)
      end)
    else
      raise ArgumentError, "path segments must be valid non-empty UTF-8"
    end
  end

  @spec decode_segment(String.t()) :: {:ok, String.t()} | {:error, error()}
  def decode_segment(segment) when is_binary(segment) and segment != "" do
    with {:ok, bytes} <- decode_bytes(segment, []),
         true <- String.valid?(bytes) do
      {:ok, bytes}
    else
      false -> {:error, :invalid_utf8}
      {:error, _reason} = error -> error
    end
  end

  def decode_segment(_segment), do: {:error, :empty_segment}

  defp decode_bytes(<<>>, acc), do: {:ok, acc |> Enum.reverse() |> IO.iodata_to_binary()}

  defp decode_bytes(<<?%, high, low, rest::binary>>, acc) do
    with {:ok, high} <- hex(high),
         {:ok, low} <- hex(low) do
      decode_bytes(rest, [<<(high <<< 4) + low>> | acc])
    else
      :error -> {:error, :invalid_percent_escape}
    end
  end

  defp decode_bytes(<<?%, _rest::binary>>, _acc), do: {:error, :invalid_percent_escape}
  defp decode_bytes(<<byte, rest::binary>>, acc), do: decode_bytes(rest, [<<byte>> | acc])

  defp hex(byte) when byte in ?0..?9, do: {:ok, byte - ?0}
  defp hex(byte) when byte in ?A..?F, do: {:ok, byte - ?A + 10}
  defp hex(byte) when byte in ?a..?f, do: {:ok, byte - ?a + 10}
  defp hex(_byte), do: :error

  defp unreserved?(byte),
    do: byte in ?A..?Z or byte in ?a..?z or byte in ?0..?9 or byte in ~c"-._~"
end
