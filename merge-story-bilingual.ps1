# merge-story-bilingual.ps1
# 用途：以「已安装的都市零协中文语言包」为中文源、以游戏自带的官方英文（Localize\en）为英文源，
#       生成一个自定义语言包；只对「剧情类文本」做成「英文 + 换行 + 中文」，其余文件保持中文单语。
#
# 关键差异（相对旧的 merge-bilingual.ps1）：
#   1) 中文源换成已安装语言包（发布仓 CN\ 落后，缺第八/九/十章）。
#   2) 双语范围由 -ModeFile（StoryFields.json）声明：路径 glob -> 允许双语的字段名白名单。
#      未命中的文件整份保持中文（操作界面、战斗标识/状态、技能介绍本体都不动）。
#
# 用法示例：
#   & .\merge-story-bilingual.ps1 -OfficialEnDir "D:\...\Localize\en" `
#       -InstalledCnDir "D:\...\Lang\LLC_zh-CN" `
#       -ReleaseCnDir   "H:\...\release-src\LLC_Release-main\CN" `
#       -ReleaseEnDir   "H:\...\release-src\LLC_Release-main\EN" `
#       -ModeFile "H:\workspace\limbus-l10n\StoryFields.json" `
#       -OutDir "H:\workspace\limbus-l10n\out\LLC_bilingual"
param(
    [Parameter(Mandatory = $true)][string]$OfficialEnDir,
    [Parameter(Mandatory = $true)][string]$InstalledCnDir,
    [Parameter(Mandatory = $true)][string]$OutDir,
    [Parameter(Mandatory = $true)][string]$ModeFile,
    [string]$ReleaseCnDir = '',
    [string]$ReleaseEnDir = '',
    [string]$Separator = "`n",
    [int]$Limit = 0,
    [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)

# ---------- 日志：一律走 Write-Host，避免污染函数返回值 ----------
function Log([string]$m) { Write-Host $m }
function LogStep([string]$m) { Write-Host $m }

Add-Type -AssemblyName System.Web.Extensions

function New-Serializer {
    $s = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    $s.MaxJsonLength = [int]::MaxValue
    $s.RecursionLimit = 512
    return $s
}
$script:Ser = New-Serializer

function Read-JsonFile([string]$path) {
    $txt = [System.IO.File]::ReadAllText($path)
    return $script:Ser.DeserializeObject($txt)
}

# ---------- 自写序列化：JavaScriptSerializer 序列化 PowerShell 对象会报 PSMethod 循环引用 ----------
function Get-EscapedString([string]$s) {
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $s.ToCharArray()) {
        $c = [int]$ch
        switch ($ch) {
            '"'  { [void]$sb.Append('\"') }
            '\'  { [void]$sb.Append('\\') }
            "`b" { [void]$sb.Append('\b') }
            "`f" { [void]$sb.Append('\f') }
            "`n" { [void]$sb.Append('\n') }
            "`r" { [void]$sb.Append('\r') }
            "`t" { [void]$sb.Append('\t') }
            default {
                if ($c -lt 32 -or $c -eq 127) { [void]$sb.Append('\u' + $c.ToString('x4')) }
                else { [void]$sb.Append($ch) }
            }
        }
    }
    return $sb.ToString()
}

function Test-IsDict($v) {
    return (($v -is [System.Collections.IDictionary]) -and -not ($v -is [System.Collections.IList]))
}
function Test-IsList($v) {
    return (($v -is [System.Collections.IList]) -and -not ($v -is [System.Collections.IDictionary]))
}

