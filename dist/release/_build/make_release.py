# -*- coding: utf-8 -*-
"""重建两个发布包：refresh pack 目录 -> 打 zip。
用法: python make_release.py
"""
import os, re, shutil, zipfile, hashlib, sys

HERE = os.path.dirname(os.path.abspath(__file__))
REL = os.path.dirname(HERE)                     # dist/release
DIST = os.path.dirname(REL)                     # dist
ROOT = os.path.dirname(DIST)                    # 工程根（WORKSPACE）
MOD_SRC = os.path.join(ROOT, 'PBZ_DamageNumbers_Custom')

# payload 白名单：只有这些会进发布包。
# 工程目录里还有 _test / backup / reference，绝不能跟着打进去。
PAYLOAD = [
    ('Scripts', 'dir'),
    ('enabled.txt', 'file'),
    ('manifest.json', 'file'),
    ('README.txt', 'file'),
]


def detect_version():
    """版本号从工程源 config.lua 首部注释里读，不再手写。

    以前这里是硬编码 'v0.5.0'，工程升到 v0.7.2 之后忘了改，
    结果打出来的包名还是 v0.5.0，跟内容对不上。
    """
    cfg = os.path.join(MOD_SRC, 'Scripts', 'config.lua')
    with open(cfg, encoding='utf-8') as f:
        for line in f:
            m = re.search(r'配置\s*(v\d+\.\d+\.\d+)', line)
            if m:
                return m.group(1)
    raise SystemExit('无法从 %s 读出形如「配置 v1.2.3」的版本号' % cfg)


VER = detect_version()

ZIP_MOD = os.path.join(REL, '影之刃零 伤害飘字MOD %s（单独MOD）.zip' % VER)
ZIP_FULL = os.path.join(REL, '影之刃零 伤害飘字MOD %s（含UE4SS前置）.zip' % VER)
TOP_MOD = '影之刃零 伤害飘字MOD %s（单独MOD）' % VER
TOP_FULL = '影之刃零 伤害飘字MOD %s（含UE4SS前置）' % VER

SCRIPTS = ['_install.ps1', '_uninstall.ps1', '一键安装.bat', '一键卸载.bat']


def gbk(src_utf8, dst):
    s = open(src_utf8, 'r', encoding='utf-8').read()
    s = s.replace('\r\n', '\n').replace('\n', '\r\n')
    with open(dst, 'w', encoding='gbk', newline='') as f:
        f.write(s)


def copy_payload(dst):
    """按白名单从工程目录重建 payload，不再依赖 stage_adapter 那份副本。

    以前 stage_adapter 是工程 Scripts 的手工副本，两边经常不同步，
    导致打出来的包是旧代码。现在只有一处源。
    """
    if os.path.isdir(dst):
        shutil.rmtree(dst)
    os.makedirs(dst)
    for name, kind in PAYLOAD:
        src = os.path.join(MOD_SRC, name)
        if not os.path.exists(src):
            raise SystemExit('payload 缺少必需项: %s' % src)
        if kind == 'dir':
            shutil.copytree(src, os.path.join(dst, name))
        else:
            shutil.copy2(src, os.path.join(dst, name))


def refresh_common(pack_dir, doc_src):
    for f in SCRIPTS:
        shutil.copy2(os.path.join(HERE, f), os.path.join(pack_dir, f))
    shutil.copy2(os.path.join(HERE, doc_src), os.path.join(pack_dir, '安装说明.txt'))


def refresh_pack_mod():
    d = os.path.join(HERE, 'pack_mod')
    copy_payload(os.path.join(d, 'PBZ_DamageNumbers_Custom'))
    refresh_common(d, 'doc_mod.txt')


def refresh_pack_full():
    d = os.path.join(HERE, 'pack_full')
    refresh_common(d, 'doc_full.txt')
    copy_payload(os.path.join(d, 'platform', 'steam', 'ue4ss', 'Mods', 'PBZ_DamageNumbers_Custom'))


def make_zip(src_dir, top_name, out):
    if os.path.exists(out):
        os.remove(out)
    n = 0
    with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for root, dirs, files in os.walk(src_dir):
            dirs.sort()
            rel = os.path.relpath(root, src_dir)
            arc_root = top_name if rel == '.' else os.path.join(top_name, rel).replace('\\', '/')
            z.writestr(zipfile.ZipInfo(arc_root + '/'), b'')
            for f in sorted(files):
                full = os.path.join(root, f)
                z.write(full, arc_root + '/' + f)
                n += 1
    return n, os.path.getsize(out)


def md5(p):
    h = hashlib.md5()
    with open(p, 'rb') as f:
        for b in iter(lambda: f.read(1 << 20), b''):
            h.update(b)
    return h.hexdigest()


if __name__ == '__main__':
    gbk(os.path.join(HERE, 'doc_mod.utf8.txt'), os.path.join(HERE, 'doc_mod.txt'))
    refresh_pack_mod()
    refresh_pack_full()

    nm, sm = make_zip(os.path.join(HERE, 'pack_mod'), TOP_MOD, ZIP_MOD)
    nf, sf = make_zip(os.path.join(HERE, 'pack_full'), TOP_FULL, ZIP_FULL)

    print('单独 MOD 包 : %2d 个文件  %.1f KB  md5=%s' % (nm, sm / 1024, md5(ZIP_MOD)))
    print('完整   包   : %2d 个文件  %.1f MB  md5=%s' % (nf, sf / 1048576, md5(ZIP_FULL)))
