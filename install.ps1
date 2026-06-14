# AGP Community Edition - CLI installer (Windows / PowerShell)
#
# Usage:
#   irm https://raw.githubusercontent.com/getraksha/agp/main/install.ps1 | iex
#
# Environment overrides:
#   $env:AGP_VERSION         release tag to install (default: latest, e.g. v0.1.0)
#   $env:AGP_INSTALL_DIR     install directory (default: %USERPROFILE%\.agp\bin)
#   $env:AGP_BASE_URL        alternate asset base URL (internal mirrors / testing)
#   $env:AGP_NO_MODIFY_PATH  set to any value to skip editing your PATH
#
# Downloads the agp CLI for your platform from github.com/getraksha/agp,
# verifies its SHA-256 checksum against the release's SHA256SUMS, installs it,
# and puts it on your PATH (this session included). The AGP services are then
# installed by the CLI itself via `agp fetch`.
#
# This install script is licensed under the MIT License. The AGP binaries it
# downloads are licensed under the AGP Community Edition License (LICENSE.md).

& {
  $ErrorActionPreference = 'Stop'
  $ProgressPreference = 'SilentlyContinue'   # disables the slow IWR progress bar

  $repo = 'getraksha/agp'
  function Fail($msg) { throw "install.ps1: $msg" }

  # GitHub serves release assets as application/octet-stream, so a downloaded
  # manifest.json comes back as raw bytes in Invoke-WebRequest's in-memory
  # .Content — not a string. Download it to a file and read it as text, then
  # pull the version with a regex (the manifest is one-key-per-line, same as
  # install.sh's sed). -UseBasicParsing keeps Windows PowerShell 5.1 from
  # invoking the legacy IE engine.
  function Get-ManifestVersion($url) {
    $f = Join-Path $env:TEMP ([Guid]::NewGuid().ToString('N') + '.json')
    try {
      Invoke-WebRequest -UseBasicParsing $url -OutFile $f
      $text = Get-Content -Raw -Path $f
      if ($text -match '"version"\s*:\s*"([^"]+)"') { return $matches[1] }
      return $null
    } finally { Remove-Item -Force $f -ErrorAction SilentlyContinue }
  }

  # --- Platform ---------------------------------------------------------------
  $arch = switch ($env:PROCESSOR_ARCHITECTURE) {
    'AMD64' { 'amd64' }
    'ARM64' { 'arm64' }
    default { Fail "unsupported architecture: $env:PROCESSOR_ARCHITECTURE (AGP supports amd64 and arm64)" }
  }
  $platform = "windows-$arch"

  if (-not (Get-Command tar -ErrorAction SilentlyContinue)) {
    Fail 'tar is required (ships with Windows 10 1803+ and Windows 11)'
  }

  # --- Resolve version + base URL --------------------------------------------
  $version = $env:AGP_VERSION
  if ($env:AGP_BASE_URL) {
    $base = $env:AGP_BASE_URL.TrimEnd('/')
    if (-not $version) { $version = Get-ManifestVersion "$base/manifest.json" }
  } elseif ($version) {
    $base = "https://github.com/$repo/releases/download/$version"
  } else {
    $version = Get-ManifestVersion "https://github.com/$repo/releases/latest/download/manifest.json"
    $base = "https://github.com/$repo/releases/download/$version"
  }
  if (-not $version) { Fail 'could not parse version from release manifest' }

  $asset = "agp_${version}_$platform.tar.gz"
  Write-Host "Installing AGP CLI $version ($platform)"

  # --- Download + verify + install --------------------------------------------
  $tmp = Join-Path $env:TEMP ('agp-install-' + [Guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Force -Path $tmp | Out-Null
  $dir = if ($env:AGP_INSTALL_DIR) { $env:AGP_INSTALL_DIR } else { Join-Path $env:USERPROFILE '.agp\bin' }
  try {
    $assetPath = Join-Path $tmp $asset
    $sumsPath  = Join-Path $tmp 'SHA256SUMS'
    Invoke-WebRequest -UseBasicParsing "$base/SHA256SUMS" -OutFile $sumsPath
    Invoke-WebRequest -UseBasicParsing "$base/$asset" -OutFile $assetPath

    $want = $null
    foreach ($line in Get-Content $sumsPath) {
      $parts = $line -split '\s+', 2
      if ($parts.Count -eq 2 -and $parts[1].TrimStart('*').Trim() -eq $asset) {
        $want = $parts[0].Trim(); break
      }
    }
    if (-not $want) { Fail "no checksum entry for $asset in SHA256SUMS" }
    $got = (Get-FileHash $assetPath -Algorithm SHA256).Hash
    if ($got -ne $want) { Fail "checksum mismatch for $asset (expected $want, got $got) - aborting" }
    Write-Host 'Checksum verified.'

    tar -xf $assetPath -C $tmp
    $exe = Join-Path $tmp 'agp.exe'
    if (-not (Test-Path $exe)) { Fail 'archive did not contain agp.exe' }

    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    Copy-Item -Force $exe (Join-Path $dir 'agp.exe')
  } finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
  }

  $installed = Join-Path $dir 'agp.exe'
  & $installed help *> $null
  if ($LASTEXITCODE -ne 0) { Fail 'installed binary failed to run' }

  Write-Host ''
  Write-Host "agp $version installed to $installed"

  # --- PATH -------------------------------------------------------------------
  # Unlike `curl | sh`, PowerShell runs this in the current process, so we can
  # update PATH for this session AND persist it for new ones.
  if (($env:Path -split ';') -contains $dir) {
    Write-Host "agp is on your PATH - you're ready to go."
  } elseif ($env:AGP_NO_MODIFY_PATH) {
    Write-Host "$dir is not on your PATH (AGP_NO_MODIFY_PATH set). Add it with:"
    Write-Host "  `$env:Path += `";$dir`""
  } else {
    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (($userPath -split ';') -notcontains $dir) {
      $newUserPath = if ($userPath) { "$userPath;$dir" } else { $dir }
      [Environment]::SetEnvironmentVariable('Path', $newUserPath, 'User')
      Write-Host "Added $dir to your user PATH (persists for new terminals)."
    }
    $env:Path = "$env:Path;$dir"
    Write-Host 'PATH updated for this terminal too - no restart needed.'
  }

  Write-Host ''
  Write-Host 'Next steps:'
  Write-Host '  agp init        # initialize ~/.agp (secrets, config, CLI profile)'
  Write-Host '  agp fetch all   # download the AGP services for your platform'
  Write-Host '  agp start all   # start the stack'
  Write-Host '  agp setup --agent-id my-agent --client claude-desktop'
}
