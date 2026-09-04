<#
.SYNOPSIS
  Validate and optionally promote synthetic VFP 6/VFP 9 fixture pairs.

.DESCRIPTION
  Scans only .vfp_mcp/fixture-drop/vfp6 and vfp9 (or an explicitly supplied
  drop root), validates SCX/SCT and VCX/VCT pairs, inventories textual memos,
  rejects data/external references, and optionally copies approved pairs to
  test/fixtures/<version>.

  This script never reads files outside the supplied drop root. It never opens
  DBF/DBC data tables and never modifies source trees. Promotion copies only
  the validated source/memo pair.
#>
param(
  [string]$DropRoot = '.\.vfp_mcp\fixture-drop',
  [string]$FixtureRoot = '.\test\fixtures',
  [switch]$Promote,
  [string]$ManifestPath = ''
)

$ErrorActionPreference = 'Stop'

function Fail([string]$Message) { throw $Message }

$drop = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $DropRoot -ErrorAction Stop).Path)
$workspace = [IO.Path]::GetFullPath((Get-Location).Path)
$destination = [IO.Path]::GetFullPath((Join-Path $workspace $FixtureRoot))
if (-not $drop.StartsWith($workspace + [IO.Path]::DirectorySeparatorChar)) {
  Fail "Drop root must be inside the repository: $drop"
}
if ($Promote -and -not $destination.StartsWith($workspace + [IO.Path]::DirectorySeparatorChar)) {
  Fail "Fixture destination must be inside the repository: $destination"
}

$versions = @('vfp6', 'vfp9')
$enc = [Text.Encoding]::GetEncoding(1252)

function Read-BE32([byte[]]$Bytes, [int]$Offset) {
  return (([int]$Bytes[$Offset]) -shl 24) -bor (([int]$Bytes[$Offset + 1]) -shl 16) -bor
         (([int]$Bytes[$Offset + 2]) -shl 8) -bor [int]$Bytes[$Offset + 3]
}

function Read-MemoText([byte[]]$Fpt, [int]$Pointer, [int]$BlockSize) {
  if ($Pointer -le 0) { return '' }
  $offset = $Pointer * $BlockSize
  if ($offset -lt 0 -or $offset + 8 -gt $Fpt.Length) { Fail "Memo pointer $Pointer is outside the FPT" }
  $length = Read-BE32 $Fpt ($offset + 4)
  if ($length -lt 0 -or $offset + 8 + $length -gt $Fpt.Length) {
    Fail "Memo pointer $Pointer has invalid length $length"
  }
  return $enc.GetString($Fpt, $offset + 8, $length)
}

function Read-Document([string]$DbfPath, [string]$MemoPath) {
  $dbf = [IO.File]::ReadAllBytes($DbfPath)
  $fpt = [IO.File]::ReadAllBytes($MemoPath)
  if ($dbf.Length -lt 32 -or $fpt.Length -lt 8) { Fail "File is too short" }
  $recordCount = [BitConverter]::ToInt32($dbf, 4)
  $headerLength = [BitConverter]::ToUInt16($dbf, 8)
  $recordLength = [BitConverter]::ToUInt16($dbf, 10)
  if ($headerLength -lt 33 -or $recordLength -lt 2 -or
      $headerLength + ($recordCount * $recordLength) -gt $dbf.Length) {
    Fail "Invalid DBF header or record bounds"
  }
  $blockSize = (([int]$fpt[6]) -shl 8) -bor [int]$fpt[7]
  if ($blockSize -le 0) { $blockSize = 512 }
  $fields = @(); $descriptor = 32; $fieldOffset = 1
  while ($descriptor -lt $headerLength -and $dbf[$descriptor] -ne 0x0D) {
    if ($descriptor + 32 -gt $dbf.Length) { Fail "Truncated field descriptor" }
    $length = $dbf[$descriptor + 16]
    $fields += [pscustomobject]@{
      Name = $enc.GetString($dbf, $descriptor, 11).Trim([char]0, ' ')
      Type = [char]$dbf[$descriptor + 11]
      Length = $length
      Offset = $fieldOffset
    }
    $fieldOffset += $length; $descriptor += 32
  }
  if ($fields.Count -eq 0) { Fail "No DBF fields found" }
  $records = @(); $allText = New-Object Text.StringBuilder
  for ($r = 0; $r -lt $recordCount; $r++) {
    $base = $headerLength + ($r * $recordLength)
    if ($dbf[$base] -eq 0x2A) { continue }
    $row = [ordered]@{ Record = $r; Deleted = $false }
    foreach ($field in $fields) {
      if ($field.Offset + $field.Length -gt $recordLength) { Fail "Field exceeds record length" }
      if ($field.Type -eq 'M') {
        $pointer = [BitConverter]::ToInt32($dbf, $base + $field.Offset)
        $text = Read-MemoText $fpt $pointer $blockSize
        $row[$field.Name] = $text
        if ($text) { [void]$allText.AppendLine($text) }
      } else {
        $value = $enc.GetString($dbf, $base + $field.Offset, $field.Length).Trim()
        $row[$field.Name] = $value
        if ($field.Name -in @('CLASSLOC', 'OBJNAME', 'PARENT', 'CLASS', 'BASECLASS')) {
          [void]$allText.AppendLine($value)
        }
      }
    }
    $records += [pscustomobject]$row
  }
  [pscustomobject]@{
    VersionByte = ('0x{0:X2}' -f $dbf[0])
    CodePage = ('0x{0:X2}' -f $dbf[29])
    BlockSize = $blockSize
    RecordCount = $recordCount
    ActiveRecords = $records.Count
    Records = $records
    Text = $allText.ToString()
  }
}

