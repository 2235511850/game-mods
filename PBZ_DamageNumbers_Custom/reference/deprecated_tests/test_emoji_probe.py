# -*- coding: utf-8 -*-
"""
冒烟测试：probeEmoji 在三种环境下的行为。

这是纯只读诊断，重点不是结果对不对，而是：
1. EmojiIcon 类型异常时不崩
2. FindFirstOf / StaticFindObject 不存在时不崩（离线环境就是这种）
3. 日志格式正常
"""
import os
import lupa

HERE = os.path.dirname(os.path.abspath(__file__))
MAIN = open(os.path.join(HERE, '..', 'Scripts', 'main.lua'), encoding='utf-8').read().split('\n')


def grab(name):
    head = 'local function %s(' % name
    start = next(i for i, ln in enumerate(MAIN) if ln.startswith(head))
    for j in range(start + 1, len(MAIN)):
        if MAIN[j] == 'end':
            return '\n'.join(MAIN[start:j + 1])
    raise SystemExit('函数 %s 没有闭合 end' % name)


FUNC = grab('probeEmoji')

HARNESS = r"""
local LOGS = {}
local function log(m) LOGS[#LOGS+1] = tostring(m) end

local Config = { probeEmoji = true }

%(func)s

local function mkRows(kind)
    local rows = {}
    for i = 1, 34 do
        local emoji
        if kind == "method" then
            emoji = { s = "物", ToString = function(self) return self.s end }
        elseif kind == "plain_string" then
            emoji = "物"
        elseif kind == "nil_value" then
            emoji = nil
        elseif kind == "no_tostring" then
            emoji = {}
        end
        rows[i] = { EmojiIcon = emoji }
    end
    return rows
end

local function mkAsset(rows)
    return {
        GetPropertyValue = function(self, name)
            if name ~= "DamageTypeDisplayInfos" then return nil end
            return {
                ForEach = function(self2, fn)
                    for i = 1, #rows do
                        local r = rows[i]
                        fn(i, { get = function() return r end })
                    end
                end,
            }
        end,
    }
end

local OUT = {}

-- 场景 A：正常 userdata 风格 + 找不到 KismetTextLibrary（离线就是这种）
probeEmoji(mkAsset(mkRows("method")))
OUT.A = LOGS

-- 场景 B：EmojiIcon 是纯字符串（没有 ToString 方法）
LOGS = {}
probeEmoji(mkAsset(mkRows("plain_string")))
OUT.B = LOGS

-- 场景 C：EmojiIcon 全为 nil
LOGS = {}
probeEmoji(mkAsset(mkRows("nil_value")))
OUT.C = LOGS

-- 场景 D：EmojiIcon 是 table 但没有 ToString
LOGS = {}
probeEmoji(mkAsset(mkRows("no_tostring")))
OUT.D = LOGS

-- 场景 E：开关关闭，应当一条日志都不产生
LOGS = {}
Config.probeEmoji = false
probeEmoji(mkAsset(mkRows("method")))
OUT.E = LOGS

return OUT
"""

lua = lupa.LuaRuntime(unpack_returned_tuples=True)
res = lua.execute(HARNESS % {'func': FUNC})

fail = []


def get(name):
    t = res[name]
    return [str(t[k]) for k in range(1, len(t) + 1)] if t else []


def check(cond, msg):
    print(('  [OK]   ' if cond else '  [FAIL] ') + msg)
    if not cond:
        fail.append(msg)


print('=== 场景 A：正常 userdata + 无 KismetTextLibrary ===')
a = get('A')
for line in a:
    print('    ' + line)
check(any('共 34 行' in x for x in a), '统计到 34 行')
check(any('userdatax34' in x or 'tablex34' in x for x in a), '类型分布正确')
check(any('ToString 成功 34' in x for x in a), '34 行 ToString 全部成功')
check(any('FindFirstOf(KismetTextLibrary) call=false' in x for x in a), '离线环境下 FindFirstOf 缺失被捕获，未崩溃')
check(any('StaticFindObject(单参)' in x for x in a), '退回尝试了 StaticFindObject')

print('=== 场景 B：EmojiIcon 是纯字符串 ===')
b = get('B')
check(any('type=string' in x for x in b), '识别为 string')
check(any('ToString=FAILED' in x for x in b), '调用 ToString 失败被捕获')
check(any('ToString 成功 0' in x for x in b), '成功数为 0')

print('=== 场景 C：EmojiIcon 全 nil ===')
c = get('C')
check(any('type=nil' in x for x in c), '识别为 nil，未崩溃')
check(any('共 34 行' in x for x in c), '仍然走完 34 行')

print('=== 场景 D：table 但没有 ToString ===')
d = get('D')
check(any('ToString=FAILED' in x for x in d), '缺方法被捕获')

print('=== 场景 E：开关关闭 ===')
e = get('E')
check(len(e) == 0, f'一条日志都不产生，实际 {len(e)} 条')

print()
if fail:
    print(f'失败 {len(fail)} 项')
    raise SystemExit(1)
print('全部通过')
