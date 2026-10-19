# Halo 5 (Xbox One, module v23) 资源解包与定位 SPEC

本文档描述**如何解包 / 定位游戏资源**的技术细节，供制作文本/翻译类补丁参考，全部为小端序（little-endian）。

## 1. 目录结构

游戏内容根目录记为 `MOUNT`（例：
`C:\Games\Halo5-Guardians_<ver>_x64_1_8wekyb3d8bbwe\Mount`）。

| 路径 | 内容 |
|------|------|
| `MOUNT\deploy\any\...` | 主模块树（关卡、globals、ui、cinematics 等） |
| `MOUNT\maps\fonts\*.bin` | 字体包（按语言分包，见 §6） |

- 标签/资源都打包在 `*.module` 文件里。
- 枚举全部模块：`MOUNT\deploy\**\*.module`（递归）。
- 典型规模：~1800+ 个 `.module`。

---

## 2. 模块容器格式（`.module`）

文件以魔数 `mohd` 开头。文件由若干**表**顺序排列，随后是**数据区**。

### 2.1 头部

| 偏移 | 大小 | 类型 | 字段 |
|-----:|-----:|------|------|
| 0  | 4 | char[4] | 魔数 `"mohd"` |
| 4  | 4 | u32 | version（Xbox One = **23**；v27+ 头部/表项更大） |
| 16 | 4 | i32 | item_count（标签数量） |
| 20 | 4 | i32 | manifest_count |
| 24 | 4 | i32 | resource_index |
| 28 | 4 | i32 | strings_size（字符串名表字节数） |
| 32 | 4 | i32 | resource_count |
| 36 | 4 | i32 | block_count |

`header_size = 48`（version < 27），否则 `56`。
`item_size = 88`。
`block_size = 20`（version < 27），否则 `32`。

### 2.2 表的排列顺序与定位

依次为：

1. **item 表**：起始 `header_size`，`item_count × item_size` 字节。
2. **strings 名表**：紧接 item 表，`strings_size` 字节。
3. **resource 表**：紧接 strings，`resource_count × 4` 字节。
4. **block 表**：紧接 resource 表，`block_count × block_size` 字节。
5. **数据区**：紧接 block 表，`data_address = header_size + item_count*88 + strings_size + resource_count*4 + block_count*block_size`。

### 2.3 item 表项（88 字节）

| 偏移 | 类型 | 字段 |
|-----:|------|------|
| 0  | i32 | name_offset（相对 strings 名表） |
| 8  | i32 | resource_count |
| 12 | i32 | resource_index |
| 16 | i32 | block_count（该标签占用的 block 数） |
| 20 | i32 | block_index（首个 block 在 block 表中的下标） |
| 24 | i64 | data_offset（相对**数据区**起点） |
| 32 | u32 | total_compressed_size |
| 36 | u32 | total_uncompressed_size |
| 43 | u8  | flags |
| 44 | i32 | global_tag_id |
| 64 | char[4] | class（**字节序反写**，见 §3） |

### 2.4 block 表项（v23：20 字节）

| 偏移 | 类型 | 字段 |
|-----:|------|------|
| 0  | u32 | comp_offset（相对该 item 的 data_offset） |
| 4  | u32 | comp_size（压缩后大小 = 磁盘上的字节数） |
| 8  | u32 | unc_offset |
| 12 | u32 | unc_size（解压后大小） |
| 16 | u32 | compressed（1 = zlib 压缩；0 = 原样存储） |

> v27+ 的 block 表项前有 8 字节前缀，故 `block_size=32`，实际字段从 +8 起。

### 2.5 计算方法

```
某 item 的第 k 个 block 的文件绝对偏移 =
    data_address
  + item.data_offset
  + block.comp_offset
（block = block_table[item.block_index + k]）
```

---

## 3. 标签类别（class）识别

class 名字以 **4 字节反写**存放。例如 `unic` 在文件里是字节
`"cinu"`（`63 69 6E 75`）。识别时把 4 字节反转再按 ASCII 解释，或直接比较
`class_bytes[::-1] == b"unic"`。

常见有用类别：

| 反写字节 | 类别名 | 含义 |
|----------|--------|------|
| `cinu` | `unic` | `multilingual_unicode_string_list`（多语言字符串表） |

---

## 4. 压缩

- `block.compressed == 1`：块内是**标准 zlib 流**（deflate + zlib 头/尾 Adler-32）。
  解压：`zlib.decompress(block_bytes[0:comp_size])`。
- `block.compressed == 0`：块为原样存储。
- 重压缩：`zlib.compress(data, 9)`；本例中结果均 **不大于**原 `comp_size`。
  为**就地等长覆盖**，把重压缩结果**尾部补 `0x00`** 到原 `comp_size`；游戏端 inflate
  在流结束后忽略多余字节。