function ConvertTo-JsonText($v) {
    if ($null -eq $v) { return 'null' }
    if ($v -is [string]) { return '"' + (Get-EscapedString $v) + '"' }
    if ($v -is [bool]) { if ($v) { return 'true' } else { return 'false' } }
    if ($v -is [decimal] -or $v -is [double] -or $v -is [single]) {
        return ([System.Convert]::ToString($v, [System.Globalization.CultureInfo]::InvariantCulture))
    }
    if ($v -is [int] -or $v -is [long] -or $v -is [int16] -or $v -is [byte] -or $v -is [int64]) {
        return ([string]$v)
    }
    if (Test-IsDict $v) {
        $parts = New-Object System.Collections.ArrayList
        foreach ($k in $v.Keys) {
            $ks = if ($k -is [string]) { $k } else { [string]$k }
            [void]$parts.Add('"' + (Get-EscapedString $ks) + '":' + (ConvertTo-JsonText $v[$k]))
        }
        return '{' + ($parts -join ',') + '}'
    }
    if (Test-IsList $v) {
        $parts = New-Object System.Collections.ArrayList
        foreach ($e in $v) { [void]$parts.Add((ConvertTo-JsonText $e)) }
        return '[' + ($parts -join ',') + ']'
    }
    # 兜底
    return ([string]$v)
}

# ---------- 合并核心 ----------
function Join-Text($en, $cn, [string]$sep) {
    $a = if ($null -eq $en) { '' } else { [string]$en }
    $b = if ($null -eq $cn) { '' } else { [string]$cn }
    if ([string]::IsNullOrEmpty($a)) { return $b }
    if ([string]::IsNullOrEmpty($b)) { return $a }
    if ($a -eq $b) { return $a }
    return $a + $sep + $b
}

function Test-Key($obj, [string]$name) {
    if ($null -eq $obj) { return $false }
    try { return [bool]$obj.ContainsKey([string]$name) }
    catch {
        try { return [bool]$obj.Contains([string]$name) }
        catch { return $false }
    }
}

# 取数组条目用于对齐的键名（优先 id，其次 fileName）；返回 ,$key 或 ,$null
function Get-ArrayKeyName($arr) {
    if ($null -eq $arr) { return , $null }
    if (-not (Test-IsList $arr)) { return , $null }
    if ($arr.Count -eq 0) { return , $null }
    $cand = @('id', 'fileName')
    foreach ($c in $cand) {
        $ok = $true
        foreach ($e in $arr) {
            if (-not (Test-IsDict $e)) { $ok = $false; break }
            if (-not (Test-Key $e $c)) { $ok = $false; break }
        }
        if ($ok) { return , $c }
    }
    return , $null
}

function Get-KeyedIndex($arr, [string]$keyName) {
    $h = @{}
    if ($null -eq $arr) { return $h }
    for ($i = 0; $i -lt $arr.Count; $i++) {
        $e = $arr[$i]
        if (Test-IsDict $e) {
            if (Test-Key $e $keyName) {
                $ks = [string]$e[$keyName]
                if (-not $h.ContainsKey($ks)) { $h[$ks] = $i }
            }
        }
    }
    return $h
}

