# 我的游戏模组

自己写的游戏 mod，一个仓库统一管理。每个 mod 一个目录，互不干扰。

## 目录

| 游戏 | Mod | 版本 | 状态 |
|---|---|---|---|
| 影之刃零（Phantom Blade Zero） | [伤害飘字自定义](PBZ_DamageNumbers_Custom/) | v0.7.2 | 可用，实机验证通过 |

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

## 当前项目常用操作

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
