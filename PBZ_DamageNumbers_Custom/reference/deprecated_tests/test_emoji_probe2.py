# -*- coding: utf-8 -*-
"""第二轮 emoji 探针离线验证。

目的不是验证游戏行为（那只能实机），而是确认：
  1. 探针代码本身不崩，异常路径也能把错误原文打进日志
  2. 各个分支（writeTest 开/关、资产缺失、方法缺失）都走得到
  3. 日志格式固定，方便之后 grep
"""
import lupa

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


PROBE = grab('probeEmoji')

# 真实情况：Conv_StringToText 抛错。这里故意复现这个错误。
MOCK = r'''
LOGS = {}
function log(s) LOGS[#LOGS + 1] = s end

-- ---------- 模拟 FText ----------
local FTextMT = {
    __index = {
        ToString = function(self) return self._s end,
        IsEmpty = function(self) return self._s == "" end,
        IsEmptyOrWhitespace = function(self) return self._s:match("^%s*$") ~= nil end,
    }
}
local function mkText(s) return setmetatable({ _s = s }, FTextMT) end
local function mkTextNoMT(s) return { _s = s } end   -- 没有元表：模拟 getmetatable 保护

-- ---------- 模拟资产 ----------
local MODE = ...   -- 'normal' / 'noasset' / 'nometatable' / 'emptytext'

local rows_data = {}
for i = 1, 34 do rows_data[i] = { EmojiIcon = mkText("row" .. i) } end
local R1 = rows_data[1]
local R10 = rows_data[10]

if MODE == 'nometatable' then
    R1.EmojiIcon = mkTextNoMT("物")
    R10.EmojiIcon = mkTextNoMT("韧")
end
if MODE == 'emptytext' then
    R1.EmojiIcon = mkText("")    -- 探针只探 row01，所以这里必须改 row01
    R10.EmojiIcon = mkText("")
end

local rowsWrap
rowsWrap = {
    ForEach = function(self, fn)
        for i = 1, 34 do
            fn(i, { get = function() return rows_data[i] end })
        end
    end
}

local asset = {
    GetPropertyValue = function(self, name)
        if MODE == 'noasset' then return nil end
        if name == "DamageTypeDisplayInfos" then return rowsWrap end
        return nil
    end
}

-- ---------- 模拟 KismetTextLibrary：复现真实报错 ----------
local lib = {
    Conv_StringToText = function(self, s)
        error("UObject: CallFunctionByNameWithArguments unsupported return type FText")
    end,
    Conv_IntToText = function(self, a, b, c, d, e)
        error("UObject: CallFunctionByNameWithArguments unsupported return type FText")
    end,
}
FindFirstOf = function(name)
    if name == "KismetTextLibrary" then return lib end
    return nil
end
StaticFindObject = function(...) return nil end
'''

RUN = r'''
Config = { probeEmoji = PROBE_ON, probeEmojiWrite = WRITE_ON }
probeEmoji(asset)
return table.concat(LOGS, "\n")
'''


def run(mode='normal', probe_on=True, write_on=True):
    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    src = MOCK.replace('local MODE = ...', 'local MODE = "%s"' % mode)
    run_src = (RUN.replace('PROBE_ON', 'true' if probe_on else 'false')
                  .replace('WRITE_ON', 'true' if write_on else 'false'))
    # 必须拼成一个 chunk：MOCK 里的 local（FTextMT/asset/lib/rows_data）
    # 只有同 chunk 的 PROBE 才看得见
    lua.execute(src + '\n' + PROBE + '\n' + run_src)
    return lua.globals().LOGS


def lines(tbl):
    n = len(tbl)
    return [tbl[i] for i in range(1, n + 1)]


ok = 0
fail = 0


def check(cond, msg):
    global ok, fail
    if cond:
        ok += 1
        print('  [PASS]', msg)
    else:
        fail += 1
        print('  [FAIL]', msg)


print('=== 场景 1：正常情况（writeTest 开）===')
out = lines(run('normal', True, True))
print('\n'.join('  ' + x for x in out))
print()
check(any('[1] row01 type=table' in x for x in out), '打印了 row01 类型')
check(any('mt keys' in x and '__index' in x for x in out), '枚举到元表键')
check(any('[2] IsEmpty ok=true' in x for x in out), 'IsEmpty 探测成功')
check(any('[3A]' in x and 'FAILED err=' in x for x in out), '打出了 Conv_StringToText 错误原文')
check(any('unsupported return type FText' in x for x in out), '错误原文内容完整')
check(any('[3B]' in x and 'FAILED err=' in x for x in out), '点调用形式也试了')
check(any('[3C]' in x and 'FAILED err=' in x for x in out), 'Conv_IntToText 对照也试了')
check(any('[3D] CDO ok=' in x for x in out), 'CDO 路径也试了')
check(any('[4A] row01 自赋值 ok=' in x for x in out), '自赋值日志有')
check(any('[4B] row10 <- row01' in x for x in out), '跨行互赋日志有')
check(any('[4C] row10 <- ""' in x for x in out), '空串赋值日志有')
check(any('[4D] row10:SetPropertyValue' in x for x in out), 'SetPropertyValue 日志有')
check(any('[5] row01 回读' in x for x in out), '复读校验有 row01')
check(any('[5] row10 回读' in x for x in out), '复读校验有 row10')
check(any('probe v2 done' in x for x in out), '有结束标记')

print('\n=== 场景 2：writeTest 关闭 ===')
out2 = lines(run('normal', True, False))
check(any('writeTest=false' in x for x in out2), '头部标了 writeTest=false')
check(any('[4] writeTest 关闭' in x for x in out2), '明确提示跳过写入')
check(not any('[4A]' in x for x in out2), '没有发生任何写入')
check(any('probe v2 done' in x for x in out2), '仍然正常结束')

print('\n=== 场景 3：资产没加载（rows 为 nil）===')
out3 = lines(run('noasset', True, True))
check(any('rows unavailable' in x for x in out3), '提示 rows unavailable')
check(not any('probe v2 done' in x for x in out3), '提前 return，不继续')

print('\n=== 场景 4：FText 没有元表（模拟 getmetatable 被保护）===')
out4 = lines(run('nometatable', True, True))
check(any('[1] getmetatable' in x for x in out4), '记录了元表情形')
check(any('[2] IsEmpty ok=false' in x for x in out4), '无元表时方法调用失败且不崩')
check(any('[5] row10 回读' in x for x in out4), '后续流程仍然走完')

print('\n=== 场景 5：某行本来就是空文本 ===')
out5 = lines(run('emptytext', True, True))
check(any('[2] IsEmpty ok=true val=true' in x for x in out5), 'IsEmpty 返回 true')

print('\n=== 场景 6：probeEmoji 总开关关闭 ===')
out6 = lines(run('normal', False, True))
check(len(out6) == 0, '完全静默，一行日志都不出')

print('\n' + '=' * 50)
print('通过 %d / 失败 %d' % (ok, fail))
raise SystemExit(0 if fail == 0 else 1)
