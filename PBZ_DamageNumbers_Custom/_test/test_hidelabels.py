# -*- coding: utf-8 -*-
"""applyHideLabels（去标签字）离线验证。

重点不是验证游戏行为，而是确认在各种失败情形下：
  - 不抛错、不中断整个流程
  - 该跳过的跳过，该继续的继续
  - 日志能说清发生了什么
"""
import sys
import lupa

sys.stdout.reconfigure(encoding='utf-8')

MAIN = open('../Scripts/main.lua', encoding='utf-8').read().split('\n')


def grab(name):
    head = 'local function %s(' % name
    start = next((i for i, ln in enumerate(MAIN) if ln.startswith(head)), None)
    if start is None:
        raise SystemExit('main.lua 里找不到函数 %s' % name)
    for j in range(start + 1, len(MAIN)):
        if MAIN[j] == 'end':
            return '\n'.join(MAIN[start:j + 1])
    raise SystemExit('函数 %s 没有闭合的 end' % name)


FUNCS = '\n\n'.join(grab(n) for n in ('getTextLib', 'makeEmptyText', 'applyHideLabels'))

MOCK = r'''
LOGS = {}
function log(s) LOGS[#LOGS + 1] = s end

-- 模拟 FText：table + 元表，只有 ToString（和实机一致）
local FTextMT = { __index = { ToString = function(self) return self._s end } }
local function mkText(s) return setmetatable({ _s = s }, FTextMT) end

-- MODE 控制各种失败情形
local MODE = "__MODE__"

-- 模拟 CDO 的 KismetTextLibrary
local cdo = {
    Conv_StringToText = function(self, s)
        if MODE == "ctor_error" then error("boom: ctor failed") end
        if MODE == "ctor_notempty" then return mkText("X") end   -- 构造了但不是空串
        return mkText(s or "")
    end,
}

StaticFindObject = function(path)
    if MODE == "no_cdo" then return nil end
    if path == "/Script/Engine.Default__KismetTextLibrary" then return cdo end
    return nil
end

-- 模拟行数据：每行 EmojiIcon 原本有字
local rows_data = {}
for i = 1, 34 do rows_data[i] = { EmojiIcon = mkText("L" .. i) } end
if MODE == "nil_row" then rows_data[5] = nil end   -- 第 5 行拿不到

local rowsWrap = {
    ForEach = function(self, fn)
        for i = 1, 34 do
            local r = rows_data[i]
            fn(i, { get = function() return r end })
        end
    end,
}

local asset = {
    GetPropertyValue = function(self, name)
        if MODE == "no_rows" then return nil end
        if name == "DamageTypeDisplayInfos" then return rowsWrap end
        return nil
    end,
}

Config = { style = { hideLabels = __ENC__ } }
'''

RUN = 'applyHideLabels(asset)\nreturn table.concat(LOGS, "\\n")'


def run(mode='normal', enabled=True):
    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    src = (MOCK.replace('__MODE__', mode)
               .replace('__ENC__', 'true' if enabled else 'false'))
    lua.execute(src + '\n' + FUNCS + '\n' + RUN)
    txt = lua.execute('return table.concat(LOGS, "\\n")')
    return txt.split('\n') if txt else []


ok = fail = 0


def check(cond, msg):
    global ok, fail
    if cond:
        ok += 1
        print('  [PASS]', msg)
    else:
        fail += 1
        print('  [FAIL]', msg)


print('=== 场景 1：正常（34 行全部清空）===')
out = run('normal', True)
print('\n'.join('  ' + x for x in out))
print()
check(any('空 FText 已就绪' in x for x in out), '空 FText 构造成功')
check(any('applied=34 failed=0' in x for x in out), '34 行全部处理成功')
check(any('verify 共 34 行，其中已清空 34 行' in x for x in out), '复读校验确认 34 行已清空')
check(not any('首个错误' in x for x in out), '没有错误记录')

print('\n=== 场景 2：hideLabels = false ===')
out2 = run('normal', False)
check(len([x for x in out2 if x.strip()]) == 0, '完全静默')

print('\n=== 场景 3：CDO 拿不到 ===')
out3 = run('no_cdo', True)
print('\n'.join('  ' + x for x in out3))
check(any('CDO 拿不到，跳过' in x for x in out3), '明确提示跳过')
check(not any('applied=' in x for x in out3), '没有继续写入')

print('\n=== 场景 4：Conv_StringToText 抛错 ===')
out4 = run('ctor_error', True)
check(any('空 FText 构造失败，跳过' in x for x in out4), '构造失败被识别并跳过')
check(not any('applied=' in x for x in out4), '没有继续写入')

print('\n=== 场景 5：构造出来但不是空串 ===')
out5 = run('ctor_notempty', True)
check(any('空 FText 构造失败，跳过' in x for x in out5), '回读非空串时判定失败（不盲信调用成功）')

print('\n=== 场景 6：某行拿不到（row 为 nil）===')
out6 = run('nil_row', True)
print('\n'.join('  ' + x for x in out6))
check(any('applied=33 failed=0' in x for x in out6), '跳过坏行，其余 33 行照常')
check(any('verify 共 33 行，其中已清空 33 行' in x for x in out6), '复读校验也一致')

print('\n=== 场景 7：资产数组读不到 ===')
out7 = run('no_rows', True)
check(any('rows unavailable' in x for x in out7), '提示 rows unavailable，不崩')

print('\n' + '=' * 50)
print('通过 %d / 失败 %d' % (ok, fail))
raise SystemExit(0 if fail == 0 else 1)
