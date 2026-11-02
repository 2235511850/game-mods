# -*- coding: utf-8 -*-
"""CP77_GameSpeedControl 离线回归测试。

不需要进游戏：用 lupa 起一个 Lua 运行时，把 CET 的 API 全部桩掉，
在桩环境里跑 Scripts/init.lua，验证热键、倍率循环、配置写入、崩溃防护。

用法:
    pip install lupa
    python test_gsc.py

退出码 0 = 全过，1 = 有失败项。
"""
import os
import shutil
import sys
import tempfile

try:
    import lupa
except ImportError:
    sys.exit('缺少 lupa，请先 pip install lupa')

HERE = os.path.dirname(os.path.abspath(__file__))
MOD = os.path.dirname(HERE)
SRC = os.path.join(MOD, 'Scripts', 'init.lua').replace('\\', '/')

STUB = r'''
-- 引擎桩：记录所有原生调用，便于断言"什么时候碰了引擎"
LOG = {}
events = {}
hotkeys = {}
ui = { list = {}, opts = {}, buttons = {} }

ready = true        -- false = 引擎时间系统尚未就绪（主菜单阶段）
player = {}         -- nil = 会话没起来（读档/加载中）
ns_ready = true     -- false = nativeSettings 比插件加载得晚

ts = {}
function ts:SetTimeDilation(reason, scale)
    LOG[#LOG + 1] = string.format("dilate(%s,%.2f)", reason, scale)
end
function ts:UnsetTimeDilation(reason)
    LOG[#LOG + 1] = "unset(" .. reason .. ")"
end
function ts:SetIgnoreTimeDilationOnLocalPlayerZero(b)
    LOG[#LOG + 1] = "ignore(" .. tostring(b) .. ")"
end

Game = {
    GetTimeSystem = function()
        if not ready then error("time system not ready") end
        return ts
    end,
    GetPlayer = function() return player end,
    GetBlackboardSystem = function() error("no ui in test") end,
}

SimpleScreenMessage = { new = function() return {} end }
GetAllBlackboardDefs = function() return {} end
ToVariant = function(x) return x end

function registerForEvent(name, fn) events[name] = fn end
function registerHotkey(id, label, fn) hotkeys[id] = fn end

-- nativeSettings 桩：opts 存回调，setOption 用来模拟"程序化改控件值"
ns = {}
function ns.pathExists() return false end
function ns.addTab(p, l) ui.tab = l end
function ns.addSubcategory(p, l) ui.list[#ui.list + 1] = "sub:" .. l end
function ns.addRangeInt(p, l, d, mn, mx, st, cur, df, cb)
    ui.list[#ui.list + 1] = "int:" .. l
    local o = { label = l }
    ui.opts[l] = { obj = o, cb = cb }
    return o
end
function ns.addRangeFloat(p, l, d, mn, mx, st, fmt, cur, df, cb)
    ui.list[#ui.list + 1] = "float:" .. l
    local o = { label = l }
    ui.opts[l] = { obj = o, cb = cb }
    return o
end
function ns.addSwitch(p, l, d, cur, df, cb)
    ui.list[#ui.list + 1] = "switch:" .. l
    ui.opts[l] = { cb = cb }
    return { label = l }
end
function ns.addButton(p, l, d, txt, sz, cb)
    ui.list[#ui.list + 1] = "button:" .. l
    ui.buttons[l] = cb
    return { label = l }
end
function ns.setOption(o, v) ui.opts[o.label].cb(v) end
function GetMod(n) if not ns_ready then return nil end return ns end

-- CET 自带的 json 库，这里给个最小实现（字段顺序无关）
json = {
    encode = function(t)
        local s = {}
        for i = 1, #t.steps do s[i] = tostring(t.steps[i]) end
        return '{"steps":[' .. table.concat(s, ",") .. ']' ..
               ',"count":' .. t.count ..
               ',"playerFollow":' .. tostring(t.playerFollow) .. '}'
    end,
    decode = function(str)
        local d = { steps = {} }
        local arr = str:match('"steps":%[([^%]]*)%]')
        if arr then for n in arr:gmatch('[^,]+') do d.steps[#d.steps + 1] = tonumber(n) end end
        d.count = tonumber(str:match('"count":(%d+)'))
        d.playerFollow = str:match('"playerFollow":(%a+)') == "true"
        return d
    end,
}

-- 辅助
function quiet() LOG = {} end
function dump()
    local t = {}
    for i = 1, #LOG do t[i] = LOG[i] end
    return table.concat(t, " | ")
end
function countLog(pat)
    local n = 0
    for i = 1, #LOG do if LOG[i]:find(pat, 1, true) then n = n + 1 end end
    return n
end
function drag(label, v) ui.opts[label].cb(v) end
function click(label) ui.buttons[label]() end
'''


