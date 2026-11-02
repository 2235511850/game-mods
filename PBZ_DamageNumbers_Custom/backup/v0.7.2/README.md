# PBZ 自定义伤害飘字（v0.7.2）

《影之刃零》UE4SS Lua 模组。不注入贴图、不改 pak、不碰界面控件，  
运行时直接改游戏自带的 `DA_DamageNumberConfig` 数据资产。

**已在实机验证**：UE4SS v3.0.1 Beta / UE 5.7.4 / build 26266538。

---

## 它做什么

| 项目     | 原版    | 本模组       | 说明                              |
| ------ | ----- | --------- | ------------------------------- |
| 飘字存活   | 1.0 秒 | **1.8 秒** | 扣掉射出 0.12 + 淡出 0.15，实际可见约 1.5 秒 |
| 连续飘字行距 | 20    | **34**    | 原版行距比字高（24）还小，必然重叠；现在一行一个       |
| 最小间距   | 5     | **8**     |                                 |
| 垂直抖动   | 10    | **12**    | 分散得更开                           |
| 敌人飘字缩放 | 1.0   | **0.9**   |                                 |
| 治疗数字颜色 | 纯白    | **亮绿**    | 原版白字和「物」的灰字几乎分不清                |
| 飘字类型   | 34 类  | **只留 10 类** | 只显示真正掉血的数字，气/韧/累积等 24 类隐藏        |
| 标签字    | 有（物/火/冰） | **去掉** | 只留纯数字串，属性靠颜色区分，画面更干净      |

治疗数字的颜色是重点：游戏的回血数字**不带类型标签**，也不在那 34 行伤害类型里，  
走的是资产级 `HealColor` 独立通道。改成绿色后，回血和掉血一眼就能分开。  
**实机已确认变绿生效。**

---

## 安装

1. 装 UE4SS（`dwmapi.dll` + `ue4ss/` 放到 `PBZ/platform/steam/`，和 511MB 的 PBZ.exe 并列）
2. 把整个 `PBZ_DamageNumbers_Custom/` 放进 `platform/steam/ue4ss/Mods/`
3. 确认 `Mods/mods.txt` 里有 `PBZ_DamageNumbers_Custom : 1`（有些版本靠 `enabled.txt` 自动识别）
4. 启动游戏，进存档打怪

日志在 `platform/steam/ue4ss/UE4SS.log`，搜索 `[PBZDN]`：  
出现 `loaded v0.5.0` 和 `apply done` 就是跑起来了。

**卸载**：删掉 `Mods/PBZ_DamageNumbers_Custom/` 即可，游戏完全恢复原样。  
临时停用：把文件夹改名成 `PBZ_DamageNumbers_Custom_off`。

---

## 配置（`Scripts/config.lua`）

```lua
layout = {
    TotalLifetime   = 1.8,    -- 总存活秒数
    FadeOutDuration = 0.15,   -- 淡出耗时
    ShootDuration   = 0.12,   -- 射出运动耗时
    YStepSize       = 34.0,   -- 行距（治重叠的关键）
    RandomJitterY   = 12.0,
    MinPadding      = 8.0,
    EnemyFontScale  = 0.9,    -- 字号缩放
}
```

留 `nil` 就是不改。所有字段都经过实测确认是 `FloatProperty`。

想调但不知道原值？把 `probeRows = true` 打开，日志会把 34 行的  
标签、内部 tag、当前 RGB 全打出来。

### 只留掉血数字（`style.hideTags`）

那 34 行伤害类型里，只有 10 行是真正扣血的。其余 24 行（韧、气、溺、沌、
各种异常累积、自身资源回复）都不掉血，只是视觉噪音。

结构体 `DamageTypeDisplayInfo` 只有 5 个字段，**没有一个是开关**，所以
「这一行不显示」在配置层面并不存在。本模组的做法是把这些行 `Color` 的
**Alpha 写成 0**，RGB 一位不动 —— 万一哪天游戏忽略 Alpha，画面会保持原样，
不会变成一团黑字。

想改回原版，把 `hideTags` 清空即可：

```lua
style = {
    hideTags = {},   -- 全部 34 行都显示
}
```

想留个几乎看不见的淡影（确认自己打到了，又不吵），把 `hideAlpha` 改成 `0.06`。

**代价**：只削盾不掉血的那一段，屏幕上不会有任何飘字。这是隐藏「韧」的必然结果。

### 去掉标签字（`style.hideLabels`）

飘字前面的那个汉字（物/火/冰/雷…）存在 `EmojiIcon` 字段里，类型是 `FText`，
和 `Color` 那种纯数字结构体完全不是一回事。改它的正确姿势只有一种：

**用 CDO 造一个空 FText，再赋值。**

```lua
local lib = StaticFindObject("/Script/Engine.Default__KismetTextLibrary")
local empty = lib:Conv_StringToText("")   -- 合法的空 FText
row["EmojiIcon"] = empty
```

这里有两个非常容易踩的坑，都是实机崩出来的：

