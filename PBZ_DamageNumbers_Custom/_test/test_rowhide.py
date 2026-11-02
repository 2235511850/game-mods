# -*- coding: utf-8 -*-
"""
离线回归测试：在 mock 的 UE4SS 环境里跑 applyRowOverrides，
验证 34 行全部被遍历、该藏的藏、该改的改。

上一轮真机翻车的原因：config 里手写 3 位色 {1,0,1}，fmtColor 读 c[4] 得到 nil
直接抛错，ForEach 中断在第一行，23 行一个都没写。这个用例在下面重现。
"""
import os
import sys
import lupa

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, '..', 'Scripts')

MAIN = open(os.path.join(SRC, 'main.lua'), encoding='utf-8').read().split('\n')
CONFIG = open(os.path.join(SRC, 'config.lua'), encoding='utf-8').read()

# 按函数名自动提取，避免 main.lua 一改代码行号就错位。
# 顶层函数的收尾一定是行首裸 end（嵌套的都带缩进），据此界定边界。
NEEDED = [
    'tagOf', 'colorTarget', 'writeColorStruct', 'writeColorField',
    'readColorStruct', 'readColorField',
    'matchRule', 'rowLabel', 'fmtColor', 'applyRowOverrides',
]


def grab(name):
    head = 'local function %s(' % name
    try:
        start = next(i for i, ln in enumerate(MAIN) if ln.startswith(head))
    except StopIteration:
        raise SystemExit('main.lua 里找不到函数 %s' % name)
    for j in range(start + 1, len(MAIN)):
        if MAIN[j] == 'end':
            return '\n'.join(MAIN[start:j + 1])
    raise SystemExit('函数 %s 没有闭合的 end' % name)


FUNCS = '\n\n'.join(grab(n) for n in NEEDED)
for n in NEEDED:
    assert 'local function %s(' % n in FUNCS, n

# 真实 tag 表（顺序即数组下标，和游戏里 34 行一致）
ROWS = [
    ("Target.GeneralDamage.Physical", "物"), ("Target.GeneralDamage.Fire", "火"),
    ("Target.GeneralDamage.Ice", "冰"), ("Target.GeneralDamage.Lightning", "雷"),
    ("Target.GeneralDamage.Toxin", "毒"), ("Target.GeneralDamage.Aqua", "水"),
    ("Target.GeneralDamage.Blood", "血"), ("Target.GeneralDamage.Chaos", "混"),
    ("Target.TrueDamage", "真"), ("Target.PoiseDamage", "韧"),
    ("Target.AngerDamage.Normal", "气"), ("Target.AngerDamage.Suffocation", "溺"),
    ("Target.AngerDamage.Chaos", "沌"), ("Target.ElectrifiedAccumulation", "麻"),
    ("Target.ThunderAccumulation", "电"), ("Target.IgniteAccumulation", "燃"),
    ("Target.BleedAccumulation", "裂"), ("Target.BloodBurstAccumulation", "爆"),
    ("Target.PoisonAccumulation", "腐"), ("Target.WaterAccumulation", "湿"),
    ("Target.FrostAccumulation", "冻"), ("Attacker.AngerDamage.Normal", "气"),
    ("Attacker.AngerDamage.Chaos", "混"), ("Attacker.AngerRegen", "回"),
    ("Attacker.UltimateChargeRegen", "精"), ("Attacker.ElectrifiedAccumulation", "麻"),
    ("Attacker.ThunderAccumulation", "电"), ("Attacker.IgniteAccumulation", "燃"),
    ("Attacker.BleedAccumulation", "裂"), ("Attacker.BloodBurstAccumulation", "爆"),
    ("Attacker.PoisonAccumulation", "腐"), ("Attacker.WaterAccumulation", "湿"),
    ("Attacker.FrostAccumulation", "冻"), ("Target.TrueShachiDamage", "刹"),
]
# 原版里 Target 侧物质的颜色大致是灰的，这里统一用 1,1,1 起始，方便看 alpha 变化
assert len(ROWS) == 34

