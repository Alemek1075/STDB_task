<#
.SYNOPSIS
  Local PostgreSQL cluster for the project (no Docker, no password).

.DESCRIPTION
  The cluster lives in .pgdata/ (gitignored), listens on localhost:5433, trust auth.
  Your system-wide PostgreSQL service is not touched.

  ./scripts/db.ps1 init      create the cluster (once)
  ./scripts/db.ps1 start     start the server
  ./scripts/db.ps1 stop      stop the server
  ./scripts/db.ps1 status    is it running?
  ./scripts/db.ps1 deploy    drop + recreate database "university" and run db/*.sql in order
  ./scripts/db.ps1 psql      open psql on the database
  ./scripts/db.ps1 run FILE  run one SQL file (e.g. db/demo/05_programmability_demo.sql)
#>
param(
    [Parameter(Position = 0)] [ValidateSet('init', 'start', 'stop', 'status', 'deploy', 'psql', 'run')] [string] $Command = 'status',
    [Parameter(Position = 1)] [string] $File
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path $PSScriptRoot -Parent
$Data = Join-Path $Root '.pgdata'
$Log  = Join-Path $Root 'pg.log'
$Port = 5433
$Db   = 'university'
$env:PGCLIENTENCODING = 'UTF8'   # SQL files are UTF-8 (Cyrillic seed data)

function Find-PgBin {
    if ($env:PG_BIN) { return $env:PG_BIN }
    $dir = Get-ChildItem 'C:\Program Files\PostgreSQL\*\bin\pg_ctl.exe' -ErrorAction SilentlyContinue |
        Sort-Object { [int]($_.Directory.Parent.Name -replace '\D', '') } -Descending |
        Select-Object -First 1
    if (-not $dir) { throw 'PostgreSQL binaries not found. Set $env:PG_BIN to the folder with pg_ctl.exe' }
    return $dir.DirectoryName
}

$Bin = Find-PgBin
function Pg([string] $exe) { Join-Path $Bin "$exe.exe" }
$Conn = @('-h', 'localhost', '-p', $Port, '-U', 'postgres')

switch ($Command) {
    'init' {
        if (Test-Path $Data) { Write-Host 'Cluster already exists in .pgdata'; break }
        & (Pg initdb) -D $Data -U postgres -A trust -E UTF8 --locale-provider=icu --icu-locale=uk-UA --locale=en-US
        Add-Content (Join-Path $Data 'postgresql.auto.conf') "port = $Port"
        Write-Host "Cluster created. Next: ./scripts/db.ps1 start; ./scripts/db.ps1 deploy"
    }
    'start'  { & (Pg pg_ctl) -D $Data -l $Log -w start }
    'stop'   { & (Pg pg_ctl) -D $Data -w stop }
    'status' { & (Pg pg_ctl) -D $Data status; & (Pg pg_isready) @Conn }
    'deploy' {
        & (Pg dropdb) @Conn --if-exists --force $Db
        & (Pg createdb) @Conn $Db
        Get-ChildItem (Join-Path $Root 'db\*.sql') | Sort-Object Name | ForEach-Object {
            Write-Host "-> $($_.Name)"
            & (Pg psql) @Conn -d $Db -v ON_ERROR_STOP=1 -q -f $_.FullName
            if ($LASTEXITCODE -ne 0) { throw "Failed on $($_.Name)" }
        }
        Write-Host "Database '$Db' deployed on localhost:$Port"
    }
    'psql' { & (Pg psql) @Conn -d $Db }
    'run'  {
        if (-not $File) { throw 'Usage: ./scripts/db.ps1 run <file.sql>' }
        & (Pg psql) @Conn -d $Db -v ON_ERROR_STOP=1 -f (Resolve-Path $File)
    }
}
