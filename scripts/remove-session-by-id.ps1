[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-fA-F-]{36}$')]
    [string]$SessionId,

    [Parameter()]
    [string]$CodexHome = $(if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME '.codex' }),

    [Parameter()]
    [switch]$Apply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# 整体说明：
# 这个脚本用于按会话 ID 预览或执行本地 Codex 会话清理。
# 设计原则是“先预览、再执行、绝不永久删除”：
# 1. 只修改少量高价值文件：session_index.jsonl 与 .codex-global-state.json
# 2. 只清理精确等于目标会话 ID 的引用，避免误伤普通文本
# 3. 会话文件只移动到 trash 目录，不做永久删除
# 4. 执行前先为会话索引和全局状态创建备份，便于手动回滚

# 这个哨兵对象用于在递归清理 JSON 时表示“这个节点应被移除”。
# 使用普通 .NET 对象并通过引用比较，避免 PSCustomObject 的值比较带来歧义。
$script:RemovedSentinel = [System.Object]::new()

# 记录所有被移除的精确引用路径，便于预览和审计。
$script:RemovedReferencePaths = [System.Collections.Generic.List[string]]::new()

function Resolve-CodexPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BasePath,

        [Parameter(Mandatory = $true)]
        [string]$ChildPath
    )

    # 用显式路径拼接和解析，避免相对路径带来的歧义。
    return [System.IO.Path]::GetFullPath((Join-Path -Path $BasePath -ChildPath $ChildPath))
}

function Assert-CodexHome {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    # 这里要求 Codex 根目录必须真实存在，否则后续所有路径判断都不可靠。
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "Codex home not found: $Path"
    }
}

function Test-IsRemovedSentinel {
    param(
        [AllowNull()]
        $Value
    )

    # 这里必须用引用相等而不是 -eq，确保只识别脚本内部创建的唯一哨兵对象。
    return [System.Object]::ReferenceEquals($Value, $script:RemovedSentinel)
}

function Get-SessionFiles {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath,

        [Parameter(Mandatory = $true)]
        [string]$TargetSessionId
    )

    $results = @()
    foreach ($relativeDir in @('sessions', 'archived_sessions')) {
        $searchRoot = Resolve-CodexPath -BasePath $RootPath -ChildPath $relativeDir
        if (-not (Test-Path -LiteralPath $searchRoot -PathType Container)) {
            continue
        }

        # 只搜文件名中包含目标会话 ID 的 JSONL 会话文件。
        $matches = Get-ChildItem -Path $searchRoot -Recurse -File |
            Where-Object { $_.Name -like "*$TargetSessionId*" -and $_.Extension -eq '.jsonl' }

        foreach ($file in $matches) {
            $results += [pscustomobject]@{
                Scope    = $relativeDir
                FullPath = $file.FullName
            }
        }
    }

    return $results
}

function Get-SessionIndexPlan {
    param(
        [Parameter(Mandatory = $true)]
        [string]$IndexPath,

        [Parameter(Mandatory = $true)]
        [string]$TargetSessionId
    )

    if (-not (Test-Path -LiteralPath $IndexPath -PathType Leaf)) {
        return [pscustomobject]@{
            Exists          = $false
            RemovedCount    = 0
            MatchingRecords = @()
            OutputLines     = @()
        }
    }

    $originalLines = Get-Content -LiteralPath $IndexPath
    $outputLines = New-Object System.Collections.Generic.List[string]
    $matchingRecords = New-Object System.Collections.Generic.List[object]

    foreach ($line in $originalLines) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            $outputLines.Add($line) | Out-Null
            continue
        }

        $parsed = $null
        try {
            $parsed = $line | ConvertFrom-Json -Depth 20
        }
        catch {
            # 遇到无法解析的行时不擅自丢弃，保持原样，避免破坏未知格式。
            $outputLines.Add($line) | Out-Null
            continue
        }

        if ($null -ne $parsed -and $parsed.PSObject.Properties.Name -contains 'id' -and $parsed.id -eq $TargetSessionId) {
            $matchingRecords.Add($parsed) | Out-Null
            continue
        }

        $outputLines.Add($line) | Out-Null
    }

    return [pscustomobject]@{
        Exists          = $true
        RemovedCount    = $matchingRecords.Count
        MatchingRecords = $matchingRecords.ToArray()
        OutputLines     = $outputLines.ToArray()
    }
}

