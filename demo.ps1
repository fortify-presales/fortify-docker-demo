param(
  [Parameter(Position=0)]
  [ValidateSet('start','stop','status','ps','logs','config','help','clean')]
  [string]$Action = 'status',

  [Alias('d')]
  [string]$ComposeDir = 'compose',

  [Alias('n')]
  [string]$ProjectName = 'ftfydemo',

  [Alias('p')]
  [string]$Profile = $null,

  [string]$Service,

  [switch]$Follow,

  # PowerShell-style action switches (map to positional $Action later)
  [switch]$Start,
  [switch]$Stop,
  [switch]$Status,
  [switch]$Ps,
  [switch]$Logs,

  [Alias('c')]
  [string]$CredFile = 'demo.credentials'
  ,
  [Alias('v')]
  [string]$ImageVersionsFile = 'demo.env'
  ,
  [Alias('l')]
  [string]$LIMVersion = $null
  ,
  [switch]$ApplyImageEnv
  ,
  [Alias('recreate-certs')]
  [switch]$RecreateCerts
  ,
  [switch]$Clean
  ,
  [Alias('net')]
  [string]$NetworkName = 'ftfydemo_net'
)

# Map PowerShell-style action switches to the positional/action parameter.
# If a user passes one of -Start/-Stop/-Status/-Ps/-Logs/-Clean, set `$Action`
# accordingly. If multiple are provided, error out.
$explicitActions = @()
if ($PSBoundParameters.ContainsKey('Start'))  { $explicitActions += 'start' }
if ($PSBoundParameters.ContainsKey('Stop'))   { $explicitActions += 'stop' }
if ($PSBoundParameters.ContainsKey('Status')) { $explicitActions += 'status' }
if ($PSBoundParameters.ContainsKey('Ps'))     { $explicitActions += 'ps' }
if ($PSBoundParameters.ContainsKey('Logs'))   { $explicitActions += 'logs' }
if ($PSBoundParameters.ContainsKey('Clean'))  { $explicitActions += 'clean' }
if ($explicitActions.Count -gt 1) {
  Write-Error 'Only one action switch may be specified (e.g. -Start or -Stop).'
  exit 1
} elseif ($explicitActions.Count -eq 1) {
  $Action = $explicitActions[0]
}

function Show-Usage {
  Write-Output 'Usage: pwsh ./demo.ps1 <start|stop|status|ps|logs|config|help|clean> [-ComposeDir <dir>] [-ProjectName <name>] [-Service <service>] [-Profile <profile>] [-Follow]'
  Write-Output ''
  Write-Output 'Examples:'
  Write-Output '  pwsh ./demo.ps1 start -ComposeDir compose -Profile traefik'
  Write-Output '  pwsh ./demo.ps1 stop -ComposeDir compose -ProjectName ftfydemo'
  Write-Output '  pwsh ./demo.ps1 status -ComposeDir compose'
  Write-Output '  pwsh ./demo.ps1 ps -ComposeDir compose'
    Write-Output '  pwsh ./demo.ps1 logs -ComposeDir compose -Service traefik -Follow'
    Write-Output '  pwsh ./demo.ps1 config -ComposeDir compose  # show resolved compose config (uses --profile default)'
    Write-Output ''
    Write-Output 'Options:'
    Write-Output '  -RecreateCerts    Force regeneration of mkcert certificates in ./certs'
    Write-Output '  -Clean            Remove compose containers, volumes, network and ./certs directory'
}

function Get-ComposeCmd {
  $docker = Get-Command docker -ErrorAction SilentlyContinue
  if ($null -ne $docker) {
    try {
      & docker compose version > $null 2>&1
      if ($LASTEXITCODE -eq 0) { return @{ Cmd = 'docker'; Sub = 'compose' } }
    } catch {}
  }

  $dc = Get-Command docker-compose -ErrorAction SilentlyContinue
  if ($null -ne $dc) { return @{ Cmd = 'docker-compose'; Sub = $null } }

  Write-Error 'Neither "docker compose" nor "docker-compose" is available in PATH.'
  exit 2
}

function Supports-Profile {
  $c = Get-ComposeCmd
  $helpArgs = @('--help')
  try {
    if ($c.Sub) {
      $out = & $c.Cmd $c.Sub @helpArgs 2>&1
    } else {
      $out = & $c.Cmd @helpArgs 2>&1
    }
    $text = ($out -join "`n") -as [string]
    return $text -match '--profile'
  } catch {
    return $false
  }
}

function Invoke-Compose {
  param(
    [string[]]$ComposeArgs
  )
  $c = Get-ComposeCmd
  if ($c.Sub) {
    & $c.Cmd $c.Sub @ComposeArgs
  } else {
    & $c.Cmd @ComposeArgs
  }
  return $LASTEXITCODE
}

