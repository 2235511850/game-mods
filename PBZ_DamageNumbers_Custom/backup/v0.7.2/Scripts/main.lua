-- ============================================================
-- PBZ 自定义伤害飘字 v0.7.2
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
--
-- 【v0.6.0 新增 / v0.7.0 定版：逐行隐藏，只留掉血数字】
--   目的：只保留"掉血"的数字，把 韧/气/累积/回/精 藏掉。
--   但 DamageTypeDisplayInfo 只有 5 个字段，没有任何 bool 开关，
--   所以只能把目标行 Color 的 Alpha 写成 0（保留原 RGB，失败也不毁画面）。
--   applyRowOverrides 负责这件事，并做一次「重新取数组再读回」的校验：
--   句柄内读回成功但资产没变的情况，只有重新取一次才能发现。
--   同一段代码还支持把某行改成指定颜色，用来做洋红探针验证写入通路。
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

-- ---------- 只读诊断：并发飘字槽位上限 ----------

-- 被隐藏的行并不会真的消失，它照样被创建、照样占一个并发槽位。
-- MaxActiveNumbers 决定同时最多存在几条，值太小的话 21 条里 14 条隐形，
-- 会把真正要看的伤害数字提前顶掉。这里只读不改，先拿到原值再决定要不要动。
local function reportCaps(a)
    local ok, v = pcall(function() return a:GetPropertyValue("MaxActiveNumbers") end)
    log("caps | MaxActiveNumbers = " .. tostring(ok and v or "?"))
end

