# Wait for SSC to populate the MySQL database and reset SSC admin flags
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\reset_admin_after_ssc.ps1

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$repoRoot = Split-Path -Parent $scriptDir
$envFile = Join-Path $repoRoot 'demo.env'
if (-not (Test-Path $envFile)) { Write-Error "demo.env not found at $envFile"; exit 2 }

# Parse demo.env for MYSQL settings
$env = @{}
foreach ($line in Get-Content $envFile) {
  if ($line -match '^\s*([^#=\s]+)\s*=\s*(.*)$') {
    $env[$matches[1]] = $matches[2]
  }
}
$db = $env['MYSQL_DATABASE']
$user = $env['MYSQL_USER']
$pass = $env['MYSQL_PASSWORD']
if (-not $db -or -not $user -or -not $pass) { Write-Error 'Missing MYSQL_DATABASE / MYSQL_USER / MYSQL_PASSWORD in demo.env'; exit 2 }

Write-Host "Using DB=$db, USER=$user"

# Find a running MySQL container
$mysqlContainer = (& docker ps --format '{{.Names}} {{.Image}}') | ForEach-Object {
  if ($_ -match 'mysql') { ($_ -split ' ')[0] }
} | Select-Object -First 1
if (-not $mysqlContainer) {
  $mysqlContainer = (& docker ps --format '{{.Names}}') | Where-Object { $_ -match 'mysql' } | Select-Object -First 1
}
if (-not $mysqlContainer) { Write-Error 'Could not find a running MySQL container (name contains "mysql")'; exit 3 }
Write-Host "Found MySQL container: $mysqlContainer"

# Wait for MySQL server to accept connections
$timeout = 120
$ok = $false
for ($i=0; $i -lt $timeout; $i++) {
  try {
    & docker exec $mysqlContainer mysqladmin ping -u $user -p"$pass" --silent > $null 2>&1
    if ($LASTEXITCODE -eq 0) { $ok = $true; break }
  } catch {}
  Start-Sleep -Seconds 2
}
if (-not $ok) { Write-Error "MySQL did not become available within $timeout seconds"; exit 4 }
Write-Host 'MySQL is accepting connections.'

# Wait for the Fortify table 'fortifyuser' to exist (populated by SSC)
$timeout2 = 600
$found = $false
for ($i=0; $i -lt $timeout2; $i++) {
  try {
    $count = & docker exec $mysqlContainer mysql -u $user -p"$pass" -N -s -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$db' AND table_name='fortifyuser';"
    if ($count -and ([int]$count -gt 0)) { $found = $true; break }
  } catch {}
  Start-Sleep -Seconds 5
}
if (-not $found) { Write-Error "Table 'fortifyuser' not found in database '$db' after waiting $timeout2 seconds"; exit 5 }
Write-Host "Table 'fortifyuser' found. Proceeding to update admin user."

# Run the update SQL
$sql = "USE $db; UPDATE fortifyuser SET requirePasswordChange = 'N', failedLoginAttempts = 0, dateFrozen = NULL, suspended = 'N' WHERE userName = 'admin'; SELECT ROW_COUNT();"
Write-Host "Running SQL: $sql"
& docker exec -i $mysqlContainer mysql -u $user -p"$pass" -e $sql
$rc = $LASTEXITCODE
Write-Host "Update finished with exit code $rc"
exit $rc
