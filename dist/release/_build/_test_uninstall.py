# -*- coding: utf-8 -*-
"""隔离测试 _uninstall.ps1 的各条分支，不动真实游戏目录。"""
import os, shutil, subprocess, sys, tempfile

BASE = os.path.join(tempfile.gettempdir(), 'pbzdn_uninstall_test')
SRC = os.path.join(os.path.dirname(os.path.abspath(__file__)), '_uninstall.ps1')

def make_game(root, with_ue4ss=True, with_dll=True, with_mod=True, other_mod=True, backups=1):
    steam = os.path.join(root, 'platform', 'steam')
    os.makedirs(steam, exist_ok=True)
    open(os.path.join(steam, 'PBZ.exe'), 'wb').write(b'MZ')
    if with_dll:
        open(os.path.join(steam, 'dwmapi.dll'), 'wb').write(b'MZ')
    if with_ue4ss:
        u = os.path.join(steam, 'ue4ss')
        os.makedirs(os.path.join(u, 'Mods'), exist_ok=True)
        open(os.path.join(u, 'UE4SS.dll'), 'wb').write(b'MZ')
        open(os.path.join(u, 'UE4SS.log'), 'wb').write(b'log')
        if other_mod:
            om = os.path.join(u, 'Mods', 'SomeOtherMod')
            os.makedirs(om, exist_ok=True)
            open(os.path.join(om, 'main.lua'), 'w').write('-- other')
        if with_mod:
            m = os.path.join(u, 'Mods', 'PBZ_DamageNumbers_Custom')
            os.makedirs(os.path.join(m, 'Scripts'), exist_ok=True)
            open(os.path.join(m, 'Scripts', 'main.lua'), 'w').write('-- pbzdn')
            open(os.path.join(m, 'enabled.txt'), 'w').write('1')
    for i in range(backups):
        b = os.path.join(steam, '_backup_20260101_00000%d' % i)
        os.makedirs(b, exist_ok=True)
        open(os.path.join(b, 'UE4SS.dll'), 'wb').write(b'OLD')
    return root

def make_pack(kind):
    """kind: 'mod' or 'full'，返回包根目录"""
    d = os.path.join(BASE, 'pack_' + kind)
    if os.path.isdir(d):
        shutil.rmtree(d)
    os.makedirs(d)
    # 塞一个测试版脚本（Find-PBZ 被替换成读环境变量）
    txt = open(SRC, 'r', encoding='utf-8-sig', newline='').read()
    stub = ("function Find-PBZ { if ($env:PBZDN_TEST_GAME) { return $env:PBZDN_TEST_GAME } ; return $null }\r\n"
            "\r\n$game = Find-PBZ\r\n")
    assert '\r\n$game = Find-PBZ\r\n' in txt
    txt = txt.replace('\r\n$game = Find-PBZ\r\n', '\r\n' + stub, 1)
    open(os.path.join(d, '_uninstall.ps1'), 'w', encoding='utf-8-sig', newline='').write(txt)
    if kind == 'mod':
        os.makedirs(os.path.join(d, 'PBZ_DamageNumbers_Custom', 'Scripts'))
        open(os.path.join(d, 'PBZ_DamageNumbers_Custom', 'Scripts', 'main.lua'), 'w').write('-- x')
    else:
        os.makedirs(os.path.join(d, 'platform', 'steam', 'ue4ss'))
        open(os.path.join(d, 'platform', 'steam', 'dwmapi.dll'), 'wb').write(b'MZ')
    return d

