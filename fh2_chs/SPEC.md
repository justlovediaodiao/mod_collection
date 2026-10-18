# FH2 Xbox One 简体中文补丁技术参考

本文记录补丁的资源范围、格式和生成规则，用于复现当前补丁，并作为后续 DLC 汉化的技术基线。当前目标版本为《极限竞速：地平线 2》Xbox One 版 `1.0.0.64`，资源从游戏已可读取的 `Mount` 目录开始处理；本文不包含 XVD 解密或挂载流程。

## 1. 补丁组成

补丁共处理 226 个游戏文件：3 个完整替换文件和 223 个末尾追加文件。完整目标路径、原始长度、补丁后长度及校验值以 `resources/files.json` 为准。

| 游戏资源 | 安装方式 | 内容 |
|---|---:|---|
| `Mount/media/stripped/stringtables/CHT.zip` | 完整替换 | 126 个 `.str`，13,310 条字符串 |
| `Mount/media/ui/Fonts.zip` | 完整替换 | 修改 `DFYuanMedium-B5.vfont` 的中文字符字形 |
| `Mount/media/zipmanifest.xml` | 完整替换 | 更新受影响 ZIP 的中央目录位置、大小和条目数 |
| `Mount/media/Cinematics.zip` | 末尾追加 | 34 个繁体中文字幕 XML |
| `Mount/media/cars/*.zip` | 末尾追加 | 221 个车辆展示字幕 XML，每包 1 个 |
| `Mount/media/ui/textures/Localized.zip` | 末尾追加 | `CHT/Legal_Disclaimer.swatchbin` 法律声明纹理 |

字幕合计 255 个 XML、1,483 个非空 `<Key>`。法律声明是静态纹理，不是启动视频；游戏视频文件没有修改。

## 2. 简繁转换规则

当前补丁只做逐字符繁体转简体，不重译句子，也不进行术语改写。映射以 OpenCC `TSCharacters.txt` 的每行第一个候选为基础，并固定以下覆盖：

```text
著 -> 着
藉 -> 借
瞭 -> 了
```

原始字典来源：<https://github.com/BYVoid/OpenCC/blob/master/data/dictionary/TSCharacters.txt>


映射必须保持一个 BMP 字符对应一个 BMP 字符。这样 UTF-16 代码单元数量不变，`.str` 中的偏移和长度可以原样保留。如果 DLC 出现代理对字符，或新映射会改变 UTF-16 长度，必须重建字符串池和全部偏移，不能套用当前的原位替换方法。

## 3. 解包与读取

游戏 `Mount/media` 下处理到的 `.zip` 是标准 PKZIP 容器，可用 .NET 的 `System.IO.Compression.ZipArchive` 读取。应在独立工作目录操作，不要直接覆盖原始游戏文件。

普通、无需保留特殊 ZIP 元数据的资源可以这样解包：

```powershell
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::ExtractToDirectory(
    'C:\path\to\CHT.zip',
    'C:\path\to\work\CHT'
)
```

车辆包、电影包和本地化纹理包包含游戏依赖的目录字段，不能用普通“全部解包再重新压缩”方式重建。当前补丁对这些包使用末尾追加算法，保留原文件作为前缀。

## 4. `.str` 字符串表

本作的 `.str` 使用旧式 `LSB2` 格式，全部整数为小端：

| 位置 | 类型 | 含义 |
|---:|---|---|
| `0x00` | 4 字节 | ASCII `LSB2` |
| `0x14` | UInt32 | values 区段起始位置 `s`，当前文件通常为 36 |
| `s+0x00` | UInt32 | values 区段总长度 `L` |
| `s+0x04` | UInt32 | 字符串条目数 `N` |
| `s+0x08` | `N × 6` 字节 | UInt16 标识/哈希 + UInt32 字符串池代码单元偏移 |
| 条目之后 | 6 字节 | `0xFFFF` 和结尾偏移组成的终止记录 |

字符串池起点：

```text
s + 8 + 6 × (N + 1)
```

字符串池终点为 `s + L`。字符串采用以空字符结尾的 UTF-16LE，并包含原有对齐填充。转换时只遍历这个字符串池中的 Unicode 字符，其他字节必须原样保留，包括条目标识、偏移、`0x18/0x1C/0x20` 指向的后续区段以及键名和元数据。