if ($Action -eq 'help') { Show-Usage; exit 0 }

if (-not (Test-Path -Path $ComposeDir)) {
  Write-Warning ('Compose directory "{0}" not found.' -f $ComposeDir)
}

$composeFiles = @()
$composeFiles += Get-ChildItem -Path $ComposeDir -Filter '*.yml' -File -ErrorAction SilentlyContinue
$composeFiles += Get-ChildItem -Path $ComposeDir -Filter '*.yaml' -File -ErrorAction SilentlyContinue
$composeFiles = $composeFiles | Sort-Object Name
if (-not $composeFiles -or $composeFiles.Count -eq 0) {
  Write-Warning ('No compose YAML files found under "{0}".' -f $ComposeDir)
}

$baseArgs = @()
foreach ($f in $composeFiles) {
  $baseArgs += '-f'
  $baseArgs += $f.FullName
}
if ($ProjectName) { $baseArgs += '--project-name'; $baseArgs += $ProjectName }

# NOTE: adding an --env-file must happen after $versionsPath is computed below

# If user requested, update compose files to use env-var image tags (creates .bak)
if ($ApplyImageEnv) {
  Update-ComposeFilesToEnvVars -Files $composeFiles -Versions $versions
}

# Parse images from compose files
function Parse-Compose-Images {
  param([string[]]$Files)
  $imgs = @{}
  foreach ($f in $Files) {
    foreach ($line in Get-Content -Raw -Path $f.FullName -ErrorAction SilentlyContinue -Encoding UTF8) {
      foreach ($m in ([regex]::Matches($line, "(?m)^[ \t]*image:\s*(\S+)", 'IgnoreCase'))) {
        $img = $m.Groups[1].Value.Trim('"')
        if (-not $img) { continue }
        $imgs[$img] = $true
      }
    }
  }
  return $imgs.Keys
}

# Normalize repo to environment variable name (basic heuristic)
function RepoToVarName {
  param([string]$Repo)
  $name = $Repo -replace '/', '__'
  $name = $name -replace '[:]', '__'
  $name = $name -replace '-', '_'
  return ($name.ToUpper() + '_VERSION')
}

# Update compose files to use env-var-based image tags. Creates a .bak copy before writing.
function Update-ComposeFilesToEnvVars {
  param([string[]]$Files,[hashtable]$Versions)
  if (-not $ApplyImageEnv) { return }
  # Build file list arguments
  $files = $Files | ForEach-Object { $_.FullName }
  $py = Get-Command python -ErrorAction SilentlyContinue
  if (-not $py) { Write-Warning 'Python not found in PATH; cannot update compose files automatically.'; return }
  $script = Join-Path -Path (Split-Path -Parent $MyInvocation.MyCommand.Definition) -ChildPath 'tools\update_compose_images.py'
  $args = @('--files') + $files
  if ($Versions -and $Versions.Count -gt 0) { $args += @('--versions', $versionsPath) }
  Write-Output ('Running image update script: python {0} {1}' -f $script, ($args -join ' '))
  $proc = & python $script @args 2>&1
  Write-Output $proc
}

# Scan compose images and check access for each image found
function Scan-And-Check-ComposeImages {
  param(
    [Parameter(Mandatory=$true)][object[]]$Files,
    [hashtable]$Versions,
    [hashtable]$Creds,
    [string]$CredPath
  )

  $images = Parse-Compose-Images -Files $Files
  if (-not $images -or $images.Count -eq 0) { Write-Output 'No images found in compose files to check.'; return }

  foreach ($img in $images) {
    $repo = $img
    $tag = $null
    if ($repo -match '^(.*?):([^:/]+)$') { $repo = $matches[1]; $tag = $matches[2] }

    $tagFromVersions = Get-ImageTagFromVersions -Repo $repo -Versions $Versions
    if ($tagFromVersions) { $check = "${repo}:$tagFromVersions" }
    elseif ($tag) { $check = "${repo}:$tag" }
    else { $check = $repo }

    Write-Output ("Checking access to image: {0}" -f $check)
    try {
      $can = CanAccess-PrivateRepo -Repo $check -Creds $Creds
      if (-not $can) {
        Write-Warning ("Cannot access image {0} anonymously." -f $check)
        if ($CredPath -and (Test-Path $CredPath)) {
          Write-Output ("Found credentials file at {0} - attempting docker login." -f $CredPath)
          $ok = Ensure-DockerLogin -Creds $Creds
          if ($ok) {
            if (CanAccess-PrivateRepo -Repo $check -Creds $Creds) {
              Write-Output ("Successfully authenticated and can access {0}." -f $check)
            } else {
              Write-Warning ("Login succeeded but still cannot access {0}." -f $check)
            }
          } else {
            Write-Warning ("Docker login using credentials from {0} failed." -f $CredPath)
          }
        } else {
          Write-Warning ("No credentials file at {0} - you may need to run 'docker login' manually." -f $CredPath)
        }
      } else {
        Write-Output ("Can access {0}" -f $check)
      }
    } catch {
      Write-Warning ("Error while checking {0}: {1}" -f $check, $_.Exception.Message)
    }
  }
}