-- ---------- 临时诊断：EmojiIcon（FText）能不能改 ----------
--
-- 目的只有一个：判断「去掉物/火/冰那些标签字」这条路技术上是否可行。
-- 判断完把 Config.probeEmoji 改 false（或整段删掉）即可。
--
-- 第一轮（只读）已经拿到的结论：
--   34 行全部 type=userdata、ToString 正常、能读出中文
--   FindFirstOf(KismetTextLibrary) 拿得到实例
--   但 lib:Conv_StringToText("") 抛错，当时只打了类型没打错误原文
--
-- 第二轮补四件事：
--   1. 打印错误原文，判断是"FText 返回值不支持"还是"签名不对"
--   2. 枚举 FText wrapper 的元表 / 方法，看有没有现成的构造入口
--   3. 换调用形式重试（点调用带 self、CDO 路径、Conv_IntToText 作对照）
--   4. 写入探测：自赋值 -> 跨行互赋 -> 空串 -> SetPropertyValue
--
-- 写入只在内存里，重启游戏自动还原。FText 内部是 TSharedRef，
-- 赋值有小概率触发原生崩溃，真崩了说明这条路不通，把 probeEmojiWrite 改 false 即可。
local function probeEmoji(a)
    if not Config.probeEmoji then return end
    log("===== emoji probe v3 (只读) =====")

    local okRows, rows = pcall(function() return a:GetPropertyValue("DamageTypeDisplayInfos") end)
    if not okRows or rows == nil then log("emoji3 | rows unavailable") return end

    local f1
    pcall(function()
        rows:ForEach(function(index, param)
            pcall(function()
                if tonumber(index) ~= 1 then return end
                local row = param:get()
                if row == nil then return end
                local okF, v = pcall(function() return row["EmojiIcon"] end)
                if okF then f1 = v end
            end)
        end)
    end)

    if f1 == nil then log("emoji3 | row01 EmojiIcon 读不到") return end

    local okT, s1 = pcall(function() return f1:ToString() end)
    log(string.format("emoji3 | row01 type=%s ToString=%s str=\"%s\"",
        type(f1), tostring(okT), tostring(okT and s1 or "?")))

    -- FindFirstOf 那个实例内部指针是 nullptr（实测报 nullptr），只有 CDO 能用
    local okL, lib = pcall(StaticFindObject, "/Script/Engine.Default__KismetTextLibrary")
    log(string.format("emoji3 | CDO KismetTextLibrary ok=%s got=%s",
        tostring(okL), tostring(okL and lib ~= nil)))

    if okL and lib ~= nil then
        local okE, t = pcall(function() return lib:Conv_StringToText("") end)
        if okE and t ~= nil then
            local okS, s = pcall(function() return t:ToString() end)
            log(string.format("emoji3 | 空FText 构造 ok=true 回读=\"%s\" 长度=%s",
                tostring(okS and s or "?"),
                tostring(okS and type(s) == "string" and #s or "?")))
        else
            log("emoji3 | 空FText 构造失败: " .. tostring(t))
        end
    end

    log("===== emoji probe v3 done =====")
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

-- ---------- 逐行处理：隐藏（Alpha=0）/ 颜色探针 ----------

-- 匹配规则：完整 tag -> 去掉 Damage.Damage. 前缀 -> 以 * 开头的键做后缀匹配
local function matchRule(tbl, tag)
    if tag == nil or tbl == nil then return nil end
    local hit = tbl[tag]
    if hit ~= nil then return hit end
    local stripped = tag:gsub("^Damage%.Damage%.", "")
    hit = tbl[stripped]
    if hit ~= nil then return hit end
    for k, v in pairs(tbl) do
        if type(k) == "string" and k:sub(1, 1) == "*" then
            local suf = k:sub(2)
            if #suf > 0 and #stripped >= #suf and stripped:sub(-#suf) == suf then
                return v
            end
        end
    end
    return nil
end

local function rowLabel(row)
    local label = "?"
    pcall(function()
        local e = row.EmojiIcon
        label = (type(e) == "string") and e or (e and e:ToString()) or "?"
    end)
    return label
end

-- 打印颜色。必须容忍缺分量：config 里手写的颜色常常只有 3 位，
-- 老版本直接取 c[4] 会在第一行日志处抛错，把整个 ForEach 中断掉。
local function fmtColor(c)
    if c == nil then return "?" end
    local function f(v)
        if type(v) == "number" then return string.format("%.2f", v) end
        return "-"
    end
    return f(c[1]) .. "," .. f(c[2]) .. "," .. f(c[3]) .. "," .. f(c[4])
end

local function applyRowOverrides(a)
    local hideTbl = Config.style.hideTags or {}
    local ovTbl   = Config.style.rowOverrides or {}
    if next(hideTbl) == nil and next(ovTbl) == nil then
        log("rowOverride | disabled (hideTags / rowOverrides 都为空)")
        return
    end

    local okRows, rows = pcall(function() return a:GetPropertyValue("DamageTypeDisplayInfos") end)
    if not okRows or rows == nil then log("rowOverride | rows unavailable") return end

    local propName = Config.style.colorPropertyName or "Color"
    local alpha    = Config.style.hideAlpha or 0.0
    local targets  = {}     -- idx -> { mode, label }
    local applied, failed, errors = 0, 0, 0

    local okAll, err = pcall(function()
        rows:ForEach(function(index, param)
            -- 单行隔离：任何一行的读写或日志出错，都必须只影响这一行，
            -- 绝不能像旧版那样抛到外层把剩余行全部丢掉。
            local okRow, rowErr = pcall(function()
                local idx = tonumber(index) or 0
                local okGet, row = pcall(function() return param:get() end)
                if not okGet or row == nil then return end
                local tag = tagOf(row)
                if tag == nil then return end

                local ov  = matchRule(ovTbl, tag)
                local hit = ov ~= nil or matchRule(hideTbl, tag) ~= nil
                if not hit then return end

                local before = readColorField(row, propName)

                local c, mode
                if ov ~= nil then
                    -- 探针：缺的分量从原值补，避免手写 3 位色意外把 Alpha 抹成 1
                    c = {
                        ov[1],
                        ov[2],
                        ov[3],
                        (ov[4] ~= nil) and ov[4] or ((before and before[4]) or 1),
                    }
                    mode = "probe"
                else
                    -- 隐藏：原 RGB 一字不动，只改 Alpha。
                    -- 这样万一游戏忽略 Alpha，画面跟现在完全一样，不会变成黑字。
                    c = {
                        (before and before[1]) or 1,
                        (before and before[2]) or 1,
                        (before and before[3]) or 1,
                        alpha,
                    }
                    mode = "hide"
                end

                local label = rowLabel(row)
                targets[idx] = { mode = mode, label = label }

                local okW, res = pcall(writeColorField, row, propName, c)
                if okW and res then applied = applied + 1 else failed = failed + 1 end
                log(string.format("rowOverride | %s row[%02d] %s %s  %s -> %s  write=%s",
                    mode, idx, label, tostring(tag), fmtColor(before), fmtColor(c),
                    (okW and res) and "ok" or "FAILED"))
            end)
            if not okRow then
                errors = errors + 1
                if errors <= 3 then log("rowOverride | row error: " .. tostring(rowErr)) end
            end
        end)
    end)
    if not okAll then log("rowOverride | ForEach FAILED: " .. tostring(err)) end

    -- 复读校验：重新向资产要一次数组。
    -- 句柄内读回成功、但资产其实没变的情况，只有重新取一次才能发现。
    -- 这里把 R 和 A 分开报：R 变了说明写入通路是通的，
    -- A 没变则说明这个通道压根写不进去（而非被渲染忽略），两者处置完全不同。
    local okV = pcall(function()
        local rows2 = a:GetPropertyValue("DamageTypeDisplayInfos")
        if rows2 == nil then log("rowOverride | verify skipped") return end
        local n = 0
        rows2:ForEach(function(index, param)
            local okRow = pcall(function()
                local idx = tonumber(index) or 0
                local t = targets[idx]
                if t == nil then return end
                local okGet, row = pcall(function() return param:get() end)
                if not okGet or row == nil then return end
                n = n + 1
                local now = readColorField(row, propName)
                local aNow = now and now[4]
                local verdict = "?"
                if aNow ~= nil then
                    if t.mode == "hide" then
                        verdict = (aNow <= 0.01) and "A已归零" or "A未变"
                    else
                        verdict = "probe"
                    end
                end
                log(string.format("rowOverride | verify row[%02d] %s %s now=%s | %s",
                    idx, t.label, t.mode, fmtColor(now), verdict))
            end)
        end)
        log("rowOverride | verified " .. n .. " row(s)")
    end)
    if not okV then log("rowOverride | verify FAILED") end

    log(string.format("rowOverride | applied=%d failed=%d errors=%d hideAlpha=%.2f",
        applied, failed, errors, alpha))
end

-- ---------- 去掉标签字（EmojiIcon -> 空 FText） ----------
--
-- 实机实测结论（v0.7.1+probe2，14:56 那轮）：
--
--   1. FindFirstOf("KismetTextLibrary") 拿回来的是个空壳，内部 UObject 指针是 nullptr。
--      调用它任何方法都会报 “Tried calling a member function but the UObject instance
--      is nullptr”。上一轮 Conv_StringToText 全部失败就是这个原因，跟参数无关。
--
--   2. 改走 StaticFindObject("/Script/Engine.Default__KismetTextLibrary") 拿 CDO，
--      Conv_StringToText("") 立刻成功，返回合法 FText。这是唯一能造 FText 的入口。
--
--   3. row["EmojiIcon"] = <另一个 FText>  —— 成功。属性本身完全可写，
--      行内结构体成员的 FText 赋值不会崩。
--
--   4. row["EmojiIcon"] = ""  —— 原生崩溃，直接把游戏带走。
--      Lua 字符串不会被自动转成 FText，UE4SS 在这里解引用空指针。
--      【绝对不要】再对 FText 属性直接赋 Lua 字符串。
--
-- 所以安全路径只有一条：CDO 造空 FText，再赋值给各行。

local function getTextLib()
    -- 只认 CDO。FindFirstOf 那条路实测是 nullptr 空壳，不要去碰。
    local ok, o = pcall(StaticFindObject, "/Script/Engine.Default__KismetTextLibrary")
    if ok and o ~= nil then return o end
    return nil
end

local function makeEmptyText(lib)
    local ok, t = pcall(function() return lib:Conv_StringToText("") end)
    if not ok or t == nil then return nil end
    -- 必须回读确认真是空串，不能只看调用没报错
    local ok2, s = pcall(function() return t:ToString() end)
    if not ok2 or s ~= "" then return nil end
    return t
end

local function applyHideLabels(a)
    if not Config.style.hideLabels then return end
    log("hideLabels | begin")

    local lib = getTextLib()
    if lib == nil then
        log("hideLabels | KismetTextLibrary CDO 拿不到，跳过")
        return
    end

    -- 只构造一次，34 行共用。值是拷贝语义（FText 内部 TSharedRef 加引用计数），安全。
    local empty = makeEmptyText(lib)
    if empty == nil then
        log("hideLabels | 空 FText 构造失败，跳过")
        return
    end
    log("hideLabels | 空 FText 已就绪")

    local okRows, rows = pcall(function() return a:GetPropertyValue("DamageTypeDisplayInfos") end)
    if not okRows or rows == nil then log("hideLabels | rows unavailable") return end

    local done, failed, firstErr = 0, 0, nil
    local okAll = pcall(function()
        rows:ForEach(function(index, param)
            local okOne, err = pcall(function()
                local row = param:get()
                if row == nil then return end
                row["EmojiIcon"] = empty
                done = done + 1
            end)
            if not okOne then
                failed = failed + 1
                if firstErr == nil then firstErr = tostring(err) end
            end
        end)
    end)

    log(string.format("hideLabels | applied=%d failed=%d", done, failed))
    if firstErr ~= nil then log("hideLabels | 首个错误: " .. firstErr) end
    if not okAll then log("hideLabels | ForEach 中断") end

    -- 复读校验：重新向资产要一次数组，只有这里读到的才是证据
    local okV = pcall(function()
        local rows2 = a:GetPropertyValue("DamageTypeDisplayInfos")
        if rows2 == nil then log("hideLabels | verify skipped") return end
        local n, emptyCount = 0, 0
        rows2:ForEach(function(index, param)
            pcall(function()
                local row = param:get()
                if row == nil then return end
                local okG, v = pcall(function() return row["EmojiIcon"] end)
                if not okG or v == nil then return end
                n = n + 1
                local okS, s = pcall(function() return v:ToString() end)
                if okS and s == "" then emptyCount = emptyCount + 1 end
            end)
        end)
        log(string.format("hideLabels | verify 共 %d 行，其中已清空 %d 行", n, emptyCount))
    end)
    if not okV then log("hideLabels | verify FAILED") end
end

-- ---------- 一次性应用 ----------

local applied = false

local function applyAll()
    local a = resolveAsset()
    if a == nil then return false end
    if applied then return true end

    log("===== apply begin =====")
    pcall(applyLayout, a)
    pcall(reportCaps, a)
    pcall(applyFont, a)
    if Config.probeRows then pcall(probeRows, a) end
    pcall(applyHealColor, a)
    pcall(applyRowOverrides, a)
    -- 去标签字放在逐行隐藏之后：两者互不干扰，先让颜色定下来再动文本
    pcall(applyHideLabels, a)
    if Config.style.enableColor then
        pcall(applyColors, a)
    else
        log("colors | disabled (style.enableColor = false)")
    end
    -- 放最后：前面的实际改动都完成后再探，万一它出问题也不影响已经生效的部分
    pcall(probeEmoji, a)
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

log(string.format("loaded v0.7.2 | delay=%s color=%s hide=%s",
    tostring(Config.startupDelayMs), tostring(Config.style.enableColor),
    tostring(Config.style.hideAlpha)))
schedule(Config.startupDelayMs or 4000)