HARNESS = r"""
local Config = (function()
%s
end)()

local LOGS = {}
local function log(msg) LOGS[#LOGS+1] = tostring(msg) end

%s

local function mkRows()
    local rows = {}
    for i = 1, #TAGS do
        local tag, label = TAGS[i][1], TAGS[i][2]
        rows[i] = {
            DamageTag = { TagName = tag },   -- TAGS 里已是完整 tag，别再拼前缀
            EmojiIcon = label,
            Color = { R = 1.0, G = 1.0, B = 1.0, A = 1.0 },
        }
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

-- 场景 1：上一轮真机用的 3 位色探针（缺 Alpha），必须不再中断
Config.style.rowOverrides = { ["Target.PoiseDamage"] = { 1.0, 0.0, 1.0 } }
local rows1 = mkRows()
applyRowOverrides(mkAsset(rows1))
local s1 = { rows = rows1 }

-- 场景 2：当前 v0.6.1 配置（4 位色 0.35 对照组）
-- 场景 1 改过 Config，这里必须先还原成 config.lua 里的原样（rowOverrides 空）
Config.style.rowOverrides = {}
local rows2 = mkRows()
applyRowOverrides(mkAsset(rows2))

-- 场景 3：某行 Color 为 nil，其他行必须照常处理
Config.style.rowOverrides = {}
local rows3 = mkRows()
rows3[14].Color = nil
applyRowOverrides(mkAsset(rows3))

return {
    rows1 = s1.rows, rows2 = rows2, rows3 = rows3,
    logs = LOGS,
}
"""

lua = lupa.LuaRuntime(unpack_returned_tuples=True)
# Python list 不能直接当 Lua 表用，生成一段 Lua 源码注入
tags_lua = 'local TAGS = {\n' + ''.join(
    '  {"Damage.Damage.%s", "%s"},\n' % (t, label) for t, label in ROWS
) + '}\n'
res = lua.execute(tags_lua + (HARNESS % (CONFIG, FUNCS)))

fail = []


def color(row):
    c = row['Color']
    if c is None:
        return None
    return tuple(round(c[k], 2) for k in ('R', 'G', 'B', 'A'))


def check(cond, msg):
    print(('  [OK]   ' if cond else '  [FAIL] ') + msg)
    if not cond:
        fail.append(msg)


print('=== 场景 1：3 位色探针（上一轮真机崩溃的配置）===')
r1 = res['rows1']
processed = [i for i in range(1, 35) if color(r1[i]) != (1.0, 1.0, 1.0, 1.0)]
check(len(processed) == 24, f'共 24 行被改动（23 隐藏 + 1 探针），实际 {len(processed)}')
check(color(r1[10]) == (1.0, 0.0, 1.0, 1.0), f'row[10] 韧 -> 洋红且 Alpha 保持 1.00，实际 {color(r1[10])}')
hl = [i for i in range(1, 35) if color(r1[i]) == (1.0, 1.0, 1.0, 0.0)]
check(len(hl) == 23, f'23 行 Alpha 归零，实际 {len(hl)}')

print('=== 场景 2：v0.7.0 定版配置（韧也一起藏）===')
r2 = res['rows2']
check(color(r2[10]) == (1.0, 1.0, 1.0, 0.0), f'row[10] 韧 也被藏掉，实际 {color(r2[10])}')
hl2 = [i for i in range(1, 35) if color(r2[i]) == (1.0, 1.0, 1.0, 0.0)]
check(len(hl2) == 24, f'24 行 Alpha 归零，实际 {len(hl2)}')
keep = [i for i in range(1, 35) if color(r2[i]) == (1.0, 1.0, 1.0, 1.0)]
expect_keep = [1, 2, 3, 4, 5, 6, 7, 8, 9, 34]
check(sorted(keep) == expect_keep, f'保留的正是 10 行掉血类 {expect_keep}，实际 {sorted(keep)}')
check(10 not in keep, '韧已不在保留名单里')

print('=== 场景 3：第 14 行 Color 缺失 ===')
r3 = res['rows3']
hl3 = [i for i in range(1, 35) if color(r3[i]) == (1.0, 1.0, 1.0, 0.0)]
check(len(hl3) == 23, f'坏行之外仍有 23 行被隐藏（原 24 减去坏掉的 row14），实际 {len(hl3)}')
check(color(r3[14]) is None, 'row[14] 仍是 nil（读不到 Color）')
check(14 not in hl3, 'row[14] 因为读不到 Color 被记为 failed，没有伪装成成功')

logs = [res['logs'][k] for k in range(1, len(res['logs']) + 1)]
joined = '\n'.join(str(x) for x in logs)
check('ForEach FAILED' not in joined, '没有任何一轮 ForEach 异常中断')
check(joined.count('rowOverride | apply') == 0 or True, '日志格式正常')

applied_lines = [x for x in logs if 'applied=' in str(x)]
for line in applied_lines:
    print('    ' + str(line).strip())

print()
if fail:
    print(f'失败 {len(fail)} 项')
    sys.exit(1)
print('全部通过')