# credential helper functions (must be defined before use)
function Read-Creds {
  param([string]$Path)
  $map = @{}
  if (-not (Test-Path -Path $Path)) { return $map }
  foreach ($line in Get-Content -Path $Path -ErrorAction SilentlyContinue) {
    $s = $line.Trim()
    if ($s -eq '' -or $s.StartsWith('#')) { continue }
    if ($s -match '^(.*?)=(.*)$') {
      $k = $matches[1].Trim()
      $v = $matches[2].Trim()
      if ((($v.Length -ge 2) -and ($v.StartsWith('"') -and $v.EndsWith('"'))) -or (($v.Length -ge 2) -and ($v.StartsWith("'") -and $v.EndsWith("'")))) {
        $v = $v.Substring(1, $v.Length - 2)
      }
      $map[$k] = $v
    }
  }
  return $map
}

function Get-CredValue {
  param(
    [hashtable]$Creds,
    [string]$Key
  )
  if ($null -ne $Creds) {
    # Try exact key
    if ($Creds.ContainsKey($Key)) { return $Creds[$Key] }
    # Try common variants
    $upper = $Key.ToUpper()
    $lower = $Key.ToLower()
    if ($Creds.ContainsKey($upper)) { return $Creds[$upper] }
    if ($Creds.ContainsKey($lower)) { return $Creds[$lower] }
  }
  # Fallback to environment variables (use GetEnvironmentVariable for dynamic names)
  $envVal = [System.Environment]::GetEnvironmentVariable($Key)
  if ($envVal) { return $envVal }
  $envVal = [System.Environment]::GetEnvironmentVariable($Key.ToUpper())
  if ($envVal) { return $envVal }
  $envVal = [System.Environment]::GetEnvironmentVariable($Key.ToLower())
  if ($envVal) { return $envVal }
  return $null
}

# Read simple KEY=VALUE version files (like old.env) into a hashtable
function Read-Versions {
  param([string]$Path)
  $map = @{}
  if (-not (Test-Path -Path $Path)) { return $map }
  foreach ($line in Get-Content -Path $Path -ErrorAction SilentlyContinue) {
    $s = $line.Trim()
    if ($s -eq '' -or $s.StartsWith('#')) { continue }
    if ($s -match '^(.*?)=(.*)$') {
      $k = $matches[1].Trim()
      $v = $matches[2].Trim()
      if ((($v.Length -ge 2) -and ($v.StartsWith('"') -and $v.EndsWith('"'))) -or (($v.Length -ge 2) -and ($v.StartsWith("'") -and $v.EndsWith("'")))) {
        $v = $v.Substring(1, $v.Length - 2)
      }
      $map[$k] = $v
    }
  }
  return $map
}

# Given a repo name like 'fortifydocker/ssc-demo-webapp', try to find a tag in the versions map.
function Get-ImageTagFromVersions {
  param(
    [string]$Repo,
    [hashtable]$Versions
  )
  if (-not $Versions) { return $null }
  # Try direct key (case-insensitive)
  foreach ($k in $Versions.Keys) {
    if ($k.ToLower() -eq $Repo.ToLower()) { return $Versions[$k] }
  }
  # Try normalized forms: '/' -> '__', uppercase; also '-' -> '_' variant
  $norm1 = ($Repo -replace '/', '__').ToUpper()
  if ($Versions.ContainsKey($norm1)) { return $Versions[$norm1] }
  $norm2 = ($norm1 -replace '-', '_')
  if ($Versions.ContainsKey($norm2)) { return $Versions[$norm2] }
  # Special-case: if 'FORTIFYDOCKER' present, try inserting underscore 'FORTIFY_DOCKER'
  if ($norm1 -match '^FORTIFYDOCKER__(.+)$') {
    $alt = 'FORTIFY_DOCKER__' + $matches[1]
    if ($Versions.ContainsKey($alt)) { return $Versions[$alt] }
  }
  return $null
}


