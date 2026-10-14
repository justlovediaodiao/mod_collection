# 《极限竞速：地平线 2》Xbox One 版简体中文补丁

本补丁把游戏的繁体中文（CHT）资源转换为简体中文。安装后，游戏语言仍应设置为繁体中文。

## 安装

1. 关闭游戏及正在使用游戏文件的程序。
2. 打开 PowerShell 7，进入补丁目录。
3. 执行：

   ```powershell
   pwsh -ExecutionPolicy Bypass -File .\Install.ps1 "游戏目录"
   ```

脚本会在游戏目录创建 `FH2_CHS_Backup`，保存三个被完整替换的原始文件。其余资源使用末尾追加方式安装，恢复时按经过校验的原始长度截断。

## 恢复原版

关闭游戏及正在使用游戏文件的程序，然后执行：

```powershell
pwsh -ExecutionPolicy Bypass -File .\Install.ps1 "游戏目录" -Restore
```

## 注意事项

- 只适用于 Xbox One `1.0.0.64` 版本，支持风暴岛DLC。
- 脚本会先校验文件状态，以免覆盖误修改游戏文件。安装中断后可以重新运行脚本，已安装和未安装的文件会分别识别。

## 文件结构

```text
Install.ps1       安装与恢复脚本
README.md             本文档
inspect.md             资源格式、处理方式和 DLC 汉化参考
resources\
  files.json            安装目标、长度和完整性校验清单
  payload\              三个完整替换文件
  deltas\               223 个末尾追加资源
```

