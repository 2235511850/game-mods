# -*- coding: utf-8 -*-
"""probeInput 离线冒烟测试。

目的：进游戏前先确认这条探针在「环境缺东少西」时不会崩。
真机上崩一次要重启游戏、还要重看日志，成本远高于这里跑一遍。
"""
import os
import sys

import lupa

HERE = os.path.dirname(os.path.abspath(__file__))
MAIN = open(os.path.join(HERE, '..', 'Scripts', 'main.lua'), encoding='utf-8').read().split('\n')

_fails = []


def check(cond, msg):
    print(('  [OK]   ' if cond else '  [FAIL] ') + msg)
    if not cond:
        _fails.append(msg)


def grab(name):
    """按函数名截取一段顶层函数（顶格 end 收尾）。"""
    head = 'local function %s(' % name
    start = next((i for i, ln in enumerate(MAIN) if ln.startswith(head)), None)
    if start is None:
        raise SystemExit('main.lua 里找不到 %s' % name)
    for j in range(start + 1, len(MAIN)):
        if MAIN[j] == 'end':
            return '\n'.join(MAIN[start:j + 1])
    raise SystemExit('%s 没有闭合的 end' % name)


FUNC = grab('probeInput')

# 各种环境的 mock。用 MODE 控制缺哪一块。
MOCK = '''
Config = { probeInput = PROBE_ON }

LOGS = {}
function log(m) LOGS[#LOGS + 1] = tostring(m) end

MODE = "MODE_NAME"

-- 默认给一套齐全的环境
io = { open = function(path, mode) return nil, "mock: no such file" end }
os = { time = function() return 1750000000 end, remove = function() return true end }
debug = { getinfo = function() return { source = "@/game/ue4ss/Mods/PBZ_DamageNumbers_Custom/Scripts/main.lua" } end }
Key = { F5 = 1, F6 = 2, F7 = 3, F8 = 4, F9 = 5, F10 = 6 }
ModifierKey = { MODCONTROL = 7 }
function RegisterKeyBind(...) return true end
function RegisterConsoleCommandHandler(...) return true end
function LoopAsync(...) return true end
function RegisterHook(...) return true end

if MODE == "noio" then
    io = nil
elseif MODE == "noopen" then
    io = { open = nil }
elseif MODE == "nokey" then
    Key = nil
    ModifierKey = nil
    RegisterKeyBind = nil
elseif MODE == "bindthrows" then
    function RegisterKeyBind(...) error("mock bind refused") end
elseif MODE == "nodebug" then
    debug = nil
elseif MODE == "full" then
    -- io 正常：第一个候选就能读到，返回可读可写的假文件对象
    io = {
        open = function(path, mode)
            if mode == "w" then
                return {
                    write = function(self, s) WRITTEN = s return true end,
                    close = function(self) return true end,
                }
            end
            return {
                read = function(self, fmt)
                    if fmt == "*l" then return "-- mock config line" end
                    return WRITTEN or ""
                end,
                close = function(self) return true end,
            }
        end,
    }
end
'''

RUN = '''
local ok, err = pcall(probeInput)
if not ok then
    LOGS[#LOGS + 1] = "!!! CRASH: " .. tostring(err)
end
'''


def run(mode, probe_on=True):
    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    src = MOCK.replace('MODE_NAME', mode).replace('PROBE_ON', 'true' if probe_on else 'false')
    lua.execute(src + '\n' + FUNC + '\n' + RUN)
    return list(lua.globals().LOGS.values()), lua


print('=== 场景 1：环境齐全但 io 读不到（最常见）===')
out, _ = run('normal')
check(not any('CRASH' in x for x in out), '没有崩溃')
check(any('input/io probe v1' in x for x in out), '打出了探针头部')
check(any('api |' in x for x in out), '打印了 API 可用性')
check(sum(1 for x in out if 'read #' in x and 'miss' in x) == 4, '4 个候选路径全部尝试并记录')
check(any('Key.F7=3' in x for x in out), '取到了 Key.F7 的值')
check(sum(1 for x in out if 'bind ' in x and 'ok=' in x) == 3, '三种绑定形式都试了（F7/F8/Ctrl+F9）')
check(any('pbzdnprobe' in x for x in out), '注册了控制台命令')
check(any('done' in x for x in out), '打出了结束行')

print('=== 场景 2：io 完全不可用 ===')
out, _ = run('noio')
check(not any('CRASH' in x for x in out), '没有崩溃')
check(any('io= nil' in x or 'io=nil' in x for x in out), '打印出 io=nil')
check(any('skipped: 没有 io.open' in x for x in out), '明确跳过并说明原因')
check(any('done' in x for x in out), '仍然走到结束行（不会中断）')

print('=== 场景 3：io 在但 io.open 被禁 ===')
out, _ = run('noopen')
check(not any('CRASH' in x for x in out), '没有崩溃')
check(any('skipped: 没有 io.open' in x for x in out), '走同一条跳过分支')

print('=== 场景 4：没有 Key / ModifierKey / RegisterKeyBind ===')
out, _ = run('nokey')
check(not any('CRASH' in x for x in out), '没有崩溃')
check(any('Key=nil' in x for x in out), 'Key 为 nil 时正常打印')
check(any('跳过：Key.F7 取不到' in x for x in out), '明确跳过热键段')
check(any('bind ' not in x or 'ok=' not in x for x in out), '没有出现伪造的绑定成功日志')

print('=== 场景 5：RegisterKeyBind 抛错 ===')
out, _ = run('bindthrows')
check(not any('CRASH' in x for x in out), '没有崩溃')
check(any('bind F7       ok=false' in x for x in out), 'F7 记为 ok=false')
check(any('mock bind refused' in x for x in out), '错误原文被打出来')
check(any('bind F8       ok=false' in x for x in out), 'F8 继续尝试，没有被 F7 的失败带停')

print('=== 场景 6：debug.getinfo 不可用 ===')
out, _ = run('nodebug')
check(not any('CRASH' in x for x in out), '没有崩溃')
check(any('script dir = nil' in x for x in out), 'dir 记成 nil')
check(sum(1 for x in out if 'read #' in x) == 3, '退回 3 个相对路径兜底')

print('=== 场景 7：io 完整可用（能写能读回）===')
out, _ = run('full')
check(not any('CRASH' in x for x in out), '没有崩溃')
check(any('read #1 OK' in x for x in out), '第一个候选就读到了 config.lua')
check(any('first line = -- mock config line' in x for x in out), '读到了文件首行')
check(any('write ok=true' in x for x in out), '写入自测成功')
check(any('readback=true match=true' in x for x in out), '读回内容与写入一致')
check(any('cleanup=true' in x for x in out), '临时文件已清理')

print('=== 场景 8：开关关闭 ===')
out, _ = run('normal', probe_on=False)
check(not any('input/io probe' in x for x in out), '关闭后一行都不输出')
check(not any('bind ' in x for x in out), '关闭后不注册任何热键')

print()
if _fails:
    print('失败 %d 项：' % len(_fails))
    for f in _fails:
        print('  -', f)
    sys.exit(1)
print('全部通过')