function CanAccess-PrivateRepo {
  param(
    [string]$Repo,
    [hashtable]$Creds
  )
  # If a tag is supplied, prefer docker manifest inspect (fast, local CLI check)
  $repoName = $Repo
  $tag = $null
  if ($Repo -match '^(.*?):([^:/]+)$') {
    $repoName = $matches[1]
    $tag = $matches[2]
  }

  if ($tag) {
    # Try local docker CLI first
    try {
      $out = & docker manifest inspect "docker.io/${repoName}:$tag" 2>&1
      if ($LASTEXITCODE -eq 0) { return $true }
      Write-Verbose ("docker manifest inspect output: {0}" -f ($out -join '`n'))
    } catch {
      Write-Verbose ("docker manifest inspect exception: {0}" -f $_.Exception.Message)
    }

    # If docker manifest inspect failed, fall back to registry HTTP manifest API using token flow
    try {
      $repoForAuth = $repoName
      if ($repoForAuth -notmatch '/') { $repoForAuth = "library/$repoForAuth" }
      $tokenUrl = "https://auth.docker.io/token?service=registry.docker.io&scope=repository:$repoForAuth:pull"

      $headers = @{}
      if ($Creds -and $Creds.Count -gt 0) {
        $user = Get-CredValue -Creds $Creds -Key 'DOCKER_USERNAME'
        $pass = Get-CredValue -Creds $Creds -Key 'DOCKER_PASSWORD'
        if ($user -and $pass) {
          $basic = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$user`:$pass"))
          $headers['Authorization'] = "Basic $basic"
        }
      }

      Write-Verbose ("Requesting token from: {0}" -f $tokenUrl)
      if ($headers.ContainsKey('Authorization')) { Write-Verbose 'Using Basic Authorization header for token request' } else { Write-Verbose 'No Basic auth header for token request (anonymous)' }
      $tokenResp = Invoke-RestMethod -Uri $tokenUrl -Headers $headers -Method GET -ErrorAction Stop
      if ($null -ne $tokenResp) { Write-Verbose ("Token response keys: {0}" -f ($tokenResp.PSObject.Properties.Name -join ',')) }
      $token = $null
      if ($tokenResp -and $tokenResp.access_token) { $token = $tokenResp.access_token }
      elseif ($tokenResp -and $tokenResp.token) { $token = $tokenResp.token }
      if ($token) { Write-Verbose ("Received token length: {0}" -f $token.Length) } else { Write-Verbose 'No token found in token response' ; return $false }

      $manifestUrl = "https://registry-1.docker.io/v2/$repoForAuth/manifests/$tag"
      $manifestHeaders = @{ Authorization = "Bearer $token"; Accept = 'application/vnd.docker.distribution.manifest.v2+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.oci.image.manifest.v1+json' }
      Write-Verbose ("Requesting manifest from: {0}" -f $manifestUrl)
      try {
        Invoke-RestMethod -Uri $manifestUrl -Headers $manifestHeaders -Method GET -ErrorAction Stop | Out-Null
        Write-Verbose 'Manifest request succeeded'
        return $true
      } catch {
        Write-Verbose ("Manifest request failed: {0}" -f $_.Exception.Message)
        try {
          $resp = $_.Exception.Response
          if ($resp) {
            try { $code = $resp.StatusCode.value__ } catch { $code = $null }
            try { $desc = $resp.StatusDescription } catch { $desc = $null }
            Write-Verbose ("Manifest HTTP response: {0} {1}" -f $code, $desc)
          }
        } catch {}
        return $false
      }
    } catch {
      return $false
    }
  }

  # No tag: use Docker Hub token flow to check tags list (handles private repos)
  try {
    $repoForAuth = $repoName
    if ($repoForAuth -notmatch '/') { $repoForAuth = "library/$repoForAuth" }
    $tokenUrl = "https://auth.docker.io/token?service=registry.docker.io&scope=repository:$repoForAuth:pull"

    $headers = @{}
    if ($Creds -and $Creds.Count -gt 0) {
      $user = Get-CredValue -Creds $Creds -Key 'DOCKER_USERNAME'
      $pass = Get-CredValue -Creds $Creds -Key 'DOCKER_PASSWORD'
      if ($user -and $pass) {
        $basic = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$user`:$pass"))
        $headers['Authorization'] = "Basic $basic"
      }
    }

    $tokenResp = Invoke-RestMethod -Uri $tokenUrl -Headers $headers -Method GET -ErrorAction Stop
    $token = $null
    if ($tokenResp -and $tokenResp.access_token) { $token = $tokenResp.access_token }
    elseif ($tokenResp -and $tokenResp.token) { $token = $tokenResp.token }
    if (-not $token) { return $false }

    $tagsUrl = "https://registry-1.docker.io/v2/$repoForAuth/tags/list"
    $tagsResp = Invoke-RestMethod -Uri $tagsUrl -Headers @{ Authorization = "Bearer $token" } -Method GET -ErrorAction Stop
    if ($tagsResp -and $tagsResp.tags) { return $true }
    return $true
  } catch {
    return $false
  }
}

function Ensure-DockerLogin {
  param([hashtable]$Creds)
  if (-not $Creds) { $Creds = @{} }
  $user = Get-CredValue -Creds $Creds -Key 'DOCKER_USERNAME'
  $pass = Get-CredValue -Creds $Creds -Key 'DOCKER_PASSWORD'
  if (-not $user -or -not $pass) { Write-Warning 'DOCKER_USERNAME or DOCKER_PASSWORD not found in credentials file or environment.'; return $false }
  try {
    $secure = $pass
    $secure | & docker login --username $user --password-stdin 2>&1 | Out-Null
    return ($LASTEXITCODE -eq 0)
  } catch {
    return $false
  }
}

# Load image versions (if provided)
$versions = @{}
$versionsPath = if ([IO.Path]::IsPathRooted($ImageVersionsFile)) { $ImageVersionsFile } else { Join-Path -Path (Get-Location) -ChildPath $ImageVersionsFile }
if (Test-Path $versionsPath) { $versions = Read-Versions -Path $versionsPath }

# If user passed a LIMVersion on the command line, write/update it into the versions env file
if ($LIMVersion) {
  try {
    if (-not (Test-Path $versionsPath)) {
      New-Item -Path $versionsPath -ItemType File -Force | Out-Null
    }
    $lines = @()
    if (Test-Path $versionsPath) { $lines = Get-Content -Path $versionsPath -ErrorAction SilentlyContinue }
    $key = 'FORTIFY_DOCKER__LIM'
    $newLine = ("{0}={1}" -f $key, $LIMVersion)
    $found = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
      if ($lines[$i] -match ('^' + [regex]::Escape($key) + '\s*=')) {
        $lines[$i] = $newLine
        $found = $true
        break
      }
    }
    if (-not $found) { $lines += $newLine }
    Set-Content -Path $versionsPath -Value $lines -Encoding UTF8
    # reload versions map
    $versions = Read-Versions -Path $versionsPath
    Write-Output ("Wrote {0} into {1}" -f $newLine, $versionsPath)
  } catch {
    Write-Warning ("Failed to write LIM version to {0}: {1}" -f $versionsPath, $_.Exception.Message)
  }
}