处理后至少验证：魔数、区段边界、所有字符串偏移不越界、每条字符串有终止符、文件长度不变、非字符串池字节不变。

## 5. 字幕 XML

字幕主要位于：

```text
Mount/media/Cinematics.zip
Mount/media/cars/*.zip
```

条目通常以 `*_CHT.xml` 结尾，结构为 UTF-8 XML：

```xml
<SubtitlesTrack>
  <Key time="..." value="..." />
</SubtitlesTrack>
```

以严格 UTF-8 解码，记录并保留原 BOM 状态，只对文本字符应用同一份一对一映射。时间、XML 标记、实体、变量和排版不改。转换后去掉 BOM 副本进行 XML 解析验证，同时检查 `<Key>` 数量、时间值及文件名没有变化。字体所需汉字集合必须从字符串表和全部字幕取并集。

## 6. ZIP 末尾追加算法

`resources/data.bin` 是所有追加数据的拼接文件，每个追加资源占用其中一段连续区段，起点和长度由 `files.json` 的 `DataOffset` 和 `DataLength` 给出。单个区段是只能追加到指定原始文件末尾的字节序列，组成如下：

1. 每个修改条目的新本地文件头、文件名和 raw Deflate 数据。
2. 一份完整的新中央目录，包含原包所有条目。
3. 新 EOCD。

旧 ZIP 的所有字节，包括旧中央目录和旧 EOCD，作为前缀保持不变。新中央目录让修改条目指向追加的新本地文件头；未修改条目的本地头偏移保持原值。ZIP 读取器从文件末尾查找 EOCD，因此会使用新目录。

关键结构位置：

| 结构 | 签名 | 关键字段 |
|---|---|---|
| Local header | `0x04034B50` | flags +6，method +8，CRC +14，压缩大小 +18，原始大小 +22，名称长 +26，extra 长 +28 |
| Central header | `0x02014B50` | flags +8，method +10，CRC +16，大小 +20/+24，名称长 +28，extra 长 +30，comment 长 +32，本地头偏移 +42 |
| EOCD | `0x06054B50` | 条目数 +10，目录大小 +12，目录起点 +16，comment 长 +20 |

当前资源使用 method 8（Deflate）。生成新条目时更新标准 CRC-32（多项式 `0xEDB88320`）、压缩大小、原始大小和偏移。数据描述符标志 bit 3 被清除，因为 CRC 和大小直接写入本地头。

车辆字幕的中央目录 extra 常见为：

```text
23 11 04 00 [UInt32LE address]
```

这是 tag `0x1123`、长度 4，载荷为数据的绝对地址。新条目必须改成：

```text
newLocalOffset + 30 + fileNameLength + localExtraLength
```

当前构建器只接受已验证的布局：无 ZIP64、包小于 4 GiB、原包末尾为无 comment 的 EOCD、本地 extra 为空、中央 extra 为空或只有 `0x1123`。遇到其他字段、加密、数据描述符、ZIP64 或未知压缩法时应停止并先解析格式。

每个追加区段与确切的原始文件绑定。安装前校验原始 SHA-256 和长度，追加后校验完整补丁文件；恢复时只在确认文件为补丁版本后截断至原始长度，再校验原始 SHA-256。不得把一个区段应用到另一版本的同名资源。

## 7. `zipmanifest.xml`

每个被修改 ZIP 的 `<Zip path="game:\media\...">` 节点需要同步更新：

```text
dirstart    新中央目录的绝对文件偏移
dirsize     新中央目录字节数
direntries  中央目录条目数
```

其他属性、优先级、版本和未修改节点保持不变。ZIP 最后一个 EOCD 与清单三项必须一致。DLC 可能有自己的清单和资源优先级；分析 DLC 时应以完整游戏路径判断覆盖关系，不能只比较 ZIP 文件名。

## 8. 字体处理

`Fonts.zip` 中只修改 `DFYuanMedium-B5.vfont`。文件名、字体引用和全局头保留，以继续满足 CHT 字体回退关系。当前补丁从字符串表和字幕收集所需汉字，并使用微软雅黑 Regular 生成 1,800 个汉字字形；其他原始字形保留。原文件有 1,915 条字形记录，补丁后为 2,720 条。这个字体是当前文本所需字符的子集，不保证覆盖未来 DLC。

旧式 `.vfont` 字形网格内嵌，主要结构为：

