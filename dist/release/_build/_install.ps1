# PBZ 伤害飘字 MOD 一键安装脚本
# 自动定位 Steam 库 -> 游戏目录，检测已有前置并备份后安装。

$ErrorActionPreference = 'Stop'
# 自动化测试用：设环境变量 PBZDN_TEST=1 时跳过所有交互提示
$autoYes = ($env:PBZDN_TEST -eq '1')
try { $Host.UI.RawUI.WindowTitle = 'PBZ 伤害飘字 MOD  v0.5.0  安装程序' } catch {}

function Line   { Write-Host ('-' * 60) -ForegroundColor DarkGray }
function Title($t) { Write-Host ''; Line; Write-Host "  $t" -ForegroundColor Cyan; Line; Write-Host '' }
function Ok($t)   { Write-Host "  [OK]   $t" -ForegroundColor Green }
function Warn($t) { Write-Host "  [!]    $t" -ForegroundColor Yellow }
function Bad($t)  { Write-Host "  [X]    $t" -ForegroundColor Red }
function Info($t) { Write-Host "         $t" -ForegroundColor Gray }

# ---------------- 定位游戏 ----------------
function Find-PBZ {
    $roots = @()
    foreach ($k in @(
        'HKCU:\Software\Valve\Steam',
        'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam',
        'HKLM:\SOFTWARE\Valve\Steam'
    )) {
        try {
            $p = Get-ItemProperty $k -ErrorAction Stop
            if ($p.SteamPath)  { $roots += $p.SteamPath }
            if ($p.InstallPath) { $roots += $p.InstallPath }
        } catch { }
    }

    $libs = @()
    foreach ($r in $roots) {
        if (-not $r) { continue }
        foreach ($rel in @('steamapps\libraryfolders.vdf', 'config\libraryfolders.vdf')) {
            $vdf = Join-Path $r $rel
            if (-not (Test-Path $vdf)) { continue }
            try {
                foreach ($line in (Get-Content -LiteralPath $vdf -ErrorAction Stop)) {
                    if ($line -match '"path"\s+"([^"]+)"') {
                        $libs += ($matches[1] -replace '\\\\', '\')
                    }
                }
            } catch { }
        }
    }

    $cands = @()
    foreach ($l in ($roots + $libs)) {
        if ($l) { $cands += (Join-Path $l 'steamapps\common\PBZ') }
    }
    $cands += @(
        'C:\Program Files (x86)\Steam\steamapps\common\PBZ',
        'C:\Program Files\Steam\steamapps\common\PBZ',
        'D:\Steam\steamapps\common\PBZ',
        'D:\SteamLibrary\steamapps\common\PBZ',
        'E:\Steam\steamapps\common\PBZ',
        'E:\SteamLibrary\steamapps\common\PBZ',
        'F:\SteamLibrary\steamapps\common\PBZ'
    )

    $seen = @{}
    foreach ($c in $cands) {
        if (-not $c) { continue }
        if ($seen.ContainsKey($c)) { continue }
        $seen[$c] = 1
        try {
            if (Test-Path (Join-Path $c 'platform\steam\PBZ.exe')) { return $c }
        } catch { }
    }
    return $null
}

function Test-GameDir($p) {
    if (-not $p) { return $false }
    return (Test-Path (Join-Path $p 'platform\steam\PBZ.exe'))
}

# ---------------- 开始 ----------------
Clear-Host
Write-Host ''
Write-Host '  ============================================================' -ForegroundColor DarkCyan
Write-Host '        影之刃零   伤害飘字优化 MOD   v0.5.0' -ForegroundColor White
Write-Host '                       安  装  程  序' -ForegroundColor White
Write-Host '  ============================================================' -ForegroundColor DarkCyan
Write-Host ''
Write-Host '  这个程序会自己找到游戏目录，把文件放到正确位置。' -ForegroundColor Gray
Write-Host '  不会动游戏本体，不碰存档，随时可以卸载。' -ForegroundColor Gray

$src = $PSScriptRoot
if (-not $src) { $src = Split-Path -Parent $MyInvocation.MyCommand.Path }

# 判断这是哪种包
$srcSteam   = Join-Path $src 'platform\steam'
$srcModDir  = Join-Path $src 'PBZ_DamageNumbers_Custom'
$isFullPack = Test-Path $srcSteam
$isModPack  = Test-Path $srcModDir

if (-not $isFullPack -and -not $isModPack) {
    Title '文件不完整'
    Bad '没有在压缩包解压目录里找到 MOD 文件。'
    Info '常见原因：你直接在压缩包里双击了这个程序，没有先解压。'
    Info ''
    Info '请这样做：'
    Info '  1. 右键压缩包 -> 全部解压缩 / 解压到当前文件夹'
    Info '  2. 进入解压出来的文件夹'
    Info '  3. 再双击"一键安装.bat"'
    Write-Host ''
    if (-not $autoYes) { Read-Host '按回车键关闭' }
    exit 1
}

$modeText = if ($isFullPack) { '完整包（含 UE4SS 前置）' } else { '单独 MOD（需要已有 UE4SS）' }
Info ''
Info "包类型：$modeText"

# ---------------- 找游戏 ----------------
Title '第 1 步 / 共 3 步    正在查找游戏目录'

$game = Find-PBZ

if ($game) {
    Ok "找到了：$game"
} else {
    Warn '没能自动找到游戏。'
    Write-Host ''
    Write-Host '  请手动指定游戏文件夹（里面有 PBZ.exe 的那个）：' -ForegroundColor Yellow
    Write-Host '    在 Steam 库里右键《影之刃零》-> 管理 -> 浏览本地文件' -ForegroundColor Gray
    Write-Host '    然后把弹出的文件夹直接拖到这个窗口里，按回车。' -ForegroundColor Gray
    Write-Host ''
    $manual = Read-Host '  游戏目录'
    if ($manual) {
        $manual = $manual.Trim()
        $manual = $manual.Trim('"')
        $manual = $manual.Trim("'")
        $manual = $manual.TrimEnd('\')
    }
    if (Test-GameDir $manual) {
        $game = $manual
        Ok "使用：$game"
    } else {
        Bad '这个路径下没有找到 platform\steam\PBZ.exe'
        Info '请确认选的是游戏根目录（PBZ.exe 所在的那一层）。'
        Write-Host ''
        if (-not $autoYes) { Read-Host '按回车键关闭' }
        exit 1
    }
}

$targetSteam = Join-Path $game 'platform\steam'
$targetMods  = Join-Path $targetSteam 'ue4ss\Mods'
$targetMod   = Join-Path $targetMods 'PBZ_DamageNumbers_Custom'

# ---------------- 检查现有前置 ----------------
Title '第 2 步 / 共 3 步    检查现有环境'

$hadUE4SS = (Test-Path (Join-Path $targetSteam 'ue4ss\UE4SS.dll'))
$hadDll   = (Test-Path (Join-Path $targetSteam 'dwmapi.dll'))
$hadMod   = (Test-Path $targetMod)

if ($hadUE4SS) {
    Ok '检测到你已经装过 UE4SS 前置'
} else {
    Warn '没有检测到 UE4SS 前置'
}

if ($hadMod) {
    Warn '检测到已安装过这个 MOD，将更新为新版本'
}

# 单独 MOD 包 + 没有 UE4SS = 装不了
if ($isModPack -and -not $hadUE4SS) {
    Write-Host ''
    Bad '这个包里只有 MOD，没有前置，而你还没装过 UE4SS。'
    Info ''
    Info '解决办法：改成用"含 UE4SS 前置"那个完整包，它一步装完。'
    Write-Host ''
    if (-not $autoYes) { Read-Host '按回车键关闭' }
    exit 1
}

# 完整包 + 已经有 UE4SS = 提醒（仍可选覆盖）
if ($isFullPack -and $hadUE4SS) {
    Write-Host ''
    Warn '你已经有 UE4SS 了，再装一份可能会起冲突。'
    Info '正常情况建议用"单独 MOD"那个包。'
    Info '如果现在这个 UE4SS 是坏的、想用包里的覆盖掉，可以继续。'
    Write-Host ''
    $ans = if ($autoYes) { 'y' } else { Read-Host '  继续覆盖安装吗？输入 y 继续，直接回车退出' }
    if ($ans -notmatch '^[yY]') {
        Info '已取消，什么都没改。'
        Write-Host ''
        if (-not $autoYes) { Read-Host '按回车键关闭' }
        exit 0
    }
}

# ---------------- 备份 ----------------
$backupDir = $null
if ($hadDll -or $hadUE4SS) {
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $backupDir = Join-Path $targetSteam ("_backup_" + $stamp)
    try {
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
        if ($hadDll) {
            Copy-Item (Join-Path $targetSteam 'dwmapi.dll') $backupDir -Force
        }
        foreach ($f in @('UE4SS.dll', 'UE4SS-settings.ini', 'MemberVariableLayout.ini')) {
            $p = Join-Path $targetSteam ("ue4ss\" + $f)
            if (Test-Path $p) { Copy-Item $p $backupDir -Force }
        }
        Ok "原有文件已备份到：_backup_$stamp"
    } catch {
        Warn '备份失败（可能是文件被占用），继续安装。'
        Info $_.Exception.Message
    }
}

# ---------------- 复制文件 ----------------
Title '第 3 步 / 共 3 步    正在安装'

try {
    if ($isFullPack) {
        & robocopy $srcSteam $targetSteam /E /IS /IT /NFL /NDL /NJH /NJS /R:2 /W:1 | Out-Null
        $code = $LASTEXITCODE
        if ($code -ge 8) { throw "robocopy 返回 $code" }
        Ok '已安装 UE4SS 前置'
        Ok '已安装飘字 MOD'
    } else {
        & robocopy $srcModDir $targetMod /E /IS /IT /NFL /NDL /NJH /NJS /R:2 /W:1 | Out-Null
        $code = $LASTEXITCODE
        if ($code -ge 8) { throw "robocopy 返回 $code" }
        Ok '已安装飘字 MOD'
    }
} catch {
    Write-Host ''
    Bad '安装过程中出错：'
    Info $_.Exception.Message
    Info ''
    Info '如果是"文件被占用"，请先完全退出游戏（任务管理器里确认没有 PBZ.exe）再试。'
    Write-Host ''
    if (-not $autoYes) { Read-Host '按回车键关闭' }
    exit 1
}

# ---------------- 校验 ----------------
Write-Host ''
$checks = @()
if ($isFullPack) {
    $checks += @{ Name = 'dwmapi.dll';           Path = (Join-Path $targetSteam 'dwmapi.dll') }
    $checks += @{ Name = 'UE4SS.dll';            Path = (Join-Path $targetSteam 'ue4ss\UE4SS.dll') }
    $checks += @{ Name = 'MemberVariableLayout'; Path = (Join-Path $targetSteam 'ue4ss\MemberVariableLayout.ini') }
}
$checks += @{ Name = 'MOD 主脚本';   Path = (Join-Path $targetMod 'Scripts\main.lua') }
$checks += @{ Name = 'MOD 启用标记'; Path = (Join-Path $targetMod 'enabled.txt') }

$allOk = $true
foreach ($c in $checks) {
    if (Test-Path $c.Path) {
        Ok $c.Name
    } else {
        Bad ($c.Name + '  缺失')
        $allOk = $false
    }
}

# ---------------- 结果 ----------------
Write-Host ''
if ($allOk) {
    Write-Host '  ============================================================' -ForegroundColor Green
    Write-Host '                        安 装 成 功' -ForegroundColor Green
    Write-Host '  ============================================================' -ForegroundColor Green
    Write-Host ''
    Write-Host '  下一步：' -ForegroundColor White
    Write-Host '    1. 启动游戏，进存档' -ForegroundColor Gray
    Write-Host '    2. 随便打几只怪' -ForegroundColor Gray
    Write-Host ''
    Write-Host '  你会看到的变化：' -ForegroundColor White
    Write-Host '    - 伤害数字停留更久，不再一闪就没' -ForegroundColor Gray
    Write-Host '    - 连续跳的数字一行一个，不再叠成一坨' -ForegroundColor Gray
    Write-Host '    - 喝药回血的数字变成绿色' -ForegroundColor Gray
    Write-Host ''
    if ($backupDir) {
        Write-Host '  原来的文件备份在：' -ForegroundColor DarkGray
        Write-Host "    $backupDir" -ForegroundColor DarkGray
        Write-Host ''
    }
    Write-Host '  想卸载：关掉游戏，双击同一个文件夹里的"一键卸载.bat"' -ForegroundColor Gray
    Write-Host '  想改效果：Scripts\config.lua 里改数字，重启游戏生效' -ForegroundColor Gray
} else {
    Write-Host '  ============================================================' -ForegroundColor Yellow
    Write-Host '                    安装没完全成功' -ForegroundColor Yellow
    Write-Host '  ============================================================' -ForegroundColor Yellow
    Write-Host ''
    Write-Host '  上面标 [X] 的文件没到位。可能是游戏正在运行，或者有杀毒软件拦了。' -ForegroundColor Gray
    Write-Host '  先完全退出游戏，再双击一次"一键安装.bat"。' -ForegroundColor Gray
}

Write-Host ''
if (-not $autoYes) { Read-Host '按回车键关闭' }

exit 0