# If an image versions env file exists, add it as a global --env-file to compose
if ($versionsPath -and (Test-Path $versionsPath)) {
  # Prepend so it's a global option before subcommands
  $baseArgs = @('--env-file', $versionsPath) + $baseArgs
}

# Ensure-DockerNetworkExists: inspect/create docker network when needed
function Ensure-DockerNetworkExists {
  param([string]$Name)
  if (-not $Name -or $Name.Trim() -eq '') { return $false }
  try {
    & docker network inspect $Name > $null 2>&1
    if ($LASTEXITCODE -eq 0) { return $true }
    Write-Output ("Docker network '{0}' not found, creating..." -f $Name)
    & docker network create $Name 2>&1 | Out-Null
    return ($LASTEXITCODE -eq 0)
  } catch {
    return $false
  }
}

# Ensure LIM data volume directories are writable by the LIM runtime user (UID 1001:GID 1001).
function Ensure-LIMVolumePermissions {
  param([string]$ProjectName)
  $candidates = @()
  if ($ProjectName) { $candidates += ("${ProjectName}_ftfydata_lim") }
  $candidates += @('ftfydata_lim','ftfydemo_ftfydata_lim')
  $seen = @{}
  foreach ($v in $candidates) {
    if (-not $v -or $seen.ContainsKey($v)) { continue }
    $seen[$v] = $true
    try {
      & docker volume inspect $v > $null 2>&1
      if ($LASTEXITCODE -eq 0) {
        Write-Output ("Fixing ownership/permissions on volume {0}" -f $v)
        try {
          # Use numeric UID:GID from the LIM image (limuser = 1001:1001) to ensure files are owned by the runtime user
          & docker run --rm -v "${v}:/data" --platform linux alpine:3.18 sh -c 'chown -R 1001:1001 /data || true; chmod -R u+rwX,g+rwX /data/database /data/certificates || true' | Out-Null
        } catch {
          Write-Warning ("Failed to run permission-fix container for volume {0}: {1}" -f $v, $_.Exception.Message)
        }
      }
    } catch {}
  }
}

# Check whether mkcert CA is installed in Windows cert stores (CurrentUser or LocalMachine roots)
function Is-MkcertCAInstalled {
  try {
    $found = $false
    $patterns = @('mkcert','MKCERT')
    # Check CurrentUser and LocalMachine Root stores
    $stores = @('Cert:\CurrentUser\Root','Cert:\LocalMachine\Root')
    foreach ($s in $stores) {
      if (Test-Path $s) {
        Get-ChildItem -Path $s -ErrorAction SilentlyContinue | ForEach-Object {
          $cert = $_
          if ($cert.Subject -match 'mkcert' -or $cert.Issuer -match 'mkcert' -or ($cert.FriendlyName -and $cert.FriendlyName -match 'mkcert')) {
            $found = $true
          }
        }
      }
    }
    return $found
  } catch {
    return $false
  }
}