def run(pack, game, choice=None, confirm=None, label=''):
    env = dict(os.environ)
    env['PBZDN_TEST'] = '1'
    env['PBZDN_TEST_GAME'] = game
    env.pop('PBZDN_TEST_CHOICE', None)
    env.pop('PBZDN_TEST_CONFIRM', None)
    if choice is not None:
        env['PBZDN_TEST_CHOICE'] = choice
    if confirm is not None:
        env['PBZDN_TEST_CONFIRM'] = confirm
    ps = os.path.join(pack, '_uninstall.ps1')
    p = subprocess.run(['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ps],
                       capture_output=True, env=env)
    out = p.stdout.decode('utf-8', 'replace')
    err = p.stderr.decode('utf-8', 'replace')
    return p.returncode, out, err

def state(game):
    steam = os.path.join(game, 'platform', 'steam')
    return {
        'mod': os.path.isdir(os.path.join(steam, 'ue4ss', 'Mods', 'PBZ_DamageNumbers_Custom')),
        'other': os.path.isdir(os.path.join(steam, 'ue4ss', 'Mods', 'SomeOtherMod')),
        'ue4ss': os.path.exists(os.path.join(steam, 'ue4ss', 'UE4SS.dll')),
        'dll': os.path.exists(os.path.join(steam, 'dwmapi.dll')),
        'backups': len([x for x in os.listdir(steam) if x.startswith('_backup_')]) if os.path.isdir(steam) else 0,
    }

def case(name, kind, setup_kw, choice, confirm, expect):
    game = make_game(os.path.join(BASE, 'game_' + name), **setup_kw)
    pack = make_pack(kind)
    rc, out, err = run(pack, game, choice, confirm, name)
    st = state(game)
    ok = all(st[k] == v for k, v in expect.items())
    print('=' * 66)
    print('[%s] %s  pack=%s choice=%r confirm=%r rc=%d' % ('PASS' if ok else 'FAIL', name, kind, choice, confirm, rc))
    print('   期望:', expect)
    print('   实际:', st)
    if not ok:
        print('---- stdout ----')
        print(out)
        if err:
            print('---- stderr ----')
            print(err)
    return ok, out

if os.path.isdir(BASE):
    shutil.rmtree(BASE)
os.makedirs(BASE)

results = []
# A 组：单独 MOD 包
results.append(case('A1_mod_choice1', 'mod', dict(), '1', None,
                    {'mod': False, 'ue4ss': True, 'other': True, 'dll': True}))
results.append(case('A2_mod_choice2', 'mod', dict(), '2', 'yes',
                    {'mod': True, 'ue4ss': True, 'other': True, 'dll': True}))
results.append(case('A3_mod_cancel', 'mod', dict(), None, None,
                    {'mod': True, 'ue4ss': True, 'other': True, 'dll': True}))
results.append(case('A4_mod_nomod', 'mod', dict(with_mod=False), '1', None,
                    {'mod': False, 'ue4ss': True, 'other': True}))
# B 组：完整包
results.append(case('B1_full_choice1', 'full', dict(backups=1), '1', None,
                    {'mod': False, 'ue4ss': True, 'other': True, 'dll': True, 'backups': 1}))
results.append(case('B2_full_choice2_no', 'full', dict(backups=1), '2', 'no',
                    {'mod': True, 'ue4ss': True, 'dll': True, 'backups': 1}))
results.append(case('B3_full_choice2_yes', 'full', dict(backups=2), '2', 'yes',
                    {'mod': False, 'ue4ss': False, 'other': False, 'dll': False, 'backups': 0}))
results.append(case('B4_full_empty', 'full', dict(with_ue4ss=False, with_dll=False, with_mod=False, backups=0), '1', None,
                    {'mod': False, 'ue4ss': False, 'dll': False, 'backups': 0}))
results.append(case('B5_full_choice1_backup_keep', 'full', dict(backups=2), '1', None,
                    {'mod': False, 'ue4ss': True, 'backups': 2}))

print('=' * 66)
print('通过 %d / %d' % (sum(1 for r in results if r[0]), len(results)))

# 额外：打印 mod 包选 2 时的实际提示，确认用户看得懂
print('\n########## mod 包选 2 的实际输出 ##########')
print(results[1][1])
print('\n########## mod 包成功卸载的输出 ##########')
print(results[0][1])