# 双语化的通用实现：fields=允许双语的字段名（小写匹配，$null 表示全部字符串字段）
function Merge-Value($en, $cn, [string]$path, $fields) {

    if ((-not (Test-IsDict $en)) -and (-not (Test-IsList $en)) -and (-not (Test-IsDict $cn)) -and (-not (Test-IsList $cn))) {
        $script:Stat.textSeen++
        $joined = Join-Text $en $cn $script:Sep
        if (($en -is [string]) -and ($cn -is [string])) {
            if ([string]::IsNullOrEmpty([string]$en)) { $script:Stat.textCnOnly++ }
            elseif ([string]::IsNullOrEmpty([string]$cn)) { $script:Stat.textEnOnly++ }
            elseif ([string]$en -eq [string]$cn) { $script:Stat.textIdentical++ }
            else { $script:Stat.textMerged++ }
        }
        return $joined
    }
    if ((Test-IsDict $en) -and (-not (Test-IsDict $cn))) { $cn = $null }
    if ((Test-IsList $en) -and (-not (Test-IsList $cn))) { $cn = $null }
    if ($null -eq $en -and $null -eq $cn) { return (New-Object System.Collections.ArrayList) }

    if (Test-IsDict $en) {

        $out = @{}
        $cnDict = if (Test-IsDict $cn) { $cn } else { $null }
        foreach ($k in $en.Keys) {
            $ks = [string]$k
            $childPath = $path + '/' + $ks
            $ev = $en[$k]
            $cv = if (($null -ne $cnDict) -and (Test-Key $cnDict $ks)) { $cnDict[$ks] } else { $null }
            # 容器（对象/数组）一律继续递归；字段白名单与排除表只决定标量文本是否双语
            if ((Test-IsDict $ev) -or (Test-IsList $ev)) {
                $out[$ks] = Merge-Value $ev $cv $childPath $fields
            }
            elseif (Test-FieldAllowed $ks $fields) {
                $out[$ks] = Merge-Value $ev $cv $childPath $null
            }
            else {
                # 语言无关字段（id / codeName / model 等）：保留英文侧原值
                $out[$ks] = $ev
            }
        }
        # 中文侧独有的键：补进来（只可能出现在允许双语的情形）
        if ($null -ne $cnDict) {
            foreach ($k in $cnDict.Keys) {
                $ks = [string]$k
                if (-not $out.ContainsKey($ks)) {
                    $script:Stat.keyCnExtra++
                    $out[$ks] = $cnDict[$k]
                }
            }
        }
        return $out
    }

    if (Test-IsList $en) {

        $cnList = if (Test-IsList $cn) { $cn } else { $null }
        $kn = Get-ArrayKeyName $en
        if ($null -eq $kn) { $kn = Get-ArrayKeyName $cnList }
        # 先判断是否「按 id 一一对齐」：条数相同、且每个位置两侧的 id 都相等（或两侧都没有该键）。
        # 这种情况一律按下标合并——这是唯一能正确处理重复 id 的办法（例如 P10916.json 里有两个 id=4）。
        $idAligned = $false
        if (($null -ne $kn) -and ($null -ne $cnList) -and ($en.Count -eq $cnList.Count)) {
            $idAligned = $true
            for ($i = 0; $i -lt $en.Count; $i++) {
                $he = (Test-IsDict $en[$i]) -and (Test-Key $en[$i] $kn)
                $hc = (Test-IsDict $cnList[$i]) -and (Test-Key $cnList[$i] $kn)
                if ($he -ne $hc) { $idAligned = $false; break }
                if ($he -and ([string]$en[$i][$kn] -ne [string]$cnList[$i][$kn])) { $idAligned = $false; break }
            }
        }
        if ($idAligned) {
            $out = New-Object System.Collections.ArrayList
            for ($i = 0; $i -lt $en.Count; $i++) {
                [void]$out.Add((Merge-Value $en[$i] $cnList[$i] ($path + '[' + $i + ']') $fields))
            }
            return , $out
        }
        if ($null -ne $kn) {
            # 混合数组（部分条目没有键，例如 StoryData 里 id=-1 的旁白/音效条目）：
            # 有键的按 id 对齐；没有键的按「无键条目内的相对下标」对齐。
            # 注意绝不能把无键条目的下标拿来当键，否则所有无键条目会互相错配。
            $cnIdx = Get-KeyedIndex $cnList $kn
            $used = @{}
            $out = New-Object System.Collections.ArrayList
            $iUnkeyed = 0
            foreach ($e in $en) {
                $ks = $null
                if ((Test-IsDict $e) -and (Test-Key $e $kn)) { $ks = [string]$e[$kn] }
                $ce = $null
                if ($null -ne $ks) {
                    if ($cnIdx.ContainsKey($ks)) { $ce = $cnList[$cnIdx[$ks]]; $used[$ks] = $true }
                    $label = $ks
                }
                else {
                    # 无键条目：在中文侧找第 $iUnkeyed 个同样没有该键的条目
                    $seen = 0
                    if ($null -ne $cnList) {
                        foreach ($c in $cnList) {
                            if ((Test-IsDict $c) -and -not (Test-Key $c $kn)) {
                                if ($seen -eq $iUnkeyed) { $ce = $c; break }
                                $seen++
                            }
                        }
                    }
                    $label = 'u' + $iUnkeyed
                    $iUnkeyed++
                }
                [void]$out.Add((Merge-Value $e $ce ($path + '[' + $label + ']') $fields))
            }
            # 中文侧独有条目追加到末尾（没被用掉的键条目 + 多出来的无键条目）
            if ($null -ne $cnList) {
                $cnUnkeyedTotal = 0
                foreach ($c in $cnList) { if ((Test-IsDict $c) -and -not (Test-Key $c $kn)) { $cnUnkeyedTotal++ } }
                $iUnkeyed2 = 0
                foreach ($c in $cnList) {
                    if ((Test-IsDict $c) -and -not (Test-Key $c $kn)) {
                        $isExtra = $iUnkeyed2 -ge $iUnkeyed
                        $iUnkeyed2++
                        if (-not $isExtra) { continue }
                        $script:Stat.arrCnExtra++
                        [void]$out.Add($c)
                        continue
                    }
                    $ks = $null
                    if ((Test-IsDict $c) -and (Test-Key $c $kn)) { $ks = [string]$c[$kn] }
                    if (($null -ne $ks) -and $used.ContainsKey($ks)) { continue }
                    $script:Stat.arrCnExtra++
                    [void]$out.Add($c)
                }
            }
            return , $out
        }
        # 完全无键数组：按下标配对
        $out = New-Object System.Collections.ArrayList
        $n = [Math]::Max($en.Count, $(if ($null -ne $cnList) { $cnList.Count } else { 0 }))
        for ($i = 0; $i -lt $n; $i++) {
            $ev = if ($i -lt $en.Count) { $en[$i] } else { $null }
            $cv = if (($null -ne $cnList) -and ($i -lt $cnList.Count)) { $cnList[$i] } else { $null }
            [void]$out.Add((Merge-Value $ev $cv ($path + '[' + $i + ']') $fields))
        }
        return , $out
    }

    # en 是标量而 cn 是结构（罕见）：以 cn 为准
    return $cn
}