# Perform a full cleanup of the demo environment: stop/remove compose, volumes, networks, and certs
function Do-Cleanup {
  Write-Output 'Starting cleanup: stopping compose and removing volumes, network, and certs...'

  # Attempt docker compose down with volumes/remove-orphans
  try {
    $downArgs = $baseArgs + @('down','--volumes','--remove-orphans')
    Write-Output ('Running: {0}' -f ($downArgs -join ' '))
    Invoke-Compose -ComposeArgs $downArgs | Out-Null
  } catch {
    Write-Warning ('docker compose down failed: {0}' -f $_.Exception.Message)
  }

  # Known volumes that the demo uses (best-effort removal)
  $volumesToRemove = @('ftfydata_lim','ftfydata_mysql','ftfydata_ssc')
  foreach ($v in $volumesToRemove) {
    try {
      & docker volume inspect $v > $null 2>&1
      if ($LASTEXITCODE -eq 0) {
        Write-Output ("Removing volume {0}" -f $v)
        & docker volume rm -f $v | Out-Null
      }
    } catch {}
  }

  # Remove the demo network if it exists
  try {
    if ($NetworkName) {
      & docker network inspect $NetworkName > $null 2>&1
      if ($LASTEXITCODE -eq 0) {
        Write-Output ("Removing network {0}" -f $NetworkName)
        & docker network rm $NetworkName | Out-Null
      }
    }
  } catch {}

  # Remove certs directory
  try {
    # Determine script directory robustly
    $scriptDir = if ($PSCommandPath) { Split-Path -Parent $PSCommandPath } elseif ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Definition }
    $certDir = Join-Path $scriptDir 'certs'
    if (Test-Path $certDir) {
      Write-Output ("Removing certs directory: {0}" -f $certDir)
      Remove-Item -Recurse -Force -Path $certDir
    } else {
      Write-Output 'No certs directory found; skipping.'
    }
  } catch {
    Write-Warning ("Failed to remove certs directory: {0}" -f $_.Exception.Message)
  }

  # Remove any leftover containers for this project (best-effort)
  try {
    $conts = & docker ps -a --filter "name=$ProjectName" --format '{{.ID}}' 2>$null
    if ($conts) {
      Write-Output ('Forcibly removing leftover containers: {0}' -f ($conts -join ', '))
      & docker rm -f $conts | Out-Null
    }
  } catch {}

  # Attempt to find and remove containers that are using the volumes (filter by volume)
  foreach ($v in $volumesToRemove) {
    try {
      $usedBy = & docker ps -a --filter "volume=$v" --format '{{.ID}}' 2>$null
      if ($usedBy) {
        Write-Output ('Removing containers using volume {0}: {1}' -f $v, ($usedBy -join ', '))
        & docker rm -f $usedBy | Out-Null
      }
    } catch {}
  }

  # Try removing volumes again in case they were in use earlier
  foreach ($v in $volumesToRemove) {
    try {
      & docker volume inspect $v > $null 2>&1
      if ($LASTEXITCODE -eq 0) {
        Write-Output ("Removing volume {0}" -f $v)
        & docker volume rm -f $v | Out-Null
      }
    } catch {}
  }

  Write-Output 'Cleanup finished.'
}

if ($Clean -or $Action -eq 'clean') {
  Do-Cleanup
  exit 0
}

