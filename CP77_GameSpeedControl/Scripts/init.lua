--[[
    GameSpeedControl v5 —— 赛博朋克 2077 游戏变速（CET Lua 插件，无额外依赖）

    原理：引擎时间膨胀。SetTimeDilation 改变世界时间流速，
          SetIgnoreTimeDilationOnLocalPlayerZero(false) 让 V 自己也跟着变快。

    热键：gspeed_cycle 按「循环档位」切换 / gspeed_reset 回 1.0 / gspeed_player 切换玩家同步
    设置页：设置 → Mods → 游戏变速（倍率与手感 / F6 循环档位）
    控制台：GetMod("GameSpeedControl").SetScale(2.0)

    v4：循环档位可配置，存 config.json，重启后保留。
    v5：配置改用相对路径写入（CET 的 io 沙箱拒收绝对路径，报 EINVAL 22）；
        档位滑条拖动即生效、提示限流；新增「切到下一档 / 回到原速」两个不依赖热键的按钮。

    版本号对照：v4 = 1.0.0（N 网首发的中英两个 zip，配置写入有 bug）
                v5 = 1.1.0（当前，修复版）
]]

local MODNAME   = "GameSpeedControl"
local REASON    = "modGameSpeed"
local MAX_STEPS = 5
local DEFAULT_STEPS = { 1.0, 1.5, 2.0, 3.0, 5.0 }
local STEP_MIN, STEP_MAX = 0.1, 10.0
local REAPPLY_GAP = 1.0
local SAVE_EVERY_TICKS = 30

local function modDir()
    if type(debug) == "table" and debug.getinfo then
        local ok, info = pcall(function() return debug.getinfo(1, "S") end)
        if ok and info and info.source then
            local src = info.source:gsub("^@", "")
            local dir = src:match("^(.*)[/\\][^/\\]+$")
            if dir and dir ~= "" and dir ~= "." then return dir end
        end
    end
    return "C:/app/Steam/steamapps/common/Cyberpunk 2077/bin/x64/plugins/cyber_engine_tweaks/mods/GameSpeedControl"
end

local DIR      = modDir()
local LOG_NAME = "debug.log"
local CFG_NAME = "config.json"

-- CET 的 io 沙箱只接受相对路径：绝对路径一律返回 nil + EINVAL(22)。
-- 相对路径的基准正好是 mod 自己的目录，所以优先按文件名打开，实在不行再回退绝对路径。
local function openLocal(name, mode)
    local ok, f = pcall(io.open, name, mode)
    if ok and f then return f end
    local ok2, f2 = pcall(io.open, DIR .. "/" .. name, mode)
    if ok2 and f2 then return f2 end
    return nil
end

local function dbg(msg)
    msg = string.format("[%s] %s", os.date("%H:%M:%S"), tostring(msg))
    print("[" .. MODNAME .. "] " .. msg)
    pcall(function()
        local f = openLocal(LOG_NAME, "a")
        if f then f:write(msg .. "\n"); f:close() end
    end)
end

local function clampNum(v, lo, hi)
    v = tonumber(v)
    if not v then return nil end
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function round1(v) return math.floor(v * 10 + 0.5) / 10 end

local state = {
    scale        = 1.0,
    playerFollow = true,
    modified     = false,
    timer        = 0.0,
    settingsDone = false,
    ticks        = 0,
    steps        = { 1.0, 1.5, 2.0, 3.0, 5.0 },
    count        = 5,
    dirty        = false,
    opts         = { steps = {} },
}