function Remove-ExactSessionReference {
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        $Value,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$TargetSessionId
    )

    if ($null -eq $Value) {
        return $null
    }

    if ($Value -is [string]) {
        # 只删除“值完全等于目标会话 ID”的字符串；包含该 ID 的普通文本不动。
        if ($Value -eq $TargetSessionId) {
            $script:RemovedReferencePaths.Add($Path) | Out-Null
            return $script:RemovedSentinel
        }

        return $Value
    }

    if ($Value -is [System.Collections.IDictionary]) {
        $result = [ordered]@{}
        foreach ($entry in $Value.GetEnumerator()) {
            $childKey = [string]$entry.Key
            $childPath = if ([string]::IsNullOrEmpty($Path)) { $childKey } else { "$Path.$childKey" }

            # 如果对象键本身就是目标会话 ID，直接移除整个属性。
            if ($childKey -eq $TargetSessionId) {
                $script:RemovedReferencePaths.Add($childPath) | Out-Null
                continue
            }

            try {
                $cleaned = Remove-ExactSessionReference -Value $entry.Value -Path $childPath -TargetSessionId $TargetSessionId
            }
            catch {
                $valueType = if ($null -eq $entry.Value) { '<null>' } else { $entry.Value.GetType().FullName }
                throw "Failed to clean dictionary node '$childPath' of type '$valueType': $($_.Exception.Message)"
            }

            if (Test-IsRemovedSentinel -Value $cleaned) {
                continue
            }

            $result[$childKey] = $cleaned
        }

        return [pscustomobject]$result
    }

    if ($Value -is [pscustomobject]) {
        $result = [ordered]@{}
        foreach ($property in $Value.PSObject.Properties) {
            $childKey = [string]$property.Name
            $childPath = if ([string]::IsNullOrEmpty($Path)) { $childKey } else { "$Path.$childKey" }

            if ($childKey -eq $TargetSessionId) {
                $script:RemovedReferencePaths.Add($childPath) | Out-Null
                continue
            }

            try {
                $cleaned = Remove-ExactSessionReference -Value $property.Value -Path $childPath -TargetSessionId $TargetSessionId
            }
            catch {
                $valueType = if ($null -eq $property.Value) { '<null>' } else { $property.Value.GetType().FullName }
                throw "Failed to clean object node '$childPath' of type '$valueType': $($_.Exception.Message)"
            }

            if (Test-IsRemovedSentinel -Value $cleaned) {
                continue
            }

            $result[$childKey] = $cleaned
        }

        return [pscustomobject]$result
    }

    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
        $items = New-Object System.Collections.Generic.List[object]
        $index = 0
        foreach ($item in $Value) {
            $childPath = if ([string]::IsNullOrEmpty($Path)) { "[{0}]" -f $index } else { "{0}[{1}]" -f $Path, $index }
            try {
                $cleaned = Remove-ExactSessionReference -Value $item -Path $childPath -TargetSessionId $TargetSessionId
            }
            catch {
                $valueType = if ($null -eq $item) { '<null>' } else { $item.GetType().FullName }
                throw "Failed to clean array node '$childPath' of type '$valueType': $($_.Exception.Message)"
            }

            if (-not (Test-IsRemovedSentinel -Value $cleaned)) {
                $items.Add($cleaned) | Out-Null
            }

            $index += 1
        }

        # 用一元逗号保留数组形态，避免单元素数组在函数返回时被自动拆箱成标量。
        return ,($items.ToArray())
    }

    # 对于数字、布尔等标量，保持原样。
    return $Value
}

function Get-GlobalStatePlan {
    param(
        [Parameter(Mandatory = $true)]
        [string]$GlobalStatePath,

        [Parameter(Mandatory = $true)]
        [string]$TargetSessionId
    )

    if (-not (Test-Path -LiteralPath $GlobalStatePath -PathType Leaf)) {
        return [pscustomobject]@{
            Exists               = $false
            RemovedReferenceCount = 0
            RemovedReferencePaths = @()
            OutputText           = $null
        }
    }

    $script:RemovedReferencePaths.Clear()
    $originalText = Get-Content -LiteralPath $GlobalStatePath -Raw
    $parsed = $originalText | ConvertFrom-Json -Depth 100
    $cleaned = Remove-ExactSessionReference -Value $parsed -Path '' -TargetSessionId $TargetSessionId
    $outputText = $cleaned | ConvertTo-Json -Depth 100

    return [pscustomobject]@{
        Exists                = $true
        RemovedReferenceCount = $script:RemovedReferencePaths.Count
        RemovedReferencePaths = $script:RemovedReferencePaths.ToArray()
        OutputText            = $outputText
    }
}

function New-TrashPlan {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath,

        [Parameter(Mandatory = $true)]
        [string]$TargetSessionId
    )

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $trashRoot = Resolve-CodexPath -BasePath $RootPath -ChildPath ("trash\session-cleaner\{0}-{1}" -f $timestamp, $TargetSessionId)

    return [pscustomobject]@{
        TrashRoot       = $trashRoot
        BackupDirectory = Join-Path $trashRoot 'backups'
        SessionFileRoot = Join-Path $trashRoot 'session-files'
        ManifestPath    = Join-Path $trashRoot 'cleanup-manifest.json'
    }
}

