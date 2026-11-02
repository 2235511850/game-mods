-- ============================================================
-- PBZ 自定义伤害飘字 - 配置 v0.5.0
--
-- 字段与数值全部来自本机实测日志（UE4SS v3.0.1 / build 26266538）：
--
-- PBZDamageNumberConfig 关键字段（原版值）：
--   EnemyFontScale       1.0     敌人（你打出去的）飘字缩放
--   PlayerFontScale      0.7     自己受到的飘字缩放
--   ShootDuration        0.15    射出运动耗时
--   TotalLifetime        1.0     总存活时间
--   FadeOutDuration      0.1     淡出耗时
--   InitialScale         1.0     初始缩放
--   RectHalfWidth        150     飘字活动范围
--   RectHalfHeight       400
--   XBaseOffset          60      起始偏移
--   YBaseOffset          10
--   YStepSize            20      连续飘字垂直步长  <-- 比字高 24 还小，所以会重叠
--   RandomJitterX/Y      15 / 10
--   MinPadding           5
--   DamageFont.Size      24
--   HealColor            (1,1,1,1)
-- ============================================================

return {
    -- ---------- 基础开关 ----------
    enableNativeNumbers = true,
    consoleCommand = "pbz.DamageNumber.Enabled 1",

    startupDelayMs = 4000,      -- 启动后多久开始第一次尝试
    retryIntervalMs = 3000,     -- 资产还没加载出来时的重试间隔
    checkIntervalMs = 5000,     -- 已应用后的巡检间隔（只补发控制台开关）

    verbose = true,             -- true = 连未匹配的伤害类型也打日志

    -- 只读探针：把 34 行的「标签 / tag / 当前颜色」全部打印进日志，不做任何修改
    -- 用来先拿到游戏原版配色，再决定要不要改、改成什么
    -- 原版配色已经拿全，日常可以改 false 让日志干净点
    probeRows = false,

    -- ---------- 样式 ----------
    style = {
        -- 治疗数字颜色（资产级 HealColor，原版是纯白 1,1,1）
        -- 回血数字没有类型标签、也不在 34 行里，走的是独立通道，所以只能整条统一换色
        enableHealColor = true,
        healColor = { 0.35, 1.00, 0.45, 1.00 },   -- 亮绿
        -- 按伤害类型配色。
        -- 第一次先留 false：只验证「不再闪退 + 布局改善」，确认稳了再改 true。
        -- 结构体字段写入这条路还没在本机跑通过，所以单独隔离成一个开关。
        enableColor = false,

        -- 本轮最多只改前 N 行（0 = 不限制）。先用 3 行试水，确认能写再放全量。
        colorRowLimit = 3,

        -- 颜色字段名：已在日志中确认为 DisplayInfo 结构体的 Color 成员
        colorPropertyName = "Color",

        -- 字体结构体名 + 字号。默认不碰（nil = 不改）
        fontStruct = nil,          -- 可填 "DamageFont" / "HealFont"
        fontSize   = nil,          -- 例如 22

        -- key 支持三种写法，按顺序匹配：完整 tag -> 去掉 Damage.Damage. 前缀 -> 末段
        -- value = {R, G, B}（0~1），可加第 4 位 Alpha
        colorByTag = {
            -- 主伤害类型
            Physical    = { 0.95, 0.95, 0.95 },  -- 物 白
            Fire        = { 1.00, 0.55, 0.20 },  -- 火 橙
            Ice         = { 0.55, 0.85, 1.00 },  -- 冰 青蓝
            Lightning   = { 1.00, 0.95, 0.45 },  -- 雷 亮黄
            Toxin       = { 0.65, 1.00, 0.45 },  -- 毒 黄绿
            Aqua        = { 0.40, 0.75, 1.00 },  -- 水 蓝
            Blood       = { 0.95, 0.20, 0.20 },  -- 血 深红
            Chaos       = { 0.80, 0.55, 1.00 },  -- 混 紫

            -- 其它伤害类
            TrueDamage  = { 1.00, 1.00, 1.00 },  -- 真 纯白
            PoiseDamage = { 1.00, 0.88, 0.60 },  -- 韧 米黄

            -- 异常状态累积（比主色暗一档）
            IgniteAccumulation  = { 0.85, 0.45, 0.18 },  -- 燃
            BleedAccumulation   = { 0.80, 0.18, 0.18 },  -- 裂
            PoisonAccumulation  = { 0.55, 0.85, 0.38 },  -- 腐
            FrostAccumulation   = { 0.45, 0.70, 0.90 },  -- 冻
            WaterAccumulation   = { 0.35, 0.62, 0.90 },  -- 湿
            ThunderAccumulation = { 0.85, 0.80, 0.40 },  -- 电
            ElectrifiedAccumulation = { 0.80, 0.75, 0.35 }, -- 麻
            BloodBurstAccumulation  = { 0.90, 0.30, 0.30 }, -- 爆

            -- 杀气类（AngerDamage.*）
            Normal      = { 0.70, 0.70, 0.70 },  -- 气
            Suffocation = { 0.50, 0.60, 0.75 },  -- 溺
        },
    },

    -- ---------- 布局（nil = 不改） ----------
    -- 只填已实测是 FloatProperty 的字段，绝不碰 Object / SoftClass / Array
    layout = {
        -- 时长：原版 1.0 秒里还要扣掉射出 0.15 + 淡出 0.1，实际可见只有 0.75 秒
        TotalLifetime   = 1.8,
        FadeOutDuration = 0.15,
        ShootDuration   = 0.12,

        -- 堆叠：原版步长 20 < 字高 24，必然重叠。抬到 34 就能一行一个
        YStepSize       = 34.0,
        RandomJitterY   = 12.0,
        MinPadding      = 8.0,

        -- 字号：原版敌人 1.0
        EnemyFontScale  = 0.9,
    },
}
