# CET bindings.json 编码规则

查自 CET 源码 `src/VKBindings.cpp`（`EncodeVKCodeBind` / `DecodeVKCodeBind`）。
写在这里是因为：**猜这个编码浪费过一整晚**，日志里没有任何提示，写错只是静默无效。

## 编码

绑定值是一个 uint64，里面塞最多 4 个 16 位 VK 码，**从最高位往低位填**。
单键就是 `VK << 48`，组合键按顺序占前几格。

```python
def enc(*vks):
    arr = list(vks) + [0] * (4 - len(vks))
    v = 0
    for k in arr:
        v = (v << 16) | k
    return v

def dec(v):
    return [(v >> s) & 0xFFFF for s in (48, 32, 16, 0)]
```

| 热键 | VK | 正确值 | 错误写法 |
| --- | --- | --- | --- |
| F6 | 0x75 | 32932572275146752 | `117`（那是 VK 本身） |
| F7 | 0x76 | 33214047251857408 | `118` |
| F8 | 0x77 | 33495522228568064 | `119` |

自检办法：CET 自带的 `overlay_key` 是 `4785280762511360` = `0x0011003000000000`，
解出来是 `[0x11, 0x30, 0, 0]` = Ctrl + 0。能对上就说明解码方向没搞反。

## RemoveDeadBindings

CET 启动时会清理**没有被成功注册**的绑定，整条记录置成 `null`。

所以「条目凭空消失」的第一嫌疑是 **mod 里的 `registerHotkey` 没执行成功**，
不是"值写错了被拒"。注册修好之后，同样的值就会保留 —— 这个因果关系很容易搞反，
因为现象看起来完全一样。

## 最容易搞错的一点

`registerHotkey` **必须写在脚本顶层**，不能放进 `onInit` 回调。
CET 只在脚本加载那几毫秒注入这批 API，回调执行时全局已经撤掉了，
取到 nil 后 `onInit` 会静默中断 —— 热键没注册上，设置页也不会建。

对照参考：`mods/custom_fast_travel_pins`、`mods/CrashWatch` 都是顶层调用。
