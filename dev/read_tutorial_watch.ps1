param(
    [string]$OutDir = '.verification/tutorial_watch',
    [switch]$Details
)

# Read one small snapshot, not the game log or a stream of screenshots.
$snapshotPath = Join-Path $OutDir 'state.json'
if (-not (Test-Path -LiteralPath $snapshotPath)) {
    Write-Output "NO SNAPSHOT: $snapshotPath"
    exit 2
}
try {
    $snapshot = Get-Content -LiteralPath $snapshotPath -Raw | ConvertFrom-Json
} catch {
    Write-Output 'Snapshot is being written or is invalid; retry the read.'
    exit 2
}
if ($Details) {
    $snapshot | ConvertTo-Json -Compress -Depth 5
    exit 0
}
'{0} {1}/{2} {3} | d{4} {5} speed={6} held={7} | {8}g staff={9} guests={10} served={11} blueprints={12}' -f `
    $snapshot.status, $snapshot.index, $snapshot.total, $snapshot.step, $snapshot.day, `
    $snapshot.clock, $snapshot.speed, $snapshot.held, $snapshot.gold, $snapshot.staff, `
    $snapshot.guests, $snapshot.served, $snapshot.blueprints
if ($snapshot.status -eq 'RUNNING' -and $snapshot.updated_unix -and
    ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - $snapshot.updated_unix) -gt 10) {
    Write-Output 'STALE: snapshot is over 10 seconds old; check the process/log.'
}
'Next: ' + $snapshot.instruction
if ($snapshot.trouble) { 'Trouble: ' + $snapshot.trouble }
