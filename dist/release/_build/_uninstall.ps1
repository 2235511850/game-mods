# PBZ 伤害飘字 MOD 一键卸载脚本
# 按包类型自适应：完整包可连同 UE4SS 一起清掉；单独 MOD 包只摘 MOD，不碰用户自己的前置。

$ErrorActionPreference = 'Stop'
# 自动化测试用：PBZDN_TEST=1 跳过交互；PBZDN_TEST_CHOICE / PBZDN_TEST_CONFIRM 供脚本化验证
$autoYes = ($env:PBZDN_TEST -eq '1')
try { $Host.UI.RawUI.WindowTitle = 'PBZ 伤害飘字 MOD  卸载程序' } catch {}

function Line { Write-Host ('-' * 60) -ForegroundColor DarkGray }
function Title($t) { Write-Host ''; Line; Write-Host "  $t" -ForegroundColor Cyan; Line; Write-Host '' }
function Ok($t)   { Write-Host "  [OK]   $t" -ForegroundColor Green }
function Warn($t) { Write-Host "  [!]    $t" -ForegroundColor Yellow }
function Bad($t)  { Write-Host "  [X]    $t" -ForegroundColor Red }
function Info($t) { Write-Host "         $t" -ForegroundColor Gray }
function Hold { if (-not $autoYes) { Read-Host '按回车键关闭' } }

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

try { Clear-Host } catch {}
Write-Host ''
Write-Host '  ============================================================' -ForegroundColor DarkCyan
Write-Host '        影之刃零   伤害飘字优化 MOD   v0.5.0' -ForegroundColor White
Write-Host '                       卸  载  程  序' -ForegroundColor White
Write-Host '  ============================================================' -ForegroundColor DarkCyan
Write-Host ''
Write-Host '  这个程序只删模组文件，游戏本体、存档都一个不碰。' -ForegroundColor Gray

# ---------------- 判断包类型 ----------------
$src = $PSScriptRoot
if (-not $src) { $src = Split-Path -Parent $MyInvocation.MyCommand.Path }
$isFullPack = Test-Path (Join-Path $src 'platform\steam')
$isModPack  = Test-Path (Join-Path $src 'PBZ_DamageNumbers_Custom')

if ($isFullPack) {
    Info ''
    Info '包类型：完整包（含 UE4SS 前置）'
} elseif ($isModPack) {
    Info ''
    Info '包类型：单独 MOD（当初没有装 UE4SS）'
} else {
    Info ''
    Info '包类型：无法识别（按"只删 MOD"处理，最安全）'
}

