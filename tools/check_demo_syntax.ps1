$tokens = $null
$errors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile('c:\Users\klee2\repos\fortify-docker-demo\demo.ps1',[ref]$tokens,[ref]$errors)
if ($errors) {
  $errors | ForEach-Object { Write-Host $_.Message -ForegroundColor Red }
  exit 2
} else {
  Write-Host 'Syntax OK' -ForegroundColor Green
}
