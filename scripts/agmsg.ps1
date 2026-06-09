param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]] $AgmsgArgs
)

$ErrorActionPreference = "Stop"
$Client = Join-Path $PSScriptRoot "agmsg-client.mjs"

node $Client @AgmsgArgs
exit $LASTEXITCODE