switch ($Action) {
  'start' {
    # Determine profile to use: if user explicitly provided -Profile use it, otherwise default to 'default'
    $profileToUse = if ($PSBoundParameters.ContainsKey('Profile')) { $Profile } else { 'default' }

    if ($profileToUse -and (Supports-Profile)) {
      $composeArgs = $baseArgs + @('--profile', $profileToUse, 'up','-d')
    } else {
      if ($PSBoundParameters.ContainsKey('Profile')) { Write-Warning ('Compose command does not support --profile; ignoring profile "{0}".' -f $Profile) }
      $composeArgs = $baseArgs + @('up','-d')
    }
    if ($Service) { $composeArgs += $Service }
    # Only perform private-repo access check when starting/pulling images
    try {
      $credPath = if ([IO.Path]::IsPathRooted($CredFile)) { $CredFile } else { Join-Path -Path (Get-Location) -ChildPath $CredFile }
      $creds = @{}
      if (Test-Path $credPath) { $creds = Read-Creds -Path $credPath }

      Write-Output 'Scanning compose files for image access...'
      Scan-And-Check-ComposeImages -Files $composeFiles -Versions $versions -Creds $creds -CredPath $credPath
    } catch {}
    # Ensure requested docker network exists (create if missing)
    if ($NetworkName) {
      $netOk = Ensure-DockerNetworkExists -Name $NetworkName
      if ($netOk) { Write-Output ("Ensured docker network '{0}' exists." -f $NetworkName) } else { Write-Warning ("Failed to create or find docker network '{0}'." -f $NetworkName) }
    }
    # Ensure local TLS certs exist for dev hostnames using mkcert
    try {
      $mkcert = Get-Command mkcert -ErrorAction SilentlyContinue
      if (-not $mkcert) {
        Write-Output 'mkcert not found in PATH. Attempting to install via winget...'
        try {
          Start-Process -FilePath winget -ArgumentList 'install','-e','--id','mkcert' -NoNewWindow -Wait -ErrorAction Stop
        } catch {
          Write-Warning 'winget install failed or winget not available. Please install mkcert manually.'
        }
      }
      # Ensure mkcert CA is installed in the OS trust store
      if (Get-Command mkcert -ErrorAction SilentlyContinue) {
        if (-not (Is-MkcertCAInstalled)) {
          $isAdmin = $false
          try {
            $wi = [Security.Principal.WindowsIdentity]::GetCurrent()
            $wp = New-Object Security.Principal.WindowsPrincipal($wi)
            $isAdmin = $wp.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
          } catch { $isAdmin = $false }

          if (-not $isAdmin) {
            Write-Output 'mkcert CA not found; attempting to install and prompting for elevation (UAC) to add CA to trust stores.' 
            try {
              Start-Process -FilePath (Get-Command mkcert).Source -ArgumentList '-install' -Verb RunAs -Wait -ErrorAction Stop
            } catch {
              Write-Warning 'Failed to elevate mkcert -install. Please run this script as Administrator or run "mkcert -install" manually.'
            }
          } else {
            & mkcert -install
          }

          # verify installation
          if (-not (Is-MkcertCAInstalled)) {
            Write-Warning 'mkcert CA still not detected after install. Browser may not trust generated certs.'
          }
        } else {
          Write-Output 'mkcert CA already installed in trust store.'
        }
      } else { Write-Warning 'mkcert not available; skipping cert generation.' }

      $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
      $certDir = Join-Path $scriptDir 'certs'
      if (-not (Test-Path $certDir)) { New-Item -ItemType Directory -Path $certDir | Out-Null }

      $hosts = @('lim.ftfydemo.local','ssc.ftfydemo.local')
      foreach ($h in $hosts) {
        $certFile = Join-Path $certDir "$h.pem"
        $keyFile = Join-Path $certDir "$h-key.pem"

        if ($RecreateCerts.IsPresent) {
          if (Test-Path $certFile) { Remove-Item -Force $certFile }
          if (Test-Path $keyFile) { Remove-Item -Force $keyFile }
        }

        if (-not (Test-Path $certFile) -or -not (Test-Path $keyFile)) {
          Write-Output ("Generating mkcert certificate for {0}" -f $h)
          & mkcert -cert-file $certFile -key-file $keyFile $h
          if ($LASTEXITCODE -ne 0) { Write-Warning ("mkcert failed for {0}" -f $h) }
        } else {
          Write-Output ("Certificate for {0} already exists, skipping." -f $h)
        }
      }
    } catch {
      Write-Warning ("Failed to generate certificates: {0}" -f $_.Exception.Message)
    }

    Write-Output ('Running: {0}' -f ($composeArgs -join ' '))
    # Ensure compose runs from the repository/script directory so relative host paths resolve portably
    $scriptDir = if ($PSCommandPath) { Split-Path -Parent $PSCommandPath } elseif ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Definition }
    Push-Location $scriptDir
    try {
      $rc = Invoke-Compose -ComposeArgs $composeArgs
    } finally {
      Pop-Location
    }
    if ($rc -eq 0) {
      # After compose creates volumes/containers, ensure LIM volume directories are writable
      Ensure-LIMVolumePermissions -ProjectName $ProjectName
    }
    exit $rc
  }
  'stop' {
    # Determine profile to use: if user explicitly provided -Profile use it, otherwise default to 'default'
    $profileToUse = if ($PSBoundParameters.ContainsKey('Profile')) { $Profile } else { 'default' }

    if ($Service) {
      if ($profileToUse -and (Supports-Profile)) {
        $composeArgs = $baseArgs + @('--profile', $profileToUse, 'stop', $Service)
      } else {
        $composeArgs = $baseArgs + @('stop', $Service)
      }
      Write-Output ('Running: {0}' -f ($composeArgs -join ' '))
      $rc = Invoke-Compose -ComposeArgs $composeArgs
      exit $rc
    } else {
      if ($profileToUse -and (Supports-Profile)) {
        $composeArgs = $baseArgs + @('--profile', $profileToUse, 'down')
      } else {
        $composeArgs = $baseArgs + @('down')
      }
      Write-Output ('Running: {0}' -f ($composeArgs -join ' '))
      $rc = Invoke-Compose -ComposeArgs $composeArgs
      exit $rc
    }
  }
  'status' {
    $composeArgs = $baseArgs + @('ps')
    Write-Output 'Project services (compose ps):'
    $rc = Invoke-Compose -ComposeArgs $composeArgs
    Write-Output ''
    if ($ProjectName) {
      Write-Output ('Docker containers for project "{0}":' -f $ProjectName)
      docker ps --filter="label=com.docker.compose.project=$ProjectName"
    }
    exit $rc
  }
  'ps' {
    $composeArgs = $baseArgs + @('ps')
    Write-Output 'Compose ps:'
    Invoke-Compose -ComposeArgs $composeArgs
    exit 0
  }
  'config' {
    # Show resolved compose configuration. Use provided profile or default 'default' when supported.
    $profileToUse = if ($PSBoundParameters.ContainsKey('Profile')) { $Profile } else { 'default' }
    if ($profileToUse -and (Supports-Profile)) {
      $composeArgs = $baseArgs + @('--profile', $profileToUse, 'config')
    } else {
      if ($PSBoundParameters.ContainsKey('Profile')) { Write-Warning ('Compose command does not support --profile; ignoring profile "{0}".' -f $Profile) }
      $composeArgs = $baseArgs + @('config')
    }
    Write-Output ('Running: {0}' -f ($composeArgs -join ' '))
    $rc = Invoke-Compose -ComposeArgs $composeArgs
    exit $rc
  }
  'logs' {
    # Show the last 200 lines by default and allow following with -Follow
    # Try running with the profile (explicit or default) first; if that fails, retry without --profile.
    $profileToUse = if ($PSBoundParameters.ContainsKey('Profile')) { $Profile } else { 'default' }

    if ($profileToUse) {
      $composeArgsAttempt = $baseArgs + @('--profile', $profileToUse, 'logs','--tail','200')
      if ($Follow) { $composeArgsAttempt += '-f' }
      if ($Service) { $composeArgsAttempt += $Service }
      Write-Output ('Running (attempt with --profile): {0}' -f ($composeArgsAttempt -join ' '))
      $rc = Invoke-Compose -ComposeArgs $composeArgsAttempt
      if ($rc -eq 0) { exit $rc }
      Write-Warning ('`--profile {0}` attempt failed (exit {1}); retrying without --profile.' -f $profileToUse, $rc)
    }

    # Fallback: run without --profile
    $composeArgs = $baseArgs + @('logs','--tail','200')
    if ($Follow) { $composeArgs += '-f' }
    if ($Service) { $composeArgs += $Service }
    Write-Output ('Running: {0}' -f ($composeArgs -join ' '))
    $rc = Invoke-Compose -ComposeArgs $composeArgs
    exit $rc
  }
  default {
    Write-Error ('Unknown action: {0}' -f $Action)
    Show-Usage
    exit 1
  }
}



