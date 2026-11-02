PBZ 自定义伤害飘字 v0.7.2
==========================

《影之刃零》UE4SS Lua 模组。运行时直接修改游戏自带的伤害飘字数据资产，
不替换 pak、不改贴图、不碰界面控件。

效果
----
屏幕上原本一次命中会弹「物251 韧100 气2」三个数字，现在只留「物251」——
而且前面那个「物」字也去掉了，就是一串干净的数字。

具体做了四件事：
1. 只保留 10 类真正掉血的飘字（物/火/冰/雷/毒/水/血/混/真/刹），
   另外 24 类（韧、气、溺、沌、各种异常累积、自身资源回复）全部隐藏
2. 去掉飘字前面的汉字标签，只留数字
3. 治疗（回血）数字由纯白改为亮绿，和掉血一眼分开
4. 排版优化：存活 1.0s -> 1.8s，行距 20 -> 34（原版行距比字高还小，
   数字会叠在一起），敌人飘字缩放 1.0 -> 0.9

需要说明的代价：只削盾不掉血的那一段，屏幕上不会有任何飘字。
这是隐藏「韧」的必然结果。想要回来，见下面「改回原版」。

全部数值都能在 Scripts/config.lua 里改。

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

改回原版
--------
用记事本打开 Scripts/config.lua：

  只想要回「韧/气」等飘字  -> 把 style.hideTags 里的内容全删掉，留 hideTags = {}
  只想要回「物 火 冰」这些字 -> 把 style.hideLabels = true 改成 false
  全部恢复出厂设置          -> 直接删掉整个 mod 文件夹

排错
----
日志：PBZ/platform/steam/ue4ss/UE4SS.log
搜索 [PBZDN]，正常应有：
  loaded v0.7.2
  layout applied = 7
  rowOverride | applied=24 failed=0 errors=0
  hideLabels  | applied=34 failed=0
  apply done

如果游戏闪退：把 Mods/PBZ_DamageNumbers_Custom 改名加 _off 后缀即可恢复。

已验证环境
----------
UE4SS v3.0.1 Beta / UE 5.7.4 / 游戏 build 26266538