**坑一：`FindFirstOf("KismetTextLibrary")` 拿到的是空壳。**
它返回的对象看着不是 nil，但内部 UObject 指针是 `nullptr`，调任何方法都报
`Tried calling a member function but the UObject instance is nullptr`。
必须走 `StaticFindObject` 拿 CDO 那条路。

**坑二：绝对不能直接赋 Lua 字符串。**
`row["EmojiIcon"] = ""` 会**当场闪退**，`pcall` 拦不住（原生访问违例）。
`SetPropertyValue("EmojiIcon", "")` 同样危险。Lua 字符串不会自动转成 FText。

想恢复带字的版本：

```lua
style = {
    hideLabels = false,
}
```

回退不需要重启，不涉及任何文件修改，改完下次启动就是原样。

---

## 走过的弯路（省得你重踩）

**1. 不要遍历类去读字段值。**  
`ForEachProperty` 遍历 `PBZDamageNumberConfig` 时，读到 `ContainerWidgetClass` /  
`DamageNumberWidgetClass` 这类 `SoftClassProperty`，值是一个 `TSoftObjectPtrUserdata` 裸指针，  
对它做反射读取会触发**原生层访问违例**，`pcall` 拦不住，游戏直接闪退。  
本模组的做法是只读写白名单里的 `FloatProperty`，软引用一概不碰。

**2. 不要整体回写结构体。**  
`row.Color = col` / `SetPropertyValue("HealColor", col)` 会破坏内存映射。  
正确做法是只写内部字段（`col.R = ...`），写完读回校验。  
实机验证：这条路是通的。

**3. v3.0.1 的 API 习惯**

- `LoopAsync` 不可靠 → 用递归 `ExecuteWithDelay`
- 数组遍历用 `rows:ForEach(function(i, param) local row = param:get() end)`
- `FName` 要 `:ToString()`
- 反射操作建议包在 `ExecuteInGameThread` 里

---

## 配色：默认不用改

原版 `DamageTypeDisplayInfos` 已经是一套完整的 34 行配色：

| 标签 | RGB            |   | 标签 | RGB            |
| -- | -------------- | - | -- | -------------- |
| 物  | 0.75,0.75,0.75 |   | 韧  | 1.00,0.65,0.00 |
| 火  | 1.00,0.42,0.21 |   | 气  | 1.00,0.27,0.27 |
| 冰  | 0.49,0.78,0.89 |   | 精  | 0.25,0.41,0.88 |
| 雷  | 0.86,0.65,0.12 |   | 回  | 1.00,0.39,0.28 |
| 毒  | 0.31,0.78,0.47 |   | 燃  | 1.00,0.27,0.00 |
| 水  | 0.29,0.56,0.85 |   | 裂  | 0.86,0.08,0.23 |
| 血  | 0.55,0.00,0.00 |   | 腐  | 0.20,0.80,0.20 |
| 混  | 0.61,0.35,0.71 |   | 冻  | 0.68,0.85,0.90 |
| 真  | 1.00,0.84,0.00 |   | 沌  | 0.55,0.00,0.55 |

「物」故意用暗灰、「气」故意用最亮的红——这是设计意图（这游戏七成破防靠主动压制）。  
所以 `enableColor` 默认 `false`，改色能力留着但不启用。

真要改的话注意两个坑：

- `Chaos` 出现在 `GeneralDamage` / `AngerDamage` / `Attacker.AngerDamage` 三处，分别是「混 / 沌 / 混」
- `Normal` 在 `Target` 和 `Attacker` 下各有一条

按 tag 末段匹配会串色，得写完整 tag 或用 `Target.` / `Attacker.` 前缀区分。

---

## 34 行伤害类型速查

| 分组             | 标签                          |
| -------------- | --------------------------- |
| 主伤害（Target）    | 物 火 冰 雷 毒 水 血 混 真 韧 气 溺 沌 刹 |
| 异常累积（Target）   | 麻 电 燃 裂 爆 腐 湿 冻             |
| 自身资源（Attacker） | 气 混 回（杀气回复） 精（精纯杀气获取）       |
| 异常累积（Attacker） | 麻 电 燃 裂 爆 腐 湿 冻             |

「精」这条对攒精纯杀气的打法特别有用——回复速率能直接看到数字。

---

## 已知限制

- 游戏更新后资产路径或字段名可能变；改的是内存资产，不落盘，所以每次启动都会重新应用
- `pbz.DamageNumber.Enabled` 这个 cvar 是总开关，模组每 5 秒补发一次，防止读档后被清掉
- 改的是全局数据资产，所有飘字实例共享，无法只改某一种
- 本模组只改数值和颜色，不替换字体、不改贴图

## 致谢

早期侦查阶段参考了 Nexus 上 Vercadi 的 Floating Combat Numbers（Lua 写法）  
和 Sleepy3812 的 Damage Numbers（pak 内 JS 的字段线索）。  
本模组代码为独立实现，未包含他人成果。
