# install-bilingual.ps1 —— 把本仓库的双语语言包安装进《边狱公司》
#
# 用法（普通 PowerShell 即可，不需要管理员）：
#   & .\install-bilingual.ps1
#   & .\install-bilingual.ps1 -LangRoot "D:\SteamLibrary\steamapps\common\Limbus Company\LimbusCompany_Data\Lang"
#   & .\install-bilingual.ps1 -Activate:$false     # 只复制语言包，不改 config.json
#
# 做的事：
#   1. 把本仓库（也就是语言包本体）复制到 <LangRoot>\LLC_zh-CN_bilingual
#      只复制游戏需要的部分（全部 *.json 与 Font / Info），.git 与工具脚本不会复制。
#      已存在同名目录时先改名备份。
#   2. 备份 config.json 后，把其中的 lang 改成 LLC_zh-CN_bilingual
#
# 原有 LLC_zh-CN 目录不会被改动，随时把 config.json 里的 lang 改回去即可切回纯中文。
[CmdletBinding()]
param(
  [string]$LangRoot = 'D:\SteamLibrary\steamapps\common\Limbus Company\LimbusCompany_Data\Lang',
  [string]$PackName = 'LLC_zh-CN_bilingual',
  [switch]$Activate = $true
)
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not [System.IO.Directory]::Exists($LangRoot)) { throw "找不到游戏 Lang 目录: $LangRoot" }

# 本仓库即语言包：源目录就是脚本所在目录。
$src = $here
if (-not [System.IO.File]::Exists((Join-Path $src 'Info\version.json'))) {
  throw "看起来 $src 不是语言包根目录（缺少 Info\version.json）。请把本脚本放在语言包根目录里运行。"
}

$dst = Join-Path $LangRoot $PackName
if ([System.IO.Directory]::Exists($dst)) {
  $bak = $dst + '.bak-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
  Write-Host "目标已存在，先备份为: $bak"
  Move-Item $dst $bak
}
[void][System.IO.Directory]::CreateDirectory($dst)

Write-Host "复制语言文件 $src -> $dst"
$n = 0
foreach ($f in [System.IO.Directory]::GetFiles($src, '*.json', [System.IO.SearchOption]::AllDirectories)) {
  $rel = $f.Substring($src.Length).TrimStart('\')
  $to = Join-Path $dst $rel
  $dir = [System.IO.Path]::GetDirectoryName($to)
  if (-not [System.IO.Directory]::Exists($dir)) { [void][System.IO.Directory]::CreateDirectory($dir) }
  [System.IO.File]::Copy($f, $to, $true)
  $n++
}
foreach ($sub in @('Font', 'Info')) {
  $s = Join-Path $src $sub
  if (-not [System.IO.Directory]::Exists($s)) { continue }
  foreach ($f in [System.IO.Directory]::GetFiles($s, '*', [System.IO.SearchOption]::AllDirectories)) {
    $rel = $f.Substring($src.Length).TrimStart('\')
    $to = Join-Path $dst $rel
    $dir = [System.IO.Path]::GetDirectoryName($to)
    if (-not [System.IO.Directory]::Exists($dir)) { [void][System.IO.Directory]::CreateDirectory($dir) }
    [System.IO.File]::Copy($f, $to, $true)
    $n++
  }
}
$emptyDir = Join-Path $src 'Font\Title'
if ([System.IO.Directory]::Exists($emptyDir)) {
  $to = Join-Path $dst 'Font\Title'
  if (-not [System.IO.Directory]::Exists($to)) { [void][System.IO.Directory]::CreateDirectory($to) }
}
Write-Host "完成：复制了 $n 个文件"

if (-not $Activate) { Write-Host '已跳过 config.json 修改'; return }

$cfg = Join-Path $LangRoot 'config.json'
if (-not [System.IO.File]::Exists($cfg)) {
  Write-Host "未找到 config.json，写入一份新的"
  $obj = '{"lang":"' + $PackName + '","titleFont":"","contextFont":"","samplingPointSize":78,"padding":5}'
  [System.IO.File]::WriteAllText($cfg, $obj, (New-Object System.Text.UTF8Encoding($false)))
} else {
  $bak = $cfg + '.bak-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
  Copy-Item $cfg $bak -Force
  $txt = [System.IO.File]::ReadAllText($cfg)
  if ($txt -match '"lang"\s*:\s*"[^"]*"') {
    $new = [regex]::Replace($txt, '"lang"\s*:\s*"[^"]*"', '"lang": "' + $PackName + '"')
  } else {
    $new = $txt -replace '\{', ('{"lang": "' + $PackName + '",')
  }
  [System.IO.File]::WriteAllText($cfg, $new, (New-Object System.Text.UTF8Encoding($false)))
  Write-Host "已把 config.json 的 lang 改为 $PackName（备份: $bak）"
}
Write-Host ''
Write-Host '启动游戏即可。想恢复纯中文：把 config.json 的 lang 改回 LLC_zh-CN。'
