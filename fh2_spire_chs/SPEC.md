# Spire 简体中文补丁技术参考

目标版本为 Xbox One `Spire 1.0.0.6`。通用的简繁转换规则、资源格式、ZIP 末尾追加算法及安装恢复流程见 [fh2_chs/SPEC.md](../fh2_chs/SPEC.md)，本文只记录 Spire 专属信息。

## 补丁范围

补丁共处理 35 个游戏文件：3 个完整替换文件和 32 个末尾追加文件。完整目标路径、校验值及追加文件长度以 `resources/files.json` 为准。

| 游戏资源 | 安装方式 | 内容 |
|---|---|---|
| `Mount/media/stripped/stringtables/CHT.zip` | 完整替换 | 128 个 `.str`，10,963 条字符串，6,959 条发生转换 |
| `Mount/media/ui/Fonts.zip` | 完整替换 | 修改 `DFYuanMedium-B5.vfont` 的中文字符字形 |
| `Mount/media/zipmanifest.xml` | 完整替换 | 更新受影响 ZIP 的目录信息 |
| `Mount/media/Cinematics.zip`、`Mount/media/cars/*.zip` | 末尾追加 | 64 个字幕 XML，涉及电影包和 30 个车辆包 |
| `Mount/media/ui/textures/Localized.zip` | 末尾追加 | `CHT/Legal_Disclaimer.swatchbin` 法律声明纹理 |

Spire 独立安装，完整替换文件的备份目录为 `FH2_SPIRE_CHS_Backup`。

## 字体补充

字符串和字幕共需 1,647 个汉字，统一使用微软雅黑 Regular。其中 1,639 个字形复用本体补丁，`乱亭兑喂桌氮络袭` 8 个字形用同一字体补充生成，尺度与本体一致。保留其他原始字形。

## 法律声明纹理

纹理规格与本体相同，Spire 的中文重绘区域为：

```text
x 632..1552, y 308..344
x 740..1180, y 344..380
x 420..1500, y 520..592
```

区域按 4 像素块对齐，英文版权行及区域外的原始 BC7 块保留。