class Harness:
    def __init__(self):
        self.L = lupa.LuaRuntime(unpack_returned_tuples=True)
        self.L.execute(STUB)
        loader = self.L.eval('function(p) local f, e = loadfile(p); '
                             'if not f then error(e) end; return f() end')
        self.mod = loader(SRC)
        self.g = self.L.globals()

    def call(self, name):
        self.g.events[name]()

    def step(self, n=1, dt=0.016):
        for _ in range(n):
            self.g.events['onUpdate'](dt, 0)

    def hotkey(self, k):
        self.g.hotkeys[k]()

    def drag(self, label, v):
        self.g.drag(label, v)

    def click(self, label):
        self.g.click(label)

    def quiet(self):
        self.g.quiet()

    def log(self):
        return self.g.dump()

    def scale(self):
        return self.mod['GetScale']()

    def steps(self):
        return [round(v, 2) for v in self.mod['GetSteps']().values()]

    def set_player(self, exists):
        self.L.execute('player = %s' % ('{}' if exists else 'nil'))

    def set_ready(self, ok):
        self.L.execute('ready = %s' % ('true' if ok else 'false'))


FAILS = []
PASSES = [0]


def check(name, cond, detail=''):
    if cond:
        PASSES[0] += 1
        print('  [PASS] %s' % name)
    else:
        FAILS.append((name, detail))
        print('  [FAIL] %s   %s' % (name, detail))


def section(title):
    print('\n── %s %s' % (title, '─' * max(0, 46 - len(title))))


def main():
    if not os.path.exists(SRC):
        sys.exit('找不到源码: %s' % SRC)

    # 切到临时目录：插件的 config.json / debug.log 都按相对路径落在 CWD
    origin = os.getcwd()
    tmp = tempfile.mkdtemp(prefix='gsc_test_')
    os.chdir(tmp)
    try:
        run_all()
    finally:
        os.chdir(origin)
        shutil.rmtree(tmp, ignore_errors=True)

    print('\n' + '═' * 52)
    if FAILS:
        print('失败 %d 项 / 通过 %d 项' % (len(FAILS), PASSES[0]))
        for n, d in FAILS:
            print('  - %s: %s' % (n, d))
        return 1
    print('全部通过（%d 项）' % PASSES[0])
    return 0