if (-not (Test-Path -LiteralPath $drop -PathType Container)) { Fail "Drop root not found: $drop" }
$results = @()
$seen = 0
foreach ($version in $versions) {
  $versionRoot = Join-Path $drop $version
  if (-not (Test-Path -LiteralPath $versionRoot -PathType Container)) { continue }
  $versionRootFull = (Resolve-Path -LiteralPath $versionRoot).Path.TrimEnd([char]92, [char]47)
  $files = Get-ChildItem -LiteralPath $versionRoot -Recurse -File |
    Where-Object { $_.Extension -in @('.scx', '.SCX', '.vcx', '.VCX') }
  foreach ($dbfItem in $files) {
    $extension = $dbfItem.Extension.ToLowerInvariant()
    $memoExtension = if ($extension -eq '.scx') { '.sct' } else { '.vct' }
    $memoPath = [IO.Path]::ChangeExtension($dbfItem.FullName, $memoExtension)
    if (-not (Test-Path -LiteralPath $memoPath -PathType Leaf)) {
      Fail "Missing companion for $($dbfItem.FullName): $memoPath"
    }
    try { $document = Read-Document $dbfItem.FullName $memoPath }
    catch { Fail "Invalid pair $($dbfItem.FullName): $($_.Exception.Message)" }
    $text = $document.Text
    $findings = @()
    if ($text -match '(?im)\b(SELECT|USE|OPEN\s+DATABASE|CREATE\s+DATABASE)\b') {
      $findings += 'VFP data/database command found'
    }
    if ($text -match '(?im)\b(ControlSource|RecordSource|DataSource)\s*=\s*(?!\.NULL\.)\S+') {
      $findings += 'non-empty data binding found'
    }
    if ($text -match '(?im)\b(LOCFILE|SET\s+PATH|SET\s+DEFAULT)\b|[A-Za-z]:\\|\\\\') {
      $findings += 'external path/reference found'
    }
    foreach ($record in $document.Records) {
      if ($record.CLASSLOC -and ([IO.Path]::IsPathRooted($record.CLASSLOC) -or $record.CLASSLOC -match '(?i)(^|[\\/])\.\.([\\/]|$)')) {
        $findings += "external CLASSLOC: $($record.CLASSLOC)"
      }
    }
    $relative = $dbfItem.FullName.Substring($versionRootFull.Length).TrimStart([char]92, [char]47)
    $relativeBase = [IO.Path]::ChangeExtension($relative, '')
    $results += [pscustomobject]@{
      Version = $version
      Kind = if ($extension -eq '.scx') { 'scx' } else { 'vcx' }
      RelativePath = $relative
      MemoRelativePath = [IO.Path]::ChangeExtension($relative, $memoExtension)
      Bytes = $dbfItem.Length
      MemoBytes = (Get-Item -LiteralPath $memoPath).Length
      SHA256 = (Get-FileHash -LiteralPath $dbfItem.FullName -Algorithm SHA256).Hash
      MemoSHA256 = (Get-FileHash -LiteralPath $memoPath -Algorithm SHA256).Hash
      RecordCount = $document.RecordCount
      ActiveRecords = $document.ActiveRecords
      CodePage = $document.CodePage
      BlockSize = $document.BlockSize
      Findings = @($findings)
    }
    $seen++
    if ($findings.Count -gt 0) { Fail "Fixture rejected ($version/$relative): $($findings -join '; ')" }
    if ($Promote) {
      $targetVersion = Join-Path $destination $version
      $targetDbf = Join-Path $targetVersion $relative
      $targetMemo = [IO.Path]::ChangeExtension($targetDbf, $memoExtension)
      New-Item -ItemType Directory -Path (Split-Path -Parent $targetDbf) -Force | Out-Null
      Copy-Item -LiteralPath $dbfItem.FullName -Destination $targetDbf -Force
      Copy-Item -LiteralPath $memoPath -Destination $targetMemo -Force
    }
  }
}
if ($seen -eq 0) { Fail "No SCX/VCX pairs found beneath $drop\vfp6 or $drop\vfp9" }
$manifest = [pscustomobject]@{
  GeneratedAt = [DateTime]::UtcNow.ToString('o')
  DropRoot = $drop
  FixtureRoot = $destination
  Promoted = [bool]$Promote
  Pairs = $results
}
$json = $manifest | ConvertTo-Json -Depth 8
if ($ManifestPath) {
  $manifestTarget = [IO.Path]::GetFullPath((Join-Path $workspace $ManifestPath))
  if (-not $manifestTarget.StartsWith($workspace + [IO.Path]::DirectorySeparatorChar)) { Fail 'Manifest must be inside the repository' }
  New-Item -ItemType Directory -Path (Split-Path -Parent $manifestTarget) -Force | Out-Null
  [IO.File]::WriteAllText($manifestTarget, $json, [Text.Encoding]::UTF8)
}
$json
