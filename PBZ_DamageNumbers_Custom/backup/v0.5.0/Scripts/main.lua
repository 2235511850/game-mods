-- ============================================================
-- PBZ 自定义伤害飘字 v0.5.0
-- 目标环境：UE4SS v3.0.1 Beta (PBZ 定制版) / UE 5.7.4
--
-- 【v0.3.0 闪退原因】
--   两次运行日志都停在完全同一行：
--     CFG ContainerWidgetClass : SoftClassProperty = TSoftObjectPtrUserdata: ...
--   下一个字段 DamageNumberWidgetClass 同样是 SoftClassProperty。
--   对 TSoftObjectPtr 这类裸 userdata 做反射读取会触发原生层访问违例，
--   pcall 拦不住（那不是 Lua 错误，是访问违例）。
--   所以 v0.4.0 彻底放弃「遍历类 + 读全部字段值」这件事。
--
-- 【v0.4.0 策略】
--   1. 不 ForEachProperty 遍历类；不读任何 Object / SoftClass / SoftObject / Array 属性值
--   2. 只对已实测是 FloatProperty 的字段做读写（白名单，见 config.layout）
--   3. 颜色走 Vercadi 已验证过的数组遍历写法（rows:ForEach + param:get()），可单独关掉
--   4. 每步独立 pcall + 写后读回校验，崩了也能从日志最后一行精确定位
-- ============================================================

local Config = require("config")

local TAG = "[PBZDN]"
local function log(msg) print(TAG .. " " .. tostring(msg) .. "\n") end
local function vlog(msg) if Config.verbose then log(msg) end end

local ASSET_FULL  = "/PBZCombatAsset/UI/DamageNumber/DA_DamageNumberConfig.DA_DamageNumberConfig"
local ASSET_SHORT = "/PBZCombatAsset/UI/DamageNumber/DA_DamageNumberConfig"

-- ---------- 基础工具 ----------

local function valid(obj)
    if obj == nil then return false end
    local ok, ans = pcall(function() return obj:IsValid() end)
    return ok and ans == true
end

local function tryFind(path)
    local ok, obj = pcall(StaticFindObject, path)
    if ok and valid(obj) then return obj end
    return nil
end

-- ---------- UEHelpers / 控制台 ----------

local helpersOk, UEHelpers = pcall(require, "UEHelpers")

local function getPC()
    if not helpersOk or type(UEHelpers.GetPlayerController) ~= "function" then return nil end
    local ok, pc = pcall(UEHelpers.GetPlayerController)
    if ok and valid(pc) then return pc end
    return nil
end

local execFn, libObj, execTried, execReady = nil, nil, false, false

local function setupExec()
    if execTried then return execReady end
    execTried = true
    execFn = tryFind("/Script/Engine.KismetSystemLibrary:ExecuteConsoleCommand")
    libObj = tryFind("/Script/Engine.Default__KismetSystemLibrary")
    execReady = (execFn ~= nil and libObj ~= nil)
    log("exec api | fn=" .. tostring(execFn ~= nil) .. " lib=" .. tostring(libObj ~= nil))
    return execReady
end

local function enableNumbers()
    if not Config.enableNativeNumbers then return end
    if not setupExec() then return end
    local pc = getPC()
    if not pc then return end
    pcall(function() execFn(libObj, pc, Config.consoleCommand, pc) end)
end

-- ---------- 资产 ----------

local asset = nil

local function resolveAsset()
    if valid(asset) then return asset end
    local obj = tryFind(ASSET_FULL)
    if valid(obj) then asset = obj; return asset end
    obj = tryFind(ASSET_SHORT)
    if valid(obj) then asset = obj; log("asset | short path OK"); return asset end
    local ok, found = pcall(FindFirstOf, "PBZDamageNumberConfig")
    if ok and valid(found) then
        asset = found
        log("asset | FindFirstOf OK -> " .. tostring(found:GetFullName()))
        return asset
    end
    return nil
end

-- ---------- 数值读写（只碰 FloatProperty 白名单） ----------

local function readNum(a, name)
    local ok, v = pcall(function() return a:GetPropertyValue(name) end)
    if ok and type(v) == "number" then return v end
    return nil
end

local function close(a, b)
    if a == nil or b == nil then return false end
    local d = math.abs(a - b)
    return d <= 0.002 or d <= math.abs(b) * 0.002
end

local function writeNum(a, name, val)
    local before = readNum(a, name)
    pcall(function() a:SetPropertyValue(name, val) end)
    local after = readNum(a, name)
    if close(after, val) then return true, before, after end
    pcall(function() a[name] = val end)
    after = readNum(a, name)
    return close(after, val), before, after
end