- 数据区各块**无独立校验和**；v23 模块头部/表也**无校验和** → 等长覆盖后无需修复任何偏移。

---

## 5. `unic` 标签布局（多语言字符串表）

每个 `unic` item 恰好有 **2 个 block**。解压后
`blob = block[0] ++ block[1]`：

- `block[0]`：标签头 + string-id 名称表（如 `redeem`、`sell_confirm_message`、`__default__`）。
- `block[1]`：**主数据**，结构为：

```
[小头部][引用记录数组 (count × 72)][字符串数据 SD (UTF-8, 以 \0 结尾)]
```

### 5.1 引用记录（72 字节）

```
u32 string_id
u32 offset[17]      // 17 种语言的字符串偏移
```

语言顺序（数组下标）：

| idx | 语言 | idx | 语言 | idx | 语言 |
|----:|------|----:|------|----:|------|
| 0 | en | 6 | it | 12 | ru |
| 1 | jp | 7 | ko | 13 | da |
| 2 | de | 8 | **cht** | 14 | fi |
| 3 | fr | 9 | **chs** | 15 | nl |
| 4 | es | 10 | pt | 16 | no |
| 5 | mx | 11 | pl | | |

- 偏移**相对字符串数据起点 SD**（不是绝对 tag 偏移）。
- 值 `0xFFFFFFFF` 表示该语言缺失。
- 字符串以 `\0` 结尾。

### 5.2 通过头部提示定位布局

`block[1]` 内：

| 位置 | 类型 | 字段 |
|-----:|------|------|
| 0x08 | i32 | global_tag_id |
| 0x20 | i32 | count（引用记录条数） |
| 0x60 | i32 | sd_size（字符串数据大小） |

推导：

```
SD         = len(block[1]) - sd_size
refs_start = SD - count * 72
第 k 条记录 @ refs_start + k*72
第 k 条语言 L 的字符串 = block[1][ SD + offset(L) : \0 ]
```

### 5.3 健壮性注意

- 定位后应**抽样校验**：读取各记录的语言偏移，确认 `!= 0xFFFFFFFF` 时
  `offset < sd_size`。个别标签的引用布局可能不同（例：基础包
  `levels\globals-rtx-1.module` 中的部分 `unic` 布局异常，且往往**不含本地化文本**）。
- 建议回退策略：当引用解析校验失败时，退化为"在字符串数据区扫描含 CJK 的
  以 `\0` 结尾字符串"。

### 5.4 已知样本

`levels\globals\assets_4k\singleplayer_4k-rtx-97230-1.module` 的 item 7：
`count=339`、`sd_size=116194`、`SD=24576`、`refs_start=168`。
例：`cht='選取'`、`jp='選択'`、`en='Select'`。

---

## 6. 字体资源（`font_package_*.bin`）

字体包位于 **`MOUNT\maps\fonts\`**，每种语言一个包（内含若干"字体"）：

| 文件 | 大小 | 字体 | 说明 |
|------|-----:|------|------|
| `font_package.bin` | 98304 | `en\fixedsys-9`(97), `en\subtitle-20`(462) | 基础（拉丁） |
| `font_package_4k.bin` | 147456 | `en\fixedsys-9`, `en\subtitle-40` | 基础（4K） |
| `font_package_cht.bin` | 3047424 | `cht\fixedsys-9`(97), `cht\subtitle-20`(**14965**) | 繁中 |
| `font_package_cht_4k.bin` | 6144000 | `cht\fixedsys-9`, `cht\subtitle-40`(**14620**) | 繁中（4K） |
| `font_package_jpn.bin` / `_4k` | 1622016 / 3342336 | `jpn\subtitle-20/40` | 日文 |
| `font_package_kor.bin` / `_4k` | 589824 / 983040 | `kor\subtitle-20/40` | 韩文 |
| `font_package_ru.bin` / `_4k` | 98304 / 147456 | `ru\subtitle-20/40` | 俄文 |

> `fixedsys-9` 仅含 ASCII（97 字形）；CJK 文本由同包的 `subtitle-20`/`subtitle-40` 渲染。
> 字体是**预渲染位图**（非 TTF、非 SDF），按语言裁剪，只含该语言需要的字形。

### 6.1 格式来源

该包是 **Blam 引擎字体包**格式，与社区工具
**FontPackager**（Lord-Zedd/FontPackager）完全一致。`0xC0000003` =
`PackageVersion360`（无 64 位头部/字形）；本游戏用其 **H4/"Halo 5 Forge" 变体**
（`Max64Fonts` + 块大小 `0xC000`）。另有 `0xC0000004`（MCC，x64）、
`0xC0000005`（H2A，`0x10000` 块）。

### 6.2 包头

```
u32 version            // 0xC0000003
i32 font_count
FontInfo[max]          // max=64（每条 12B）；判据：首条 offset==1048(0x418) → 64，否则 16
    { i32 offset; i32 size; i16 start_block; i16 block_count; }
