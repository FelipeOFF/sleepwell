#requires -Version 5.1
<#
.SYNOPSIS
  Detect platform and install sleepwell-helper from GitHub Releases.
.PARAMETER Version
  Specific tag (with or without bin- prefix). Defaults to latest.
.PARAMETER Dest
  Install directory. Default: $env:LOCALAPPDATA\sleepwell\bin
.PARAMETER SkipIfPresent
  No-op if a runnable binary already exists at the destination.
.PARAMETER Quiet
  Only print errors.
#>
param(
  [string]$Version = '',
  [string]$Dest = '',
  [switch]$SkipIfPresent,
  [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
$Repo = 'FelipeOFF/sleepwell'

function Log($msg) { if (-not $Quiet) { Write-Host "[sleepwell-install] $msg" } }
function Die($msg) { Write-Error "[sleepwell-install] error: $msg"; exit 1 }

if (-not $Dest) {
  $Dest = Join-Path $env:LOCALAPPDATA 'sleepwell\bin'
}

# Detect arch
$arch = switch -Wildcard ($env:PROCESSOR_ARCHITECTURE) {
  'AMD64'   { 'x86_64'  }
  'ARM64'   { 'aarch64' }
  default   { Die "unsupported PROCESSOR_ARCHITECTURE: $env:PROCESSOR_ARCHITECTURE" }
}

$target = if ($arch -eq 'x86_64') { 'x86_64-pc-windows-msvc' } else { Die "no prebuilt binary for windows-$arch" }
$asset  = "sleepwell-helper-$target.zip"
$binName = 'sleepwell-helper.exe'

# Resolve version
if (-not $Version) {
  Log 'resolving latest bin-v* release'
  try {
    $releases = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases" -UseBasicParsing
    $Version = ($releases | Where-Object { $_.tag_name -like 'bin-v*' } | Select-Object -First 1).tag_name
  } catch {
    Die 'could not resolve latest release. Pass -Version <tag>.'
  }
  if (-not $Version) { Die 'no bin-v* release found' }
}

if ($Version -notmatch '^bin-v') { $Version = "bin-v$($Version -replace '^v','')" }

$installed = Join-Path $Dest $binName
if ($SkipIfPresent -and (Test-Path $installed)) {
  try {
    & $installed --version | Out-Null
    Log "binary already present: $installed"
    exit 0
  } catch {
    Log 'binary present but not runnable; reinstalling'
  }
}

New-Item -ItemType Directory -Force -Path $Dest | Out-Null

$url = "https://github.com/$Repo/releases/download/$Version/$asset"
$tmp = New-Item -ItemType Directory -Force -Path (Join-Path $env:TEMP "sleepwell-install-$([guid]::NewGuid().Guid)")
$pkg = Join-Path $tmp $asset

Log "downloading $asset ($Version) -> $Dest"
try {
  Invoke-WebRequest -Uri $url -OutFile $pkg -UseBasicParsing
} catch {
  Die "download failed: $url ($_)"
}

# Extract
try {
  Expand-Archive -Path $pkg -DestinationPath $tmp -Force
} catch {
  Die "extract failed: $_"
}

$src = Get-ChildItem -Path $tmp -Recurse -Filter $binName | Select-Object -First 1
if (-not $src) { Die "binary $binName not found in archive" }

Copy-Item -Path $src.FullName -Destination $installed -Force

try {
  $ver = & $installed --version
  Log "installed: $installed"
  Log "version: $ver"
} catch {
  Die "installed but failed to run: $installed"
}

# Cleanup
Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue

# PATH hint
if (-not ($env:Path -split ';' | Where-Object { $_ -eq $Dest })) {
  Log "tip: add $Dest to PATH for direct invocation"
}