# ---------------- 找游戏 ----------------
Write-Host ''
$game = Find-PBZ
if (-not $game) {
    Warn '没能自动找到游戏目录。'
    Write-Host ''
    Write-Host '  请把游戏文件夹拖进下面（里面有 PBZ.exe 的那一层），按回车：' -ForegroundColor Yellow
    Write-Host '    Steam 库 -> 右键《影之刃零》-> 管理 -> 浏览本地文件' -ForegroundColor Gray
    Write-Host ''
    $manual = if ($autoYes) { '' } else { Read-Host '  游戏目录' }
    if ($manual) {
        $manual = $manual.Trim().Trim('"').Trim("'").TrimEnd('\')
    }
    if ($manual -and (Test-Path (Join-Path $manual 'platform\steam\PBZ.exe'))) {
        $game = $manual
    } else {
        Bad '没找到游戏目录，退出。'
        Info '如果你确定装过，就在 Steam 里右键游戏 -> 管理 -> 浏览本地文件，把那个文件夹路径抄下来。'
        Hold
        exit 1
    }
}

$targetSteam = Join-Path $game 'platform\steam'
$targetMod   = Join-Path $targetSteam 'ue4ss\Mods\PBZ_DamageNumbers_Custom'
$ue4ssDir    = Join-Path $targetSteam 'ue4ss'
$dllPath     = Join-Path $targetSteam 'dwmapi.dll'

Ok "游戏目录：$game"

$hasMod   = Test-Path $targetMod
$hasUE4SS = Test-Path (Join-Path $ue4ssDir 'UE4SS.dll')
$hasDll   = Test-Path $dllPath

if (-not $hasMod -and -not $hasUE4SS -and -not $hasDll) {
    Title '没有找到要卸载的内容'
    Info '这个游戏目录里既没有 UE4SS，也没有飘字 MOD。'
    Info '可能已经卸载过了，或者游戏装在别的库。'
    Write-Host ''
    Hold
    exit 0
}

# ---------------- 游戏是否在跑 ----------------
$running = @()
try { $running = @(Get-Process -Name 'PBZ' -ErrorAction SilentlyContinue) } catch { }
if ($running.Count -gt 0) {
    Write-Host ''
    Bad '游戏正在运行，请先完全退出游戏再卸载。'
    Info '（任务管理器里确认没有 PBZ.exe）'
    Write-Host ''
    Hold
    exit 1
}

# ---------------- 现状 ----------------
Write-Host ''
if ($hasMod)   { Warn '检测到：飘字 MOD 已安装' } else { Info '飘字 MOD：本来就没装' }
if ($hasUE4SS) { Info 'UE4SS 前置：存在' } else { Info 'UE4SS 前置：不存在' }
if ($hasDll)   { Info 'dwmapi.dll：存在' }

# ---------------- 菜单 ----------------
$canFull = $isFullPack -and ($hasDll -or $hasUE4SS)

Title '请选择卸载方式'

if ($hasMod) {
    Write-Host '  1   只卸载飘字 MOD' -ForegroundColor White
    Write-Host '      数字排版、绿色回血都会回到游戏原样' -ForegroundColor Gray
    Write-Host '      你原有的 UE4SS 和其它模组完全不受影响' -ForegroundColor Gray
} else {
    Write-Host '  1   只卸载飘字 MOD（当前没装，选它等于什么都不做）' -ForegroundColor DarkGray
}

Write-Host ''
if ($canFull) {
    Write-Host '  2   完全卸载（连 UE4SS 前置一起删）' -ForegroundColor White
    Write-Host '      游戏彻底回到没装过任何模组的状态' -ForegroundColor Gray
    Write-Host '      注意：其它依赖 UE4SS 的模组会一起失效' -ForegroundColor DarkYellow
} else {
    Write-Host '  2   完全卸载（连 UE4SS 一起删）  —— 本包不提供' -ForegroundColor DarkGray
    if ($isModPack) {
        Write-Host '      这个包当初只装了 MOD，没有装过 UE4SS。' -ForegroundColor DarkGray
        Write-Host '      你机器上的 UE4SS 是你自己（或别的整合包）装的，' -ForegroundColor DarkGray
        Write-Host '      里面可能还有别的模组，所以这里不帮你删。' -ForegroundColor DarkGray
    }
}

Write-Host ''
Write-Host '  直接回车 = 取消，什么都不做' -ForegroundColor DarkGray
Write-Host ''

$choice = ''
if ($autoYes) {
    if ($env:PBZDN_TEST_CHOICE) { $choice = $env:PBZDN_TEST_CHOICE }
} else {
    $choice = Read-Host '  输入 1 或 2'
    if ($choice) { $choice = $choice.Trim() }
}

# ---------------- 分支 1：只删 MOD ----------------
if ($choice -eq '1') {
    Title '正在移除飘字 MOD'

    if ($hasMod) {
        try {
            Remove-Item -LiteralPath $targetMod -Recurse -Force -Confirm:$false
            Ok '已删除 PBZ_DamageNumbers_Custom'
        } catch {
            Bad '删除失败：'
            Info $_.Exception.Message
            Info '请确认游戏已经完全退出（任务管理器里没有 PBZ.exe），再试一次。'
            Write-Host ''
            Hold
            exit 1
        }
    } else {
        Info 'MOD 本来就没装，不用删。'
    }

    # 校验
    Write-Host ''
    if (Test-Path $targetMod) {
        Bad 'MOD 文件夹还在，删除没成功。'
        Info '重启电脑后再运行一次这个卸载程序。'
        Write-Host ''
        Hold
        exit 1
    }
    Ok '校验通过：MOD 文件夹已不存在'

    if ($hasUE4SS) { Ok 'UE4SS 前置保留（其它模组照常工作）' }

    # 备份目录提示
    $bk = @()
    try {
        $bk = @(Get-ChildItem -LiteralPath $targetSteam -Directory -Filter '_backup_*' -ErrorAction SilentlyContinue)
    } catch { }
    if ($bk.Count -gt 0) {
        Write-Host ''
        Info ("另外还有 $($bk.Count) 个安装时自动备份的文件夹：")
        foreach ($b in $bk) { Info ("  " + $b.Name) }
        Info '里面是安装前的旧文件，留着不占事，想清理可以手动删掉。'
    }

    Write-Host ''
    Write-Host '  ============================================================' -ForegroundColor Green
    Write-Host '              飘字 MOD 已移除，游戏恢复原样' -ForegroundColor Green
    Write-Host '  ============================================================' -ForegroundColor Green
    Write-Host ''
    Write-Host '  进游戏后：数字停留时间回到 1 秒左右，回血数字变回白色。' -ForegroundColor Gray
    Write-Host '  想再装回来，双击同一个文件夹里的"一键安装.bat"就行。' -ForegroundColor Gray
}

# ---------------- 分支 2：完全卸载 ----------------
elseif ($choice -eq '2') {

    if (-not $canFull) {
        Title '这个包不提供完全卸载'
        if ($isModPack) {
            Info '你用的是"单独 MOD"版，UE4SS 不是这个包装的，'
            Info '删掉可能把你别的模组一起搞坏，所以这里不做。'
            Info ''
            Info '只想删飘字 MOD 的话，重新运行一次，选 1。'
        } else {
            Info '当前目录里没检测到 dwmapi.dll 和 UE4SS.dll，'
            Info '说明它们不在，或者已经被删过了，没东西可清。'
            Info ''
            Info '只想删飘字 MOD 的话，重新运行一次，选 1。'
        }
        Write-Host ''
        Hold
        exit 0
    }

    Write-Host ''
    Warn '即将删除下面这些：'
    Info 'ue4ss 整个文件夹（含里面所有模组、配置、日志）'
    Info 'dwmapi.dll'
    Info '安装时留下的 _backup_ 备份文件夹'
    Write-Host ''
    Info '游戏本体文件和存档不会被动。'
    Write-Host ''

    $confirm = ''
    if ($autoYes) {
        if ($env:PBZDN_TEST_CONFIRM) { $confirm = $env:PBZDN_TEST_CONFIRM }
    } else {
        $confirm = Read-Host '  确定吗？输入 yes 执行'
        if ($confirm) { $confirm = $confirm.Trim() }
    }

    if ($confirm -ne 'yes') {
        Info ''
        Info '已取消，什么都没改。'
        Write-Host ''
        Hold
        exit 0
    }

    Title '正在完全卸载'

    $fail = 0

    if (Test-Path $ue4ssDir) {
        try {
            Remove-Item -LiteralPath $ue4ssDir -Recurse -Force -Confirm:$false
            Ok '已删除 ue4ss 文件夹'
        } catch {
            Bad '删除 ue4ss 失败：'
            Info $_.Exception.Message
            Info '可能有进程占用，重启电脑后再试。'
            $fail++
        }
    }

    if (Test-Path $dllPath) {
        try {
            Remove-Item -LiteralPath $dllPath -Force -Confirm:$false
            Ok '已删除 dwmapi.dll'
        } catch {
            Bad '删除 dwmapi.dll 失败：'
            Info $_.Exception.Message
            $fail++
        }
    }

    try {
        Get-ChildItem -LiteralPath $targetSteam -Directory -Filter '_backup_*' -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                Remove-Item -LiteralPath $_.FullName -Recurse -Force -Confirm:$false
                Ok ('已清理备份 ' + $_.Name)
            } catch { }
        }
    } catch { }

    Write-Host ''
    if ($fail -eq 0) {
        Write-Host '  ============================================================' -ForegroundColor Green
        Write-Host '                已完全卸载，游戏恢复原版' -ForegroundColor Green
        Write-Host '  ============================================================' -ForegroundColor Green
        Write-Host ''
        Write-Host '  直接启动游戏即可，和没装过模组一模一样。' -ForegroundColor Gray
    } else {
        Write-Host '  ============================================================' -ForegroundColor Yellow
        Write-Host '                部分文件没删掉' -ForegroundColor Yellow
        Write-Host '  ============================================================' -ForegroundColor Yellow
        Write-Host ''
        Write-Host '  上面标 [X] 的没删成功，通常是文件被占用。' -ForegroundColor Gray
        Write-Host '  重启电脑后再运行一次卸载程序即可。' -ForegroundColor Gray
        Write-Host ''
        Hold
        exit 1
    }
}

# ---------------- 取消 ----------------
else {
    Info ''
    Info '已取消，什么都没做。'
}

Write-Host ''
Hold
exit 0