function Write-Utf8File([string]$path, [string]$text) {
    $dir = [System.IO.Path]::GetDirectoryName($path)
    if (-not [System.IO.Directory]::Exists($dir)) { [void][System.IO.Directory]::CreateDirectory($dir) }
    $enc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($path, $text, $enc)
}

# 把「范围声明的字段白名单」与「全局排除字段」合成真正的判定表
# 返回 $null 表示除排除字段外全部双语；否则返回允许双语的字段数组
function Get-EffectiveFields($declared) {
    if ($null -ne $declared) { return $declared }
    return $null
}
function Test-FieldAllowed([string]$name, $declared) {
    $n = $name.ToLowerInvariant()
    foreach ($e in $script:ExcludeFields) { if ($e -eq $n) { return $false } }
    if ($null -eq $declared) { return $true }
    foreach ($f in $declared) { if (([string]$f).ToLowerInvariant() -eq $n) { return $true } }
    return $false
}function Test-Glob([string]$pattern, [string]$name) {
    $p = $pattern.Replace('/', '\')
    $n = $name.Replace('/', '\')
    if ($p -eq $n) { return $true }
    if ($p -notmatch '[\*\?]') { return $false }
    $rx = '^' + [regex]::Escape($p).Replace('\*', '.*').Replace('\?', '.') + '$'
    return [bool]($n -match $rx)
}

# ---------- 载入模式文件 ----------
$mode = Read-JsonFile $ModeFile
$excludeFields = @()
if ($null -ne $mode.excludeFields) { $excludeFields = @($mode.excludeFields | ForEach-Object { ([string]$_).ToLowerInvariant() }) }
$scopes = @()
foreach ($s in $mode.scopes) {
    $flds = $null
    if ($null -ne $s.fields) { $flds = @($s.fields) }
    $scopes += [pscustomobject]@{ pattern = [string]$s.pattern; fields = $flds }
}
$defaultFields = $null
if ($null -ne $mode.defaultFields) { $defaultFields = @($mode.defaultFields) }
Log "模式文件：$ModeFile"
Log ("双语范围规则 " + $scopes.Count + " 条；默认字段白名单：" + $(if ($null -eq $defaultFields) { '(全部)' } else { ($defaultFields -join ',') }))
foreach ($s in $scopes) {
    Log ("  " + $s.pattern + "  ->  " + $(if ($null -eq $s.fields) { '(全部字段)' } else { ($s.fields -join ',') }))
}

$script:ExcludeFields = $excludeFields
$script:Sep = $Separator
$script:Stat = [ordered]@{
    filesConsidered = 0; filesWritten = 0; filesCopiedCn = 0; filesSkippedNoCn = 0
    filesBilingual = 0; filesCnOnly = 0; textSeen = 0; textMerged = 0; textEnOnly = 0
    textCnOnly = 0; textIdentical = 0; keyCnExtra = 0; arrCnExtra = 0
    filesWithEnglish = 0; filesWithoutEnglish = 0
}

# ---------- 建立官方英文索引（去 EN_ 前缀） ----------
LogStep '--- 建立官方英文索引 ---'
$enIndex = @{}
foreach ($f in [System.IO.Directory]::GetFiles($OfficialEnDir, '*.json', [System.IO.SearchOption]::AllDirectories)) {
    $rel = $f.Substring($OfficialEnDir.Length).TrimStart('\')
    $d = [System.IO.Path]::GetDirectoryName($rel)
    $b = [System.IO.Path]::GetFileName($rel)
    if ($b -like 'EN_*') { $b = $b.Substring(3) }
    $lg = if ([string]::IsNullOrEmpty($d)) { $b } else { "$d\$b" }
    if (-not $enIndex.ContainsKey($lg)) { $enIndex[$lg] = $f }
}
Log ("官方英文本地化逻辑文件数：" + $enIndex.Count)

# ---------- 建立中文索引（已安装包 + 发布仓 CN 的独有文件） ----------
LogStep '--- 建立中文索引 ---'
$cnIndex = [ordered]@{}
foreach ($f in [System.IO.Directory]::GetFiles($InstalledCnDir, '*.json', [System.IO.SearchOption]::AllDirectories)) {
    $rel = $f.Substring($InstalledCnDir.Length).TrimStart('\')
    if (-not $cnIndex.Contains($rel)) { $cnIndex[$rel] = $f }
}
$instCount = $cnIndex.Count
$extraCn = 0
if (-not [string]::IsNullOrEmpty($ReleaseCnDir) -and [System.IO.Directory]::Exists($ReleaseCnDir)) {
    foreach ($f in [System.IO.Directory]::GetFiles($ReleaseCnDir, '*.json', [System.IO.SearchOption]::AllDirectories)) {
        $rel = $f.Substring($ReleaseCnDir.Length).TrimStart('\')
        if (-not $cnIndex.Contains($rel)) { $cnIndex[$rel] = $f; $extraCn++ }
    }
}
Log ("中文源：已安装包 " + $instCount + " 个，发布仓补充 " + $extraCn + " 个，合计 " + $cnIndex.Count)

# 发布仓英文（仅作为官方英文缺失时的兜底）
$relEnIndex = @{}
if (-not [string]::IsNullOrEmpty($ReleaseEnDir) -and [System.IO.Directory]::Exists($ReleaseEnDir)) {
    foreach ($f in [System.IO.Directory]::GetFiles($ReleaseEnDir, '*.json', [System.IO.SearchOption]::AllDirectories)) {
        $rel = $f.Substring($ReleaseEnDir.Length).TrimStart('\')
        if (-not $relEnIndex.ContainsKey($rel)) { $relEnIndex[$rel] = $f }
    }
    Log ("发布仓英文兜底文件数：" + $relEnIndex.Count)
}

function Resolve-EnPath([string]$rel) {
    if ($enIndex.ContainsKey($rel)) { return $enIndex[$rel] }
    if ($relEnIndex.ContainsKey($rel)) { return $relEnIndex[$rel] }
    return $null
}

# ---------- 主循环：以官方英文为主干（含中文侧独有的文件） ----------
$allRel = New-Object System.Collections.ArrayList
$seen = @{}
foreach ($rel in $enIndex.Keys) { if (-not $seen.ContainsKey($rel)) { $seen[$rel] = $true; [void]$allRel.Add($rel) } }
foreach ($rel in $cnIndex.Keys) { if (-not $seen.ContainsKey($rel)) { $seen[$rel] = $true; [void]$allRel.Add($rel) } }
$allRel = @($allRel | Sort-Object)
Log ("待处理文件总数：" + $allRel.Count)
if ($Limit -gt 0) { $allRel = @($allRel | Select-Object -First $Limit); Log ("（-Limit " + $Limit + " 生效，只处理前 " + $allRel.Count + " 个）") }

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$i = 0
foreach ($rel in $allRel) {
    $i++
    if ($i % 200 -eq 0) { Log ("  ... " + $i + "/" + $allRel.Count + "  用时 " + [int]$sw.Elapsed.TotalSeconds + "s") }
    $script:Stat.filesConsidered++

    # 该文件允许双语的字段
    $fields = $null
    $matched = $false
    foreach ($s in $scopes) {
        if (Test-Glob $s.pattern $rel) { $fields = $s.fields; $matched = $true; break }
    }
    if (-not $matched) { $fields = $null }
    else { $fields = (Get-EffectiveFields $fields) }
    # 未命中 -> 中文单语（$matched 决定后续分支）

    $enPath = Resolve-EnPath $rel
    $cnPath = if ($cnIndex.Contains($rel)) { $cnIndex[$rel] } else { $null }
    $outPath = Join-Path $OutDir $rel

    if ($null -eq $cnPath) {
        # 没有中文：官方英文缺失才走到这里 -> 跳过
        $script:Stat.filesSkippedNoCn++
        continue
    }

    if (-not $matched) {
        # 中文单语：直接复制中文文件
        $script:Stat.filesCnOnly++
        if (-not $DryRun) {
            $dir = [System.IO.Path]::GetDirectoryName($outPath)
            if (-not [System.IO.Directory]::Exists($dir)) { [void][System.IO.Directory]::CreateDirectory($dir) }
            [System.IO.File]::Copy($cnPath, $outPath, $true)
        }
        $script:Stat.filesWritten++
        continue
    }

    # 双语文件
    $script:Stat.filesBilingual++
    if ($null -eq $enPath) {
        # 范围内但没有英文原文 -> 保持中文单语
        $script:Stat.filesWithoutEnglish++
        if (-not $DryRun) {
            $dir = [System.IO.Path]::GetDirectoryName($outPath)
            if (-not [System.IO.Directory]::Exists($dir)) { [void][System.IO.Directory]::CreateDirectory($dir) }
            [System.IO.File]::Copy($cnPath, $outPath, $true)
        }
        $script:Stat.filesWritten++
        continue
    }
    $script:Stat.filesWithEnglish++

    $enObj = Read-JsonFile $enPath
    $cnObj = Read-JsonFile $cnPath

    $merged = Merge-Value $enObj $cnObj '' $fields
    $txt = ConvertTo-JsonText $merged
    if (-not $DryRun) { Write-Utf8File $outPath $txt }
    $script:Stat.filesWritten++
}
$sw.Stop()

# ---------- 报告 ----------
LogStep ''
LogStep '================ 统计 ================'
foreach ($k in $script:Stat.Keys) { Log ("{0,-22} {1}" -f $k, $script:Stat[$k]) }
Log ("{0,-22} {1}" -f 'elapsedSeconds', [int]$sw.Elapsed.TotalSeconds)
Log ("{0,-22} {1}" -f 'outDir', $OutDir)
if ($DryRun) { Log '（DryRun：未写任何文件）' }