i32 orders[max]        // 引擎字体顺序（-1 = 空）
i32 header_table_offset   // 字体头区起点（=0x418）
i32 header_table_size
i32 block_ranges_offset
i32 block_count
字体头区（font_count 个，见 §6.3）
块范围表（block_count × 8B）：{u16 start_unic, u16 start_font, u16 end_unic, u16 end_font}
… 补齐 0x00 到 chunk_size（0xC000）
块区（block_count × chunk_size，见 §6.4）
```

`header_table_offset` 恒等于 `8 + max*12 + max*4 + 0x10`。

### 6.3 字体头（每条 `0x15C` 字节 + 紧接的 kerning 对）

| 偏移 | 类型 | 字段 |
|-----:|------|------|
| 0x00 | u32 | `0xF0000005` |
| 0x04 | char[32] | 字体名（`\0` 补齐，如 `cht\subtitle-20`） |
| 0x24 | i16×4 | ascend, descend, lead_h, lead_w |
| 0x2C | i32 | pairstart(=0x15C) |
| 0x30 | i32 | paircount |
| 0x34 | u8[0x100] | kerning 索引（每首字符 → 对起始） |
| 0x134 | i32 | pairend；0x138 last_char；0x13C char_count |
| 0x140 | i32 | virtualdatastart；0x144 i32 block_data_size |
| 0x148 | u32 | fallback 字形 datum（`0xFFFFFFFF`=无） |
| 0x14C | i32×4 | max_comp, max_decomp, comp_total, decomp_total |
| 之后 | (u8,i8)[paircount] | kerning 对 |

`decomp` 计入的是 `宽×高×2`（16bpp 像素），`comp` 为各字形压缩字节数之和。

### 6.4 数据块

块区从 `chunk_size`（`0xC000`）开始，连续 `block_count` 块，每块 `chunk_size` 字节：

```
i16 version(=8); i16 char_count; i16 char_table_size(=count*8+8); i16 char_data_size
char_count × { u16 unic; i16 font_index; i32 data_offset }   // 相对块起点
字符数据记录（每条 8 字节对齐）：
    u16 display_width; i16 comp_size; u16 width; u16 height;
    i16 origin_x; i16 origin_y; u8 comp[comp_size]
```

某字形 = 某块中 `font_index` 匹配其字体的记录；一个字体的字形散布在
`[start_block, start_block+block_count)` 的块里。块写满即新开一块（`char_data_size`
字段是 16 位截断值，读取时可忽略）。

### 6.5 字形位图与压缩（ARGB4444 + 自定义 RLE）

- 解压后为 **每像素 4 字节 BGRA**，尺寸 `width × height`；取色是 4-bit/通道
  （`alpha = (A>>4)*17` 等），实际字形为**白色 + 4-bit 抗锯齿 alpha**。
- 压缩为自定义 RLE：字面量 `00 AR GB`（1 像素），或运行码/差分码；
  详细算法见参考实现 `blamfont.py`（与 FontPackager `CharacterTools` 一致，
  已实测**逐字形无损**且**整包逐字节可复现**）。

### 6.6 追加字形与重打包

- 在目标字体的字形列表里**新增** `Char`（`unic` 用 BMP 码位），用 writer 整体重写：
  字体头/块范围/各 `block_count` 与 `offset` 均会重算。
- 新增数据以 `chunk_size` 为单位增长（本补丁 706 字形：非 4K +1 块 / 4K +2 块）。
- 实测：对全部 10 个 `font_package_*.bin`，本 writer **逐字节复现原文件**（round-trip
  完全一致），因此增字后重写的包结构正确、可被引擎读取。

### 6.7 本游戏的 *中文字体* 指标

| 包/字体 | 框高 H | 基线 oy | 典型字距 | 参考字号(雅黑) |
|---------|------:|-------:|--------:|--------------:|
| `cht\subtitle-20` | 35 | 27 | ≈26 | 28 px |
| `cht\subtitle-40` | 54 | 42 | ≈52 | 54 px |

CJK 字形墨迹约占 `y=6..30`（20 号）/ `y=2..50`（40 号），左对齐需按 `origin_x`
定位、`display_width` 前进。缺字时引擎画 `fallback` 字形（方框）。

---

## 7. 就地打补丁要点（长度不变替换）

1. 用 §2–§5 定位目标字符串并解码 UTF-8。
2. 逐字符替换；**保证 UTF-8 字节长度不变**（CJK 基本区字符恒为 3 字节，
   1:1 字符映射即可等长）。
3. 重新 `zlib.compress(...,9)` → 尾部补 `0x00` 到原 `comp_size`。
4. 在原 `data_address + item.data_offset + block.comp_offset` 处**等长覆盖**。
5. 文件大小、所有偏移与表均不变，无需其他修复。
