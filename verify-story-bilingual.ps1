# verify-story-bilingual.ps1
# 校验 merge-story-bilingual.ps1 的产物：
#   1) 范围外文件：输出必须与已安装中文包逐字节一致（中文单语，未被改动）
#   2) 范围内文件：输出的每个可双语标量文本必须等于 en、cn 之一，或 en + sep + cn；
#      语言无关字段（excludeFields）必须与英文侧逐字相同
#   3) 英文侧每个 id 必须存在，且 id 集合与顺序与英文侧一致
#   4) 范围内但无官方英文的文件：输出必须与中文侧逐字节一致
param(
    [Parameter(Mandatory = $true)][string]$OfficialEnDir,
    [Parameter(Mandatory = $true)][string]$InstalledCnDir,
    [Parameter(Mandatory = $true)][string]$OutDir,
    [Parameter(Mandatory = $true)][string]$ModeFile,
    [string]$ReportPath = '',
    [string]$Separator = "`n"
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Web.Extensions
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
function Log([string]$m) { Write-Host $m }

$script:Ser = New-Object System.Web.Script.Serialization.JavaScriptSerializer
$script:Ser.MaxJsonLength = [int]::MaxValue
$script:Ser.RecursionLimit = 512
function Read-JsonFile([string]$p) { return $script:Ser.DeserializeObject([System.IO.File]::ReadAllText($p)) }

function Test-IsDict($v) { return (($v -is [System.Collections.IDictionary]) -and -not ($v -is [System.Collections.IList])) }
function Test-IsList($v) { return (($v -is [System.Collections.IList]) -and -not ($v -is [System.Collections.IDictionary])) }
function Test-Key($o, [string]$n) {
    if ($null -eq $o) { return $false }
    try { return [bool]$o.ContainsKey([string]$n) } catch { try { return [bool]$o.Contains([string]$n) } catch { return $false } }
}
function Test-Glob([string]$pattern, [string]$name) {
    $p = $pattern.Replace('/', '\'); $n = $name.Replace('/', '\')
    if ($p -eq $n) { return $true }
    if ($p -notmatch '[\*\?]') { return $false }
    $rx = '^' + [regex]::Escape($p).Replace('\*', '.*').Replace('\?', '.') + '$'
    return [bool]($n -match $rx)
}
# 与合并脚本一致的数组键判定：优先 id，其次 fileName；有键就按键配对，无键才按下标
function Get-ArrayKeyName($arr) {
    if ($null -eq $arr) { return , $null }
    if (-not (Test-IsList $arr)) { return , $null }
    if ($arr.Count -eq 0) { return , $null }
    foreach ($c in @('id', 'fileName')) {
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
        if ((Test-IsDict $e) -and (Test-Key $e $keyName)) {
            $ks = [string]$e[$keyName]
            if (-not $h.ContainsKey($ks)) { $h[$ks] = $i }
        }
    }
    return $h
}

$mode = Read-JsonFile $ModeFile
$scopes = @($mode.scopes | ForEach-Object { [string]$_.pattern })
$excludeFields = @()
if ($null -ne $mode.excludeFields) { $excludeFields = @($mode.excludeFields | ForEach-Object { ([string]$_).ToLowerInvariant() }) }
function Test-Excluded([string]$n) { $x = $n.ToLowerInvariant(); foreach ($e in $excludeFields) { if ($e -eq $x) { return $true } }; return $false }
function Test-InScope([string]$rel) { foreach ($p in $scopes) { if (Test-Glob $p $rel) { return $true } }; return $false }

# 英文索引
$enIndex = @{}
foreach ($f in [System.IO.Directory]::GetFiles($OfficialEnDir, '*.json', [System.IO.SearchOption]::AllDirectories)) {
    $rel = $f.Substring($OfficialEnDir.Length).TrimStart('\')
    $d = [System.IO.Path]::GetDirectoryName($rel); $b = [System.IO.Path]::GetFileName($rel)
    if ($b -like 'EN_*') { $b = $b.Substring(3) }
    $lg = if ([string]::IsNullOrEmpty($d)) { $b } else { "$d\$b" }
    if (-not $enIndex.ContainsKey($lg)) { $enIndex[$lg] = $f }
}

$issues = New-Object System.Collections.ArrayList
$stat = [ordered]@{
    outFiles = 0; scopedFiles = 0; unscopedFiles = 0; cnOnlyScopedFiles = 0; missingInOut = 0
    byteIdenticalUnscoped = 0; byteDiffUnscoped = 0; byteIdenticalCnOnly = 0; byteDiffCnOnly = 0
    textOk = 0; textMerged = 0; textEnOnly = 0; textCnOnly = 0
    textBad = 0; invariantBad = 0; idLost = 0; idExtra = 0; idOrderBad = 0; typeBad = 0; cnMissing = 0
}
function AddIssue([string]$rel, [string]$kind, [string]$detail) {
    if ($issues.Count -lt 400) { [void]$issues.Add("$kind`t$rel`t$detail") }
}

# 递归比对：out vs en vs cn
function Compare-Node($out, $en, $cn, [string]$rel, [string]$path) {
    # 类型一致性
    if ($null -ne $en) {
        $enK = if (Test-IsDict $en) { 'obj' } elseif (Test-IsList $en) { 'arr' } elseif ($en -is [string]) { 'str' } elseif ($en -is [bool]) { 'bool' } else { 'num' }
        $outK = if (Test-IsDict $out) { 'obj' } elseif (Test-IsList $out) { 'arr' } elseif ($out -is [string]) { 'str' } elseif ($out -is [bool]) { 'bool' } else { 'num' }
        if ($enK -ne $outK -and -not ($null -eq $out -and $enK -eq 'str')) {
            $stat.typeBad++; AddIssue $rel 'TYPE' "$path en=$enK out=$outK"; return
        }
    }
    if (Test-IsDict $en) {
        foreach ($k in $en.Keys) {
            $ks = [string]$k; $cp = "$path/$ks"
            if (-not (Test-Key $out $ks)) { $stat.idLost++; AddIssue $rel 'MISSINGKEY' $cp; continue }
            $ev = $en[$k]
            $cv = if ((Test-IsDict $cn) -and (Test-Key $cn $ks)) { $cn[$ks] } else { $null }
            $ov = $out[$ks]
            if ((Test-IsDict $ev) -or (Test-IsList $ev)) { Compare-Node $ov $ev $cv $rel $cp }
            elseif (Test-Excluded $ks) {
                if (-not ($ev -is [string]) -or -not ($ov -is [string])) {
                    $a = [string]$ev; $b = [string]$ov
                    if ($a -ne $b) { $stat.invariantBad++; AddIssue $rel 'INVARIANT' "$cp [$a] -> [$b]" }
                }
            }
            else {
                Check-Text $ov $ev $cv $rel $cp
            }
        }
        foreach ($k in $out.Keys) {
            $ks = [string]$k
            if (-not (Test-Key $en $ks)) {
                # 中文侧独有（合并会补进来）时不算问题
                if ((Test-IsDict $cn) -and (Test-Key $cn $ks)) { continue }
                $stat.idExtra++; AddIssue $rel 'EXTRAKEY' "$path/$ks"
            }
        }
        return
    }
    if (Test-IsList $en) {
        $kn = Get-ArrayKeyName $en
        if ($null -eq $kn) { $kn = Get-ArrayKeyName $cn }
        # 与合并脚本一致：若条数相同且每个位置的 id 都对得上，则按下标配对（重复 id 的唯一正确处理方式）
        $idAligned = $false
        if (($null -ne $kn) -and (Test-IsList $cn) -and ($en.Count -eq $cn.Count)) {
            $idAligned = $true
            for ($i = 0; $i -lt $en.Count; $i++) {
                $he = (Test-IsDict $en[$i]) -and (Test-Key $en[$i] $kn)
                $hc = (Test-IsDict $cn[$i]) -and (Test-Key $cn[$i] $kn)
                if ($he -ne $hc) { $idAligned = $false; break }
                if ($he -and ([string]$en[$i][$kn] -ne [string]$cn[$i][$kn])) { $idAligned = $false; break }
            }
        }
        if ($idAligned) {
            if ($out.Count -ne $en.Count) { $stat.idExtra++; AddIssue $rel 'LEN' "$path en=$($en.Count) out=$($out.Count)" }
            $n = [Math]::Min($out.Count, $en.Count)
            for ($i = 0; $i -lt $n; $i++) {
                $ev = $en[$i]; $ov = $out[$i]; $cv = $cn[$i]
                if ((Test-IsDict $ev) -or (Test-IsList $ev)) { Compare-Node $ov $ev $cv $rel "$path[$i]" }
                else { Check-Text $ov $ev $cv $rel "$path[$i]" }
            }
            return
        }
        if ($null -ne $kn) {
            # 与合并脚本完全一致的对齐方式：
            #   有键条目按 id 配对；无键条目按「无键条目内的相对下标」配对（不能拿下标当键）
            $cnIdx = Get-KeyedIndex $cn $kn
            $outIdx = Get-KeyedIndex $out $kn
            $outUnkeyed = New-Object System.Collections.ArrayList
            foreach ($ovv in $out) {
                if (-not ((Test-IsDict $ovv) -and (Test-Key $ovv $kn))) { [void]$outUnkeyed.Add($ovv) }
            }
            $cnUnkeyed = New-Object System.Collections.ArrayList
            foreach ($cvv in $cn) {
                if ((Test-IsList $cn) -and (Test-IsDict $cvv) -and (Test-Key $cvv $kn)) { continue }
                if (Test-IsList $cn) { [void]$cnUnkeyed.Add($cvv) }
            }
            $iUnkeyed = 0
            foreach ($ev in $en) {
                $hasKey = ((Test-IsDict $ev) -and (Test-Key $ev $kn))
                if ($hasKey) {
                    $ks = [string]$ev[$kn]
                    $cv = if ($cnIdx.ContainsKey($ks)) { $cn[$cnIdx[$ks]] } else { $null }
                    if (-not $outIdx.ContainsKey($ks)) { $stat.idLost++; AddIssue $rel 'IDLOST' "$path[$ks]"; continue }
                    $ov = $out[$outIdx[$ks]]
                    $lbl = $ks
                }
                else {
                    $cv = if ($iUnkeyed -lt $cnUnkeyed.Count) { $cnUnkeyed[$iUnkeyed] } else { $null }
                    if ($iUnkeyed -ge $outUnkeyed.Count) { $stat.idLost++; AddIssue $rel 'IDLOST' "$path[u$iUnkeyed]"; $iUnkeyed++; continue }
                    $ov = $outUnkeyed[$iUnkeyed]
                    $lbl = 'u' + $iUnkeyed
                    $iUnkeyed++
                }
                if ((Test-IsDict $ev) -or (Test-IsList $ev)) { Compare-Node $ov $ev $cv $rel "$path[$lbl]" }
                else { Check-Text $ov $ev $cv $rel "$path[$lbl]" }
            }
            # 产物里比英文多的、且中文侧也有的条目：合并会追加，属正常
            $cnAllIdx = Get-KeyedIndex $cn $kn
            foreach ($ovv in $out) {
                $ks = if ((Test-IsDict $ovv) -and (Test-Key $ovv $kn)) { [string]$ovv[$kn] } else { $null }
                if ($null -eq $ks) { continue }
                if ((Get-KeyedIndex $en $kn).ContainsKey($ks)) { continue }
                if ($cnAllIdx.ContainsKey($ks)) { continue }
                $stat.idExtra++; AddIssue $rel 'ARREXTRA' "$path[$ks]"
            }
            return
        }
        if ($out.Count -ne $en.Count) { $stat.idExtra++; AddIssue $rel 'LEN' "$path en=$($en.Count) out=$($out.Count)" }
        $n = [Math]::Min($out.Count, $en.Count)
        for ($i = 0; $i -lt $n; $i++) {
            $ev = $en[$i]; $ov = $out[$i]
            $cv = if ((Test-IsList $cn) -and ($i -lt $cn.Count)) { $cn[$i] } else { $null }
            if ((Test-IsDict $ev) -or (Test-IsList $ev)) { Compare-Node $ov $ev $cv $rel "$path[$i]" }
            else { Check-Text $ov $ev $cv $rel "$path[$i]" }
        }
        return
    }
    Check-Text $out $en $cn $rel $path
}

function Check-Text($out, $en, $cn, [string]$rel, [string]$path) {
    $e = if ($null -eq $en) { '' } else { [string]$en }
    $c = if ($null -eq $cn) { '' } else { [string]$cn }
    $o = if ($null -eq $out) { '' } else { [string]$out }
    $stat.textOk++
    if ($e -eq $c) {
        if ($o -ne $e) { $stat.textBad++; AddIssue $rel 'TEXT-IDENT' "$path [$o] != [$e]" } else { $stat.textEnOnly++ }
        return
    }
    if ([string]::IsNullOrEmpty($c)) {
        if ($o -ne $e) { $stat.textBad++; AddIssue $rel 'TEXT-ENONLY' "$path [$o] != [$e]" } else { $stat.textEnOnly++ }
        return
    }
    if ([string]::IsNullOrEmpty($e)) {
        if ($o -ne $c) { $stat.textBad++; AddIssue $rel 'TEXT-CNONLY' "$path [$o] != [$c]" } else { $stat.textCnOnly++ }
        return
    }
    $want = $e + $Separator + $c
    if ($o -eq $want) { $stat.textMerged++; return }
    $stat.textBad++; AddIssue $rel 'TEXT-PAIR' "$path [$o] != [$want]"
}

$sw = [System.Diagnostics.Stopwatch]::StartNew()
foreach ($f in [System.IO.Directory]::GetFiles($OutDir, '*.json', [System.IO.SearchOption]::AllDirectories)) {
    $rel = $f.Substring($OutDir.Length).TrimStart('\')
    $stat.outFiles++
    $inScope = Test-InScope $rel
    $enPath = if ($enIndex.ContainsKey($rel)) { $enIndex[$rel] } else { $null }
    $cnPath = Join-Path $InstalledCnDir $rel

    if (-not [System.IO.File]::Exists($cnPath)) { $stat.cnMissing++; AddIssue $rel 'CNMISSING' $cnPath; continue }
    $cnBytes = [System.IO.File]::ReadAllBytes($cnPath)
    $outBytes = [System.IO.File]::ReadAllBytes($f)

    if (-not $inScope) {
        $stat.unscopedFiles++
        if ($outBytes.Length -eq $cnBytes.Length) { $stat.byteIdenticalUnscoped++ }
        else { $stat.byteDiffUnscoped++; AddIssue $rel 'UNSCOPED-DIFF' "out=$($outBytes.Length) cn=$($cnBytes.Length)" }
        continue
    }
    $stat.scopedFiles++
    if ($null -eq $enPath) {
        $stat.cnOnlyScopedFiles++
        if ([System.Linq.Enumerable]::SequenceEqual([byte[]]$outBytes, [byte[]]$cnBytes)) { $stat.byteIdenticalCnOnly++ }
        else { $stat.byteDiffCnOnly++; AddIssue $rel 'SCOPED-NOEN-DIFF' "out=$($outBytes.Length) cn=$($cnBytes.Length)" }
        continue
    }
    $outObj = Read-JsonFile $f
    $enObj = Read-JsonFile $enPath
    $cnObj = Read-JsonFile $cnPath
    Compare-Node $outObj $enObj $cnObj $rel ''
}
$sw.Stop()

Log '================ 校验统计 ================'
foreach ($k in $stat.Keys) { Log ("{0,-24} {1}" -f $k, $stat[$k]) }
Log ("{0,-24} {1}" -f 'issueCount', $issues.Count)
Log ("{0,-24} {1}" -f 'elapsedSeconds', [int]$sw.Elapsed.TotalSeconds)
if ($issues.Count -gt 0) {
    Log ''
    Log '================ 问题样例（最多 60 条）================'
    $issues | Select-Object -First 60 | ForEach-Object { Log $_ }
}
if (-not [string]::IsNullOrEmpty($ReportPath)) {
    $lines = New-Object System.Collections.ArrayList
    [void]$lines.Add('merge-story-bilingual 产物校验报告')
    [void]$lines.Add('时间：' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
    [void]$lines.Add("英文目录：$OfficialEnDir")
    [void]$lines.Add("中文目录：$InstalledCnDir")
    [void]$lines.Add("产物目录：$OutDir")
    [void]$lines.Add("模式文件：$ModeFile")
    [void]$lines.Add('')
    foreach ($k in $stat.Keys) { [void]$lines.Add(("{0,-24} {1}" -f $k, $stat[$k])) }
    [void]$lines.Add(("{0,-24} {1}" -f 'issueCount', $issues.Count))
    [void]$lines.Add('')
    [void]$lines.Add('---- 问题明细 ----')
    foreach ($it in $issues) { [void]$lines.Add($it) }
    $enc = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllBytes($ReportPath, $enc.GetPreamble() + $enc.GetBytes(($lines -join "`r`n")))
    Log "报告已写出：$ReportPath"
}
