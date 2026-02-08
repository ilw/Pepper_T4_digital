param(
  [string]$Iverilog = "iverilog",
  [string]$Vvp      = "vvp",
  [string]$OutDir   = "simulation\\block_tb_runs",
  [switch]$Verbose
)

# IMPORTANT:
# Some PowerShell versions/environments treat any stderr output from native
# commands as terminating errors (even when exit code is 0). Icarus prints
# warnings on stderr, so we explicitly disable that behavior and rely only
# on exit codes + log scanning.
$ErrorActionPreference = "Continue"
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue) {
  $global:PSNativeCommandUseErrorActionPreference = $false
}

function Write-Info([string]$msg) { Write-Host $msg }

if (-not (Test-Path $OutDir)) {
  New-Item -ItemType Directory -Path $OutDir | Out-Null
}

# Collect block-level requirement testbenches
$tbs = Get-ChildItem -Path "testbenches" -Filter "tb_req_block_*.v" | Sort-Object Name
if ($tbs.Count -eq 0) {
  Write-Host "No block testbenches found under testbenches\\tb_req_block_*.v"
  exit 2
}

Write-Info ("Found {0} block testbenches." -f $tbs.Count)
Write-Info ""

$pass = 0
$fail = 0
$results = @()

foreach ($tb in $tbs) {
  $name = [IO.Path]::GetFileNameWithoutExtension($tb.Name)
  $vvpOut = Join-Path $OutDir ($name + ".vvp")
  $logOut = Join-Path $OutDir ($name + ".log")

  # Compile: include only DUT sources + this testbench.
  # (Do NOT include other testbenches to avoid multiple top modules.)
  $compileArgs = @(
    "-o", $vvpOut,
    "-Wall",
    $tb.FullName
  ) + (Get-ChildItem -Path "source" -Filter "*.v" | ForEach-Object { $_.FullName })

  # Some block TBs may depend on the ADC mock module definition.
  if (Test-Path "testbenches\\ns_sar_v2_mock.v") {
    $compileArgs += (Resolve-Path "testbenches\\ns_sar_v2_mock.v").Path
  }

  if ($Verbose) {
    Write-Info ("[compile] {0}" -f $name)
    Write-Info ("  {0} {1}" -f $Iverilog, ($compileArgs -join " "))
  } else {
    Write-Info ("[run] {0}" -f $name)
  }

  $compileOut = (& $Iverilog @compileArgs 2>&1)
  $compileExit = $LASTEXITCODE
  if ($compileExit -ne 0) {
    $fail++
    $compileOut | Out-File -FilePath $logOut -Encoding utf8
    $results += [pscustomobject]@{ tb = $name; status = "FAIL (compile)"; log = $logOut }
    Write-Info ("  FAIL (compile) -> {0}" -f $logOut)
    continue
  }

  # Run in non-interactive mode so $stop behaves like $finish.
  $simOut = (& $Vvp "-n" $vvpOut 2>&1)
  $simOut | Out-File -FilePath $logOut -Encoding utf8

  # Detect failures: any explicit "ERROR:" lines or common $display error markers.
  $hasError = ($simOut | Select-String -Pattern "ERROR:" -SimpleMatch -Quiet)

  if ($hasError) {
    $fail++
    $results += [pscustomobject]@{ tb = $name; status = "FAIL (ERROR: in sim)"; log = $logOut }
    Write-Info ("  FAIL (ERROR: in sim) -> {0}" -f $logOut)
  } else {
    $pass++
    $results += [pscustomobject]@{ tb = $name; status = "PASS"; log = $logOut }
    Write-Info ("  PASS -> {0}" -f $logOut)
  }
}

Write-Info ""
Write-Info ("Summary: PASS={0} FAIL={1}" -f $pass, $fail)

if ($fail -ne 0) {
  Write-Info ""
  Write-Info "Failures:"
  $results | Where-Object { $_.status -ne "PASS" } | ForEach-Object {
    Write-Info ("  - {0}: {1} ({2})" -f $_.tb, $_.status, $_.log)
  }
  exit 1
}

exit 0