function Write-PlanJson {
    param(
        [Parameter(Mandatory = $true)]
        $Plan
    )

    $publicPlan = [pscustomobject]@{
        Mode         = $Plan.Mode
        SessionId    = $Plan.SessionId
        CodexHome    = $Plan.CodexHome
        Paths        = $Plan.Paths
        SessionFiles = @(
            foreach ($sessionFile in $Plan.SessionFiles) {
                [pscustomobject]@{
                    Scope    = $sessionFile.Scope
                    FullPath = $sessionFile.FullPath
                }
            }
        )
        SessionIndex = [pscustomobject]@{
            Exists          = $Plan.SessionIndex.Exists
            RemovedCount    = $Plan.SessionIndex.RemovedCount
            MatchingRecords = @(
                foreach ($record in $Plan.SessionIndex.MatchingRecords) {
                    [pscustomobject]@{
                        id          = $record.id
                        thread_name = $record.thread_name
                        updated_at  = $record.updated_at
                    }
                }
            )
        }
        GlobalState = [pscustomobject]@{
            Exists                = $Plan.GlobalState.Exists
            RemovedReferenceCount = $Plan.GlobalState.RemovedReferenceCount
            RemovedReferencePaths = $Plan.GlobalState.RemovedReferencePaths
        }
        Trash   = $Plan.Trash
        Summary = $Plan.Summary
    }

    $publicPlan | ConvertTo-Json -Depth 100
}

function Invoke-ApplyPlan {
    param(
        [Parameter(Mandatory = $true)]
        $Plan
    )

    # 先创建 trash 目录，再备份关键文件，最后改写索引并移动会话文件。
    New-Item -ItemType Directory -Path $Plan.Trash.BackupDirectory -Force | Out-Null
    New-Item -ItemType Directory -Path $Plan.Trash.SessionFileRoot -Force | Out-Null

    if ($Plan.SessionIndex.Exists) {
        Copy-Item -LiteralPath $Plan.Paths.SessionIndexPath -Destination (Join-Path $Plan.Trash.BackupDirectory 'session_index.jsonl.bak')
        Set-Content -LiteralPath $Plan.Paths.SessionIndexPath -Value $Plan.SessionIndex.OutputLines -Encoding utf8
    }

    if ($Plan.GlobalState.Exists) {
        Copy-Item -LiteralPath $Plan.Paths.GlobalStatePath -Destination (Join-Path $Plan.Trash.BackupDirectory '.codex-global-state.json.bak')
        Set-Content -LiteralPath $Plan.Paths.GlobalStatePath -Value $Plan.GlobalState.OutputText -Encoding utf8
    }

    foreach ($sessionFile in $Plan.SessionFiles) {
        $scopeDirectory = Join-Path $Plan.Trash.SessionFileRoot $sessionFile.Scope
        New-Item -ItemType Directory -Path $scopeDirectory -Force | Out-Null
        Move-Item -LiteralPath $sessionFile.FullPath -Destination (Join-Path $scopeDirectory ([System.IO.Path]::GetFileName($sessionFile.FullPath)))
    }

    Set-Content -LiteralPath $Plan.Trash.ManifestPath -Value (Write-PlanJson -Plan $Plan) -Encoding utf8
}

Assert-CodexHome -Path $CodexHome

$paths = [pscustomobject]@{
    SessionIndexPath = Resolve-CodexPath -BasePath $CodexHome -ChildPath 'session_index.jsonl'
    GlobalStatePath  = Resolve-CodexPath -BasePath $CodexHome -ChildPath '.codex-global-state.json'
}

$sessionFiles = Get-SessionFiles -RootPath $CodexHome -TargetSessionId $SessionId
$sessionIndexPlan = Get-SessionIndexPlan -IndexPath $paths.SessionIndexPath -TargetSessionId $SessionId
$globalStatePlan = Get-GlobalStatePlan -GlobalStatePath $paths.GlobalStatePath -TargetSessionId $SessionId
$trashPlan = New-TrashPlan -RootPath $CodexHome -TargetSessionId $SessionId

$plan = [pscustomobject]@{
    Mode         = if ($Apply) { 'apply' } else { 'preview' }
    SessionId    = $SessionId
    CodexHome    = [System.IO.Path]::GetFullPath($CodexHome)
    Paths        = $paths
    SessionFiles = @($sessionFiles)
    SessionIndex = $sessionIndexPlan
    GlobalState  = $globalStatePlan
    Trash        = $trashPlan
    Summary      = [pscustomobject]@{
        SessionFileCount          = $sessionFiles.Count
        SessionIndexRemovedCount  = $sessionIndexPlan.RemovedCount
        GlobalStateReferenceCount = $globalStatePlan.RemovedReferenceCount
    }
}

if ($Apply) {
    # 边界条件：如果完全没有命中任何文件或引用，拒绝做空写入，避免制造无意义变更。
    if (
        $plan.Summary.SessionFileCount -eq 0 -and
        $plan.Summary.SessionIndexRemovedCount -eq 0 -and
        $plan.Summary.GlobalStateReferenceCount -eq 0
    ) {
        throw "No matching session files or exact references found for session ID: $SessionId"
    }

    Invoke-ApplyPlan -Plan $plan
}

Write-PlanJson -Plan $plan
