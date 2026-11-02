# 我的游戏模组

自己写的游戏 mod，一个仓库统一管理。每个 mod 一个目录，互不干扰。

## 目录

| 游戏 | Mod | 版本 | 状态 |
|---|---|---|---|
| 影之刃零（Phantom Blade Zero） | [伤害飘字自定义](PBZ_DamageNumbers_Custom/) | v0.7.2 | 可用，实机验证通过 |
| 赛博朋克 2077（Cyberpunk 2077） | [游戏变速](CP77_GameSpeedControl/) | v1.1.0 | 可用，实机验证通过 |

## 结构约定

```
<游戏或mod名>/
├── README.md          ← 这个 mod 的详细说明（功能、配置、踩坑记录）
├── Scripts/           ← 源码，进发布包
├── manifest.json      ← UE4SS 元数据，进发布包
├── enabled.txt        ← UE4SS 启用标记，进发布包
├── _test/             ← 离线回归测试，不进发布包
├── backup/            ← 定版快照，不进发布包
└── reference/         ← 逆向笔记与他人代码，不进发布包

dist/release/_build/   ← 安装/卸载脚本 + 打包脚本 + UE4SS 素材
```

发布包的内容由 `make_release.py` 里的 `PAYLOAD` 白名单决定，**只打 `Scripts/` 和三个元数据文件**，测试/备份/参考目录不会被误打进去。

上面的骨架以 UE4SS 类 mod 为模板。**`manifest.json` 的字段跟着 mod 框架走**：

| | UE4SS（影之刃零） | CET（赛博朋克 2077） |
| --- | --- | --- |
| 启用方式 | `enabled.txt` + `mods.txt` | 目录名自动加载，无启用标记 |
| 安装位置 | `platform/steam/ue4ss/Mods/<名字>/` | `bin/x64/plugins/cyber_engine_tweaks/mods/<名字>/` |
| 路径映射 | 无需，`Scripts/` 即目录结构 | 写进 `install.map`，因为路径太深 |
| 配置/日志 | 走 `UE4SS.log` | 各自 mod 目录下的 `config.json` / `debug.log` |

共同点是 **源码只有一份，不设 payload 副本** —— 一旦有两份，就会出现"打包源和工程源不同步"（这个坑 PBZ 那个 mod 已经踩过）。

## 当前项目常用操作

下面以 PBZ 为例。赛博朋克那个 mod 的部署与测试命令写在
[它自己的 README](CP77_GameSpeedControl/README.md) 里（CET 的安装路径和启用方式都不同，不混在一起写）。

### 部署到游戏

```bash
cp PBZ_DamageNumbers_Custom/Scripts/*.lua \
   /c/app/Steam/steamapps/common/PBZ/platform/steam/ue4ss/Mods/PBZ_DamageNumbers_Custom/Scripts/
```

改完记得核对 md5，两边一致才算部署成功。

### 跑离线测试

需要 `pip install lupa`。改完 Lua 先跑这个，别直接进游戏试错。

```bash
cd PBZ_DamageNumbers_Custom/_test
python test_rowhide.py       # 逐行隐藏逻辑
python test_hidelabels.py    # 去掉标签字逻辑
```

### 重新打发布包

```bash
cd dist/release/_build
python make_release.py
```

版本号从 `Scripts/config.lua` 首行的 `配置 vX.Y.Z` 自动读，不用手改。

如果 `pack_full/` 里缺 `UE4SS.dll` 或 `dwmapi.dll`（换机器或清过目录时会缺），从游戏目录补：

```bash
cp /c/app/Steam/steamapps/common/PBZ/platform/steam/dwmapi.dll            dist/release/_build/pack_full/platform/steam/
cp -r /c/app/Steam/steamapps/common/PBZ/platform/steam/ue4ss/.            dist/release/_build/pack_full/platform/steam/ue4ss/
```

## 说明

- 本仓库是个人自用存档，不考虑分发体验
- UE4SS 为 MIT License（Copyright © 2022 Narknon），随包分发时保留其 LICENSE
- `reference/` 下若含第三方代码，均已在 `.gitignore` 中排除，不随仓库分发
