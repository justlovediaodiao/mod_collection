# 《光环 5：守护者》Xbox One 版简体中文补丁

本补丁把游戏的繁体中文（CHT）文本转换为简体中文，并替换中文字体包以补齐简体字形。安装后，游戏语言仍应设置为繁体中文。

## 安装

1. 关闭游戏及正在使用游戏文件的程序。
2. 打开 PowerShell 7，进入补丁目录。
3. 执行：

   ```powershell
   pwsh -ExecutionPolicy Bypass -File .\Install.ps1 "游戏目录"
   ```

`游戏目录` 填包含 `Mount` 文件夹的游戏根目录。脚本会在游戏根目录创建 `_CHT2CHS_backup` 保存原始数据。文本为原地等长替换，字体文件整体替换。

## 恢复原版

关闭游戏及正在使用游戏文件的程序，然后执行：

```powershell
pwsh -ExecutionPolicy Bypass -File .\Install.ps1 "游戏目录" -Restore
```

## 注意事项

- 只适用于 Xbox One 版 Halo 5: Guardians（`1.1.31695.21`）。
- 安装前会先校验文件状态，不匹配时不会修改任何文件；中断后可以重新运行。

## 文件结构

```text
Install.ps1              安装与恢复脚本
README.md                本文档
manifest.json            文本块与字体校验清单
data.bin                 文本替换数据
font_package_cht.bin     替换用字体包
font_package_cht_4k.bin  替换用 4K 字体包
```
