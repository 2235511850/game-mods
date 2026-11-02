PBZ 自定义伤害飘字 v0.5.0
==========================

《影之刃零》UE4SS Lua 模组。运行时直接修改游戏自带的伤害飘字数据资产，
不替换 pak、不改贴图、不碰界面控件。

功能
----
- 飘字存活 1.0 秒 -> 1.8 秒（打快攻时读得过来）
- 连续飘字行距 20 -> 34（原版行距比字高还小，数字会叠在一起）
- 最小间距、垂直抖动微调，数字散得更开
- 敌人飘字缩放 1.0 -> 0.9
- 治疗（回血）数字由纯白改为亮绿，和掉血一眼分开

全部数值都能在 Scripts/config.lua 里改，留 nil 就是不改。

前置
----
必须已安装 UE4SS（dwmapi.dll + ue4ss/ 放在 PBZ/platform/steam/，
和 511MB 的 PBZ.exe 并列）。

安装
----
把整个 PBZ_DamageNumbers_Custom 文件夹放进
  PBZ/platform/steam/ue4ss/Mods/
确认 Mods/mods.txt 里有  PBZ_DamageNumbers_Custom : 1

卸载
----
删掉该文件夹即可，游戏完全恢复原样。
临时停用：把文件夹改名成 PBZ_DamageNumbers_Custom_off。

排错
----
日志：PBZ/platform/steam/ue4ss/UE4SS.log
搜索 [PBZDN]，正常应有：
  loaded v0.5.0
  layout applied = 7
  healColor ... (write=ok, refetch=0.35,1.00,0.45)
  apply done

如果游戏闪退：把 Mods/PBZ_DamageNumbers_Custom 改名加 _off 后缀即可恢复。

已验证环境
----------
UE4SS v3.0.1 Beta / UE 5.7.4 / 游戏 build 26266538