------------------------------------------------------------------
-- 配置
------------------------------------------------------------------
local function loadConfig()
    local loaded = false
    local ok, err = pcall(function()
        local f = openLocal(CFG_NAME, "r")
        if not f then return end
        local raw = f:read("*a")
        f:close()
        if not raw or raw == "" then return end

        local data = json.decode(raw)
        if type(data) ~= "table" then return end
        loaded = true

        if type(data.steps) == "table" then
            for i = 1, MAX_STEPS do
                local v = clampNum(data.steps[i], STEP_MIN, STEP_MAX)
                if v then state.steps[i] = round1(v) end
            end
        end
        local c = clampNum(data.count, 1, MAX_STEPS)
        if c then state.count = math.floor(c + 0.5) end
        if type(data.playerFollow) == "boolean" then state.playerFollow = data.playerFollow end
    end)
    if not ok then
        dbg("配置读取失败，用默认档位: " .. tostring(err))
    elseif loaded then
        dbg(string.format("配置已读取：%d 档", state.count))
    else
        dbg("没有 config.json，使用默认档位 1.0/1.5/2.0/3.0/5.0")
    end
end

local function saveConfig()
    local ok, err = pcall(function()
        if type(json) ~= "table" or type(json.encode) ~= "function" then
            error("json 库不可用")
        end
        local f = openLocal(CFG_NAME, "w")
        if not f then
            error(string.format("无法写入 %s（相对与绝对路径都失败）", CFG_NAME))
        end
        f:write(json.encode({
            steps        = state.steps,
            count        = state.count,
            playerFollow = state.playerFollow,
        }))
        f:close()
    end)
    if not ok then
        state.saveFail = (state.saveFail or 0) + 1
        if state.saveFail <= 3 then dbg("配置写入失败: " .. tostring(err)) end
    elseif state.saveFail then
        local n = state.saveFail
        state.saveFail = nil
        dbg("配置写入恢复正常（此前连续失败 " .. tostring(n) .. " 次）")
    end
end