| 位置/区段 | 内容 |
|---|---|
| `0x00..0xBF` | 192 字节全局头 |
| `0x80` | UInt32 字形数量 |
| `0xB8` | UInt32 kerning 数量 |
| `0xC0` | 每字形 28 字节 metrics，按码点排序 |
| metrics 后 | `12 × kerningCount` 字节不透明 kerning 数据 |
| kerning 后 | UInt32 mesh 数量，随后逐字形 mesh |

每个 metrics 记录中：`+0` 为码点，`+4` 为 float advance，`+8/+12` 为顶点数和索引数。每个 mesh 为 `UInt32 codepoint, UInt32 V, UInt32 I`，随后 `V × 8` 字节顶点和 `I × 2` 字节 UInt16 索引。顶点是四个 half-float；生成字形使用 `(x,y,z,w)`，辅助分量为 `(0,1)`，三角形索引按游戏坐标方向生成。

未来 DLC 必须把基础游戏和所有 DLC 所需字符取并集，只补充缺失字符，并同时更新 metrics 数、mesh 数及两处排序。不能用单个 DLC 的字符子集覆盖当前字体，否则会丢失基础游戏字形。

## 9. 法律声明纹理

修改条目：

```text
Mount/media/ui/textures/Localized.zip
  CHT/Legal_Disclaimer.swatchbin
```

该文件为 Xbox One `swatchbin` 纹理：ASCII 魔数 `burG`，TXCB version 2，包含 TXCH 元数据。当前文件的 83 字节头保持不变；主要字段为宽 `0x40`、高 `0x42`、深度 `0x44`、mip 数 `0x4C`、相对 mip 数 `0x4D`、偏移 `0x4E`、flags `0x4F`。`tileMode = flags & 0x1F`，`encoding = (flags >> 5) & 0x3F`。

本纹理为 1920×1080、1 mip、tile mode 14、encoding 9（BC7 / DXGI 98），负载 2,359,296 字节并含 tiled padding。处理流程：用 Xbox One 纹理地址计算库解 tile，BC7 解码到 RGBA，只重绘三块中文区域，再以 BC7 最高质量编码，把未涉及区域的原始 BC7 块复用，最后重新 tile 回原负载副本。英文版权行、背景、文件头、padding 和其他 15 种语言条目保持不变。

修改区域以 4 像素块对齐：

```text
x 400..1520, y 352..396
x 360..1560, y 488..564
x 360..1560, y 592..704
```

原始 17 个 CHT 纹理均做过解 tile 后再回写的逐字节验证；只有法律声明包含需要转换的繁体中文。验证时应再次解码补丁纹理作视觉检查，并确认包内其余条目字节不变。

## 10. 安装、恢复和校验清单

`resources/files.json` 是机器读取的安装清单。它保存每个目标的相对路径、安装方式、原始/补丁/增量校验值及长度。大量 SHA-256 用于保护游戏文件，避免把追加数据写到错误版本，或把恢复截断用于其他补丁修改过的文件；它们不是额外资源。

安装流程：

1. 对全部 226 个目标预检，状态只能是已知原版、当前补丁版或清单明确允许的旧补丁版。
2. 三个完整替换文件首次安装时备份到游戏目录的 `FH2_CHS_Backup`，再复制 `resources/payload`。
3. 223 个追加文件只在原始长度和原始 SHA-256 都匹配时追加 `data.bin` 中的对应区段。
4. 每个文件写入后立即验证补丁 SHA-256。

恢复流程：完整替换文件从备份复制；追加文件只有在完整补丁 SHA-256 匹配时才截断到原始长度，随后验证原始 SHA-256。脚本支持中断后重跑，但不提供跨 226 文件的事务回滚。

### 清单字段

| 字段 | 含义 |
|---|---|
| `Path` | 相对于游戏目录的资源路径，以 `Mount\` 开头 |
| `OriginalSHA256` | 原始文件的 SHA-256 |
| `PatchedSHA256` | 补丁后完整文件的 SHA-256 |
| `OriginalLength` | 原始文件的字节数，仅追加资源包含此字段 |
| `PatchedLength` | 补丁后文件的字节数，仅追加资源包含此字段 |
| `DataOffset` | 该资源在 `data.bin` 中的起始字节偏移，仅追加资源包含此字段 |
| `DataLength` | 该资源在 `data.bin` 中占用的字节数，仅追加资源包含此字段 |