local function applyLayout(a)
    local n, fails = 0, {}
    for name, val in pairs(Config.layout) do
        if val ~= nil then
            local ok, before, after = writeNum(a, name, val)
            if ok then
                n = n + 1
                log(string.format("layout %-18s %s -> %s", name, tostring(before), tostring(after)))
            else
                fails[#fails + 1] = name
                log(string.format("layout FAILED %-14s before=%s after=%s target=%s",
                    name, tostring(before), tostring(after), tostring(val)))
            end
        end
    end
    log("layout applied = " .. n .. (#fails > 0 and ("  failed=" .. table.concat(fails, ",")) or ""))
end

-- ---------- 字体（可选，默认不动） ----------

local function applyFont(a)
    local key, size = Config.style.fontStruct, Config.style.fontSize
    if key == nil or size == nil then return end
    local ok = pcall(function()
        local f = a:GetPropertyValue(key)
        if f ~= nil then f.Size = size end
    end)
    log("font " .. tostring(key) .. ".Size -> " .. tostring(size) .. (ok and " ok" or " FAILED"))
end

-- ---------- 颜色 ----------

local function tagOf(row)
    local ok, s = pcall(function()
        local t = row.DamageTag
        if t == nil then return nil end
        local n = t.TagName
        if type(n) == "string" then return n end
        if n ~= nil then return n:ToString() end
        return nil
    end)
    if ok and type(s) == "string" then return s end
    return nil
end

local function colorFor(tag)
    if tag == nil then return nil end
    local tbl = Config.style.colorByTag
    if tbl == nil then return nil end
    local tail = tag:match("([%w_]+)$")
    local stripped = tag:gsub("^Damage%.Damage%.", "")
    return tbl[tag] or tbl[stripped] or (tail and tbl[tail]) or nil
end

local function colorTarget(col)
    if col == nil then return nil end
    local okR, r = pcall(function() return col.R end)
    if okR and type(r) == "number" then return col end
    local okS, sc = pcall(function() return col.SpecifiedColor end)
    if okS and sc ~= nil then
        local okR2, r2 = pcall(function() return sc.R end)
        if okR2 and type(r2) == "number" then return sc end
    end
    return nil
end

-- 直接对一个颜色结构体写入（也用于 HealColor 这种资产级字段）
local function writeColorStruct(col, c)
    local target = colorTarget(col)
    if target == nil then return false end
    target.R = c[1]
    target.G = c[2]
    target.B = c[3]
    if c[4] ~= nil then target.A = c[4] end
    local okV, back = pcall(function() return target.R end)
    return okV and type(back) == "number" and math.abs(back - c[1]) < 0.02
end

local function writeColorField(row, propName, c)
    local ok, col = pcall(function() return row[propName] end)
    if not ok or col == nil then return false end
    return writeColorStruct(col, c)
end

-- 只读取颜色当前值（不做任何写入）
local function readColorStruct(col)
    local target = colorTarget(col)
    if target == nil then return nil end
    local _, r = pcall(function() return target.R end)
    local _, g = pcall(function() return target.G end)
    local _, b = pcall(function() return target.B end)
    local _, a2 = pcall(function() return target.A end)
    if type(r) ~= "number" then return nil end
    return {
        r,
        (type(g) == "number") and g or 1,
        (type(b) == "number") and b or 1,
        (type(a2) == "number") and a2 or 1,
    }
end

local function readColorField(row, propName)
    local ok, col = pcall(function() return row[propName] end)
    if not ok or col == nil then return nil end
    return readColorStruct(col)
end

-- 只读探针：把 34 行的标签、tag、当前颜色全部打印出来（不修改任何东西）
local function probeRows(a)
    log("===== probe rows (只读) =====")
    local okRows, rows = pcall(function() return a:GetPropertyValue("DamageTypeDisplayInfos") end)
    if not okRows or rows == nil then log("probe | rows unavailable") return end
    local okN, count = pcall(function() return rows:GetArrayNum() end)
    log("probe | rows count = " .. tostring(okN and count or "?"))

    local n = 0
    local okAll, err = pcall(function()
        rows:ForEach(function(index, param)
            local idx = tonumber(index) or 0
            local okGet, row = pcall(function() return param:get() end)
            if not okGet or row == nil then return end
            n = n + 1

            local tag = tagOf(row) or "?"
            local label = "?"
            pcall(function()
                local e = row.EmojiIcon
                label = (type(e) == "string") and e or (e and e:ToString()) or "?"
            end)

            local cur = readColorField(row, Config.style.colorPropertyName)
            local rgb = cur and string.format("%.2f,%.2f,%.2f,%.2f", cur[1], cur[2], cur[3], cur[4]) or "?"
            log(string.format("probe row[%02d] %s | %s | rgb=%s", idx, label, tag, rgb))
        end)
    end)
    if not okAll then log("probe | ForEach FAILED: " .. tostring(err)) end
    log("probe | rows dumped = " .. n)
end

local function applyColors(a)
    local okRows, rows = pcall(function() return a:GetPropertyValue("DamageTypeDisplayInfos") end)
    if not okRows or rows == nil then log("colors | rows unavailable") return end

    local okN, count = pcall(function() return rows:GetArrayNum() end)
    log("colors | rows count = " .. tostring(okN and count or "?"))

    local limit = Config.style.colorRowLimit or 0
    if limit > 0 then log("colors | 本轮限制只改前 " .. limit .. " 行（探针模式）") end

    local applied, skipped, unmatched = 0, 0, 0
    local okAll, err = pcall(function()
        rows:ForEach(function(index, param)
            local idx = tonumber(index) or 0
            local okGet, row = pcall(function() return param:get() end)
            if not okGet or row == nil then skipped = skipped + 1; return end

            local tag = tagOf(row)
            local label = "?"
            pcall(function()
                local e = row.EmojiIcon
                label = (type(e) == "string") and e or (e and e:ToString()) or "?"
            end)

            local c = colorFor(tag)
            if c == nil then
                unmatched = unmatched + 1
                vlog(string.format("colors | no rule row[%02d] %s %s", idx, label, tostring(tag)))
                return
            end

            if limit > 0 and idx > limit then
                skipped = skipped + 1
                return
            end

            local cur = readColorField(row, Config.style.colorPropertyName)
            local before = cur and string.format("%.2f,%.2f,%.2f", cur[1], cur[2], cur[3]) or "?"
            log(string.format("colors | row[%02d] %s %s %s -> %.2f,%.2f,%.2f",
                idx, label, tostring(tag), before, c[1], c[2], c[3]))
            local okW, res = pcall(writeColorField, row, Config.style.colorPropertyName, c)
            if okW and res then applied = applied + 1 else skipped = skipped + 1 end
        end)
    end)

    if not okAll then log("colors | ForEach FAILED: " .. tostring(err)) end
    log(string.format("colors applied = %d  skipped = %d  unmatched = %d", applied, skipped, unmatched))
end

-- ---------- 治疗数字颜色（资产级 HealColor，原版纯白） ----------

local function applyHealColor(a)
    if not Config.style.enableHealColor then return end
    local c = Config.style.healColor
    if c == nil then return end

    local okGet, col = pcall(function() return a:GetPropertyValue("HealColor") end)
    if not okGet or col == nil then log("healColor | struct unavailable") return end

    local before = readColorStruct(col)
    local beforeTxt = before and string.format("%.2f,%.2f,%.2f", before[1], before[2], before[3]) or "?"
    local ok, res = pcall(writeColorStruct, col, c)

    -- 关键校验：重新向资产要一次 HealColor，而不是读刚才那个句柄。
    -- 如果 GetPropertyValue 返回的是值拷贝，句柄内的读回会成功但资产没变，
    -- 只有重新取一次才能确认真的写进了资产内存。
    local refetched = nil
    local okRe, col2 = pcall(function() return a:GetPropertyValue("HealColor") end)
    if okRe and col2 ~= nil then
        local after = readColorStruct(col2)
        if after then refetched = string.format("%.2f,%.2f,%.2f", after[1], after[2], after[3]) end
    end

    log(string.format("healColor %s -> %.2f,%.2f,%.2f (write=%s, refetch=%s)",
        beforeTxt, c[1], c[2], c[3], (ok and res) and "ok" or "FAILED", tostring(refetched)))
end

-- ---------- 一次性应用 ----------

local applied = false

local function applyAll()
    local a = resolveAsset()
    if a == nil then return false end
    if applied then return true end

    log("===== apply begin =====")
    pcall(applyLayout, a)
    pcall(applyFont, a)
    if Config.probeRows then pcall(probeRows, a) end
    pcall(applyHealColor, a)
    if Config.style.enableColor then
        pcall(applyColors, a)
    else
        log("colors | disabled (style.enableColor = false)")
    end
    applied = true
    log("===== apply done =====")
    return true
end

-- ---------- 调度：ExecuteWithDelay 递归，每步在游戏线程内执行 ----------

local armed, pending, halted = false, false, false

local function tick()
    local ok, err = pcall(function()
        enableNumbers()
        applyAll()
    end)
    if not ok then vlog("tick ERROR: " .. tostring(err)) end
end

local schedule
schedule = function(delay)
    if halted or armed or pending then return end
    armed = true
    local ok = pcall(ExecuteWithDelay, delay, function()
        armed = false
        if halted or pending then return end
        pending = true
        local queued = pcall(ExecuteInGameThread, function()
            tick()
            pending = false
            schedule(applied and Config.checkIntervalMs or Config.retryIntervalMs)
        end)
        if not queued then
            pending, halted = false, true
            log("REFUSED | game-thread queue failed, module halted")
        end
    end)
    if not ok then
        armed, halted = false, true
        log("REFUSED | scheduling failed, module halted")
    end
end

log(string.format("loaded v0.5.0 | delay=%s color=%s", tostring(Config.startupDelayMs), tostring(Config.style.enableColor)))
schedule(Config.startupDelayMs or 4000)