-- 生效档位：截到 count、去重（相邻重复只留第一个）
local function activeSteps()
    local out, last = {}, nil
    for i = 1, math.min(state.count, MAX_STEPS) do
        local v = state.steps[i]
        if type(v) == "number" and v >= STEP_MIN and v <= STEP_MAX then
            if not last or math.abs(v - last) > 0.001 then
                out[#out + 1] = v
                last = v
            end
        end
    end
    if #out == 0 then out[1] = 1.0 end
    return out
end

------------------------------------------------------------------
-- 引擎接口（全部 pcall 保护；主菜单阶段调原生接口会崩进程）
------------------------------------------------------------------
local function getTimeSystem()
    local ok, ts = pcall(function() return Game.GetTimeSystem() end)
    if ok and ts then return ts end
    return nil
end

local function playerExists()
    local ok, p = pcall(function() return Game.GetPlayer() end)
    return ok and p ~= nil
end

local function notify(msg)
    pcall(function()
        local t = SimpleScreenMessage.new()
        t.duration  = 1.2
        t.message   = msg
        t.isInstant = true
        t.isShown   = true
        Game.GetBlackboardSystem():Get(GetAllBlackboardDefs().UI_Notifications):SetVariant(
            GetAllBlackboardDefs().UI_Notifications.OnscreenMessage, ToVariant(t), true)
    end)
    dbg("notify: " .. tostring(msg))
end

local function applyScale()
    if state.scale == 1.0 and not state.modified then return true end
    if not playerExists() then return false end

    local ts = getTimeSystem()
    if not ts then return false end

    if state.scale == 1.0 then
        pcall(function() ts:UnsetTimeDilation(REASON) end)
        if state.modified then
            pcall(function() ts:SetIgnoreTimeDilationOnLocalPlayerZero(false) end)
            state.modified = false
        end
        return true
    end

    pcall(function() ts:SetIgnoreTimeDilationOnLocalPlayerZero(not state.playerFollow) end)
    state.modified = true
    pcall(function() ts:SetTimeDilation(REASON, state.scale) end)
    return true
end

------------------------------------------------------------------
-- 操作
------------------------------------------------------------------
local function cycleScale()
    dbg("热键命中: cycle")
    local list = activeSteps()

    local idx
    for i, v in ipairs(list) do
        if math.abs(v - state.scale) < 0.001 then idx = i; break end
    end
    if idx then
        idx = (idx % #list) + 1
    else
        idx = #list
        for i, v in ipairs(list) do
            if v > state.scale + 0.001 then idx = i; break end
        end
    end

    state.scale = list[idx]
    applyScale()
    notify(string.format("游戏速度 %.1f× · %d/%d%s",
        state.scale, idx, #list, state.playerFollow and "" or " · 仅世界"))
end

local function resetScale()
    dbg("热键命中: reset")
    state.scale = 1.0
    applyScale()
    notify("游戏速度 1.0×（原速）")
end

local function togglePlayer()
    dbg("热键命中: player")
    state.playerFollow = not state.playerFollow
    state.dirty = true
    applyScale()
    notify(state.playerFollow and "玩家同步加速：开" or "玩家同步加速：关（只有世界变）")
end

------------------------------------------------------------------
-- 设置界面
------------------------------------------------------------------
local function registerSettings()
    if state.settingsDone then return end
    local ok, err = pcall(function()
        local ns = GetMod("nativeSettings")
        if not ns then error("nativeSettings 未加载") end

        if not ns.pathExists("/gamespeed") then
            ns.addTab("/gamespeed", "游戏变速")
        end

        ns.addSubcategory("/gamespeed/main", "倍率与手感")
        ns.addRangeFloat("/gamespeed/main", "游戏速度倍率",
            "1.0 = 原速。1.5–2.0 适合赶过场动画（配音不会跟着变快，超过 2.0 容易口型对不上）；3.0 以上适合纯跑图。",
            1.0, 5.0, 0.1, "%.1f", state.scale, 1.0,
            function(value)
                state.scale = value
                applyScale()
                notify(string.format("游戏速度 %.1f×", state.scale))
            end)
        ns.addSwitch("/gamespeed/main", "玩家同步加速",
            "开：V 的跑动、开车也跟着变快（日常赶路用）。关：只有世界变快，V 保持原速（拍照、纯看动画用）。",
            state.playerFollow, true,
            function(value)
                state.playerFollow = value
                state.dirty = true
                applyScale()
            end)

        -- 不依赖热键的触发通道：热键失效时这两颗按钮照样能用
        ns.addButton("/gamespeed/main", "切到下一档",
            "和 F6 完全等效。F6 没反应时用这个。",
            "下一档", 40, function() cycleScale() end)
        ns.addButton("/gamespeed/main", "回到原速",
            "和 F7 完全等效。",
            "1.0×", 40, function() resetScale() end)

        ns.addSubcategory("/gamespeed/cycle", "F6 循环档位")
        state.opts.count = ns.addRangeInt("/gamespeed/cycle", "循环档位数",
            "F6 只在这几个档位里依次切换。设为 3 就只用档位 1–3，档位 4、5 不参与。",
            1, MAX_STEPS, 1, state.count, MAX_STEPS,
            function(value)
                local v = clampNum(value, 1, MAX_STEPS)
                if v then
                    state.count = math.floor(v + 0.5)
                    state.dirty = true
                end
            end)

        for i = 1, MAX_STEPS do
            local slot = i
            state.opts.steps[i] = ns.addRangeFloat("/gamespeed/cycle",
                string.format("档位 %d", i),
                (i == 1) and "F6 的起点档位。填 1.0 就是从原速开始循环；想要慢放可以设成 0.5。" or "",
                STEP_MIN, STEP_MAX, 0.1, "%.1f", state.steps[i], DEFAULT_STEPS[i],
                function(value)
                    local v = clampNum(value, STEP_MIN, STEP_MAX)
                    if not v then return end
                    v = round1(v)
                    local old = state.steps[slot]
                    state.steps[slot] = v
                    state.dirty = true
                    -- 当前速度正好等于这个档位时，跟着一起变；否则改档位不会立刻有反应，容易被当成失效
                    if old and math.abs(state.scale - old) < 0.001 then
                        state.scale = v
                        applyScale()
                        -- 拖滑条是连续事件，限流到约 1.2 秒一次，否则屏幕提示刷屏
                        if (state.ticks - (state.lastStepTip or -9999)) > 72 then
                            state.lastStepTip = state.ticks
                            notify(string.format("档位 %d → %.1f×", slot, v))
                        end
                    end
                end)
        end

        ns.addButton("/gamespeed/cycle", "恢复默认档位",
            "把档位 1–5 恢复成 1.0 / 1.5 / 2.0 / 3.0 / 5.0，循环档位数也回到 5。",
            "恢复默认", 45,
            function()
                for i = 1, MAX_STEPS do
                    state.steps[i] = DEFAULT_STEPS[i]
                    local opt = state.opts.steps[i]
                    if opt then pcall(function() ns.setOption(opt, DEFAULT_STEPS[i]) end) end
                end
                state.count = MAX_STEPS
                if state.opts.count then
                    pcall(function() ns.setOption(state.opts.count, MAX_STEPS) end)
                end
                state.dirty = true
                saveConfig()
                notify("循环档位已恢复默认")
            end)
    end)
    if ok then
        state.settingsDone = true
        dbg("nativeSettings 页面已注册")
    else
        dbg("nativeSettings 注册失败（稍后重试）: " .. tostring(err))
    end
end

------------------------------------------------------------------
-- 热键：必须在脚本顶层注册（放进 onInit 里会拿到 nil）
------------------------------------------------------------------
local function registerHotkeys()
    if type(registerHotkey) ~= "function" then
        dbg("registerHotkey 不可用，跳过热键（控制台与设置页仍可用）")
        return
    end
    local ok, err = pcall(function()
        registerHotkey("gspeed_cycle",  "游戏变速：按循环档位切换", cycleScale)
        registerHotkey("gspeed_reset",  "游戏变速：恢复 1.0 原速", resetScale)
        registerHotkey("gspeed_player", "游戏变速：玩家是否同步加速", togglePlayer)
    end)
    dbg("热键注册 " .. (ok and "成功" or ("失败: " .. tostring(err))))
end

loadConfig()
registerHotkeys()

------------------------------------------------------------------
-- 生命周期
------------------------------------------------------------------
registerForEvent("onInit", function()
    dbg("=== onInit 开始 ===")
    registerSettings()
    dbg("=== onInit 结束 ===")
end)

registerForEvent("onUpdate", function(dt)
    state.ticks = state.ticks + 1

    if not state.settingsDone and state.ticks % 30 == 0 then
        state.settingsTries = (state.settingsTries or 0) + 1
        if state.settingsTries <= 20 then registerSettings() end
    end

    if state.dirty and state.ticks % SAVE_EVERY_TICKS == 0 then
        state.dirty = false
        saveConfig()
    end

    -- 1.0 且从未改过引擎 → 一个原生调用都不做（主菜单阶段碰 TimeSystem 会崩游戏）
    if state.scale == 1.0 and not state.modified then return end

    state.timer = state.timer + (tonumber(dt) or 0.0)
    if state.timer < REAPPLY_GAP then return end
    state.timer = 0.0
    applyScale()
end)

registerForEvent("onShutdown", function()
    state.scale = 1.0
    state.modified = false
    if state.dirty then saveConfig() end
    dbg("shutdown")
end)

------------------------------------------------------------------
-- 控制台入口
------------------------------------------------------------------
function SetScale(v)
    v = clampNum(v, STEP_MIN, STEP_MAX)
    if not v then return end
    state.scale = round1(v)
    applyScale()
    notify(string.format("游戏速度 %.1f×", state.scale))
end

function Reset() resetScale() end

function SetPlayerFollow(v)
    state.playerFollow = (v == true)
    state.dirty = true
    applyScale()
end

return {
    SetScale        = SetScale,
    Reset           = Reset,
    SetPlayerFollow = SetPlayerFollow,
    GetScale        = function() return state.scale end,
    GetSteps        = function() return activeSteps() end,
}