# Read simple KEY=VALUE version files (like old.env) into a hashtable
function Read-Versions {
  param([string]$Path)
  $map = @{}
  if (-not (Test-Path -Path $Path)) { return $map }
  foreach ($line in Get-Content -Path $Path -ErrorAction SilentlyContinue) {
    $s = $line.Trim()
    if ($s -eq '' -or $s.StartsWith('#')) { continue }
    if ($s -match '^(.*?)=(.*)$') {
      $k = $matches[1].Trim()
      $v = $matches[2].Trim()
      if ((($v.Length -ge 2) -and ($v.StartsWith('"') -and $v.EndsWith('"'))) -or (($v.Length -ge 2) -and ($v.StartsWith("'") -and $v.EndsWith("'")))) {
        $v = $v.Substring(1, $v.Length - 2)
      }
      $map[$k] = $v
    }
  }
  return $map
}

# Given a repo name like 'fortifydocker/ssc-demo-webapp', try to find a tag in the versions map.
function Get-ImageTagFromVersions {
  param(
    [string]$Repo,
    [hashtable]$Versions
  )
  if (-not $Versions) { return $null }
  # Try direct key (case-insensitive)
  foreach ($k in $Versions.Keys) {
    if ($k.ToLower() -eq $Repo.ToLower()) { return $Versions[$k] }
  }
  # Try normalized forms: '/' -> '__', uppercase; also '-' -> '_' variant
  $norm1 = ($Repo -replace '/', '__').ToUpper()
  if ($Versions.ContainsKey($norm1)) { return $Versions[$norm1] }
  $norm2 = ($norm1 -replace '-', '_')
  if ($Versions.ContainsKey($norm2)) { return $Versions[$norm2] }
  # Special-case: if 'FORTIFYDOCKER' present, try inserting underscore 'FORTIFY_DOCKER'
  if ($norm1 -match '^FORTIFYDOCKER__(.+)$') {
    $alt = 'FORTIFY_DOCKER__' + $matches[1]
    if ($Versions.ContainsKey($alt)) { return $Versions[$alt] }
  }
  return $null
}