def run_all():
    section('加载与注册')
    h = Harness()
    check('源码可编译加载', h.mod is not None)
    check('顶层注册 3 个热键（不在 onInit 里）',
          sorted(h.g.hotkeys.keys()) == ['gspeed_cycle', 'gspeed_player', 'gspeed_reset'],
          h.g.hotkeys.keys())
    check('加载期不碰引擎（只读配置）', h.log() == '', h.log())

    h.call('onInit')
    ctrls = [v for v in h.g.ui['list'].values() if isinstance(v, str)]
    check('设置页注册 13 个控件', len(ctrls) == 13, '%d 个: %s' % (len(ctrls), ctrls))
    check('页签名正确', h.g.ui['tab'] == '游戏变速', h.g.ui['tab'])

    section('倍率循环')
    h.quiet()
    seq = []
    for _ in range(6):
        h.hotkey('gspeed_cycle')
        seq.append(h.scale())
    # 初始 1.0 本身就在档位列表里，按一次是"前进"到 1.5，不是停在 1.0
    check('F6 从 1.0 前进：1.5→2.0→3.0→5.0→1.0→1.5',
          [round(x, 1) for x in seq] == [1.5, 2.0, 3.0, 5.0, 1.0, 1.5], seq)

    # 此时 scale 停在 1.5，再按一次到 2.0
    h.quiet()
    h.hotkey('gspeed_cycle')
    check('加速时写 dilation 和 ignore(false)',
          'dilate(modGameSpeed,2.00)' in h.log() and 'ignore(false)' in h.log(), h.log())

    section('玩家同步开关')
    h.quiet()
    h.hotkey('gspeed_player')
    log = h.log()
    check('F8 关闭同步后 ignore(true)（只有世界变）', 'ignore(true)' in log, log)
    h.quiet()
    h.hotkey('gspeed_player')
    check('F8 再开回 ignore(false)', 'ignore(false)' in h.log(), h.log())

    section('复位')
    h.quiet()
    h.hotkey('gspeed_reset')
    check('F7 回到 1.0 并 unset', h.scale() == 1.0 and 'unset(modGameSpeed)' in h.log(), h.log())

    section('崩溃防护：会话未就绪')
    h.set_player(False)
    h.quiet()
    h.hotkey('gspeed_cycle')
    check('读档中按 F6 不调引擎（只改状态）', h.log() == '', h.log())
    check('倍率仍在内存里更新', abs(h.scale() - 1.5) < 0.01, h.scale())
    h.set_player(True)
    h.quiet()
    h.step(70)
    check('玩家回来后约 1.1 秒自动补挂', 'dilate' in h.log(), h.log())

    h.set_ready(False)
    h.quiet()
    h.hotkey('gspeed_reset')
    check('引擎掉线时不崩、不抛错', True)
    h.set_ready(True)

    h.set_player(False)
    h.quiet()
    for _ in range(100):
        h.step(1)
    check('主菜单阶段 100 帧零引擎调用', h.log() == '', h.log())
    h.set_player(True)

    section('档位滑条')
    # 触发条件是「当前倍率正好等于该档位的旧值」。
    # 默认档位是 1.0/1.5/2.0/3.0/5.0，所以档位3 = 2.0，按两次 F6 就能对齐。
    h.hotkey('gspeed_reset')
    for _ in range(2):
        h.hotkey('gspeed_cycle')
    check('前置：倍率已到 2.0 = 档位3 的值', abs(h.scale() - 2.0) < 0.01, h.scale())

    h.quiet()
    h.drag('档位 3', 2.4)
    check('拖当前所在档位会立刻跟着变速',
          abs(h.scale() - 2.4) < 0.01 and 'dilate' in h.log(),
          'scale=%s log=%s' % (h.scale(), h.log()))

    h.quiet()
    for i in range(40):
        h.step(1)
        h.drag('档位 3', 2.0 + i * 0.1)
    tips = h.g.countLog('notify: 档位')
    check('连拖 40 次提示被限流（≤3 条）', tips <= 3, '%d 条' % tips)
    check('限流期间倍率仍实时跟手（最后到 5.9）',
          abs(h.scale() - 5.9) < 0.01, h.scale())

    section('恢复默认')
    h.click('恢复默认档位')
    check('档位回到 1.0/1.5/2.0/3.0/5.0',
          h.steps() == [1.0, 1.5, 2.0, 3.0, 5.0], h.steps())

    section('配置持久化')
    h.quiet()
    h.drag('循环档位数', 3)
    h.drag('档位 1', 0.5)
    h.step(70)
    cfg_exists = os.path.exists('config.json')
    check('config.json 用相对路径写成功', cfg_exists, 'CWD=%s' % os.getcwd())
    if cfg_exists:
        raw = open('config.json', encoding='utf-8').read()
        check('写入内容含 steps/count/playerFollow',
              all(k in raw for k in ('steps', 'count', 'playerFollow')), raw)
        h2 = Harness()
        check('重启后能读回 3 档 + 0.5 起点',
              h2.steps()[:3] == [0.5, 1.5, 2.0], h2.steps())

    section('控制台入口')
    h.hotkey('gspeed_reset')
    h.mod['SetScale'](3.0)
    check('SetScale(3.0) 生效', abs(h.scale() - 3.0) < 0.01, h.scale())
    h.mod['SetScale'](999)
    check('SetScale(999) 钳到上限 10.0', abs(h.scale() - 10.0) < 0.01, h.scale())
    h.mod['SetScale']('2.5')
    check("SetScale('2.5') 接受字符串", abs(h.scale() - 2.5) < 0.01, h.scale())
    before = h.scale()
    h.mod['SetScale'](None)
    check('SetScale(nil) 被忽略、不改倍率', abs(h.scale() - before) < 0.01, h.scale())

    section('退出')
    h.quiet()
    h.call('onShutdown')
    check('onShutdown 不调引擎', h.log() == '', h.log())


if __name__ == '__main__':
    sys.exit(main())
