# 《镜之边缘：催化剂》简体中文补丁

## 补丁介绍
基于 3DM 简体中文补丁的繁简字符映射和字体，适配 Steam Build 10351434（游戏程序版本 1.0.3.47248）。
将游戏的繁体中文文本转换为简体中文，保留原有措辞和术语，同时修正原补丁中的少数映射错误，补充缺失按键图标字体，并翻译启动停服提示等界面中的繁体字形。

## 安装方法

1. 在 Steam 库中右键游戏，打开“属性”，将游戏语言设为“繁体中文”。
2. 打开“属性 → 已安装文件 → 浏览”，进入包含 MirrorsEdgeCatalyst.exe 的游戏目录。
3. 安装前备份以下四个原文件：
   - Data\Win32\UI.sb
   - Data\Win32\gameconfigurations\initialinstallpackage\cas.cat
   - Patch\Win32\UI.sb
   - Patch\Win32\gameconfigurations\initialinstallpackage\cas.cat
4. 将本补丁中的 Data、Patch 文件夹及 bcrypt.dll 复制到游戏目录，合并文件夹并覆盖同名文件。

## 注意事项
验证游戏文件完整性或更新游戏后，补丁可能需要重新安装；其他游戏版本的兼容性未经验证。
bcrypt.dll 用于兼容修改后的游戏资源。

## 卸载方法
退出游戏，还原安装前备份的四个原文件，并删除本补丁新增的以下文件：
   - bcrypt.dll
   - Data\Win32\gameconfigurations\initialinstallpackage\cas_99.cas
   - Patch\Win32\gameconfigurations\initialinstallpackage\cas_99.cas

## 鸣谢
3DM 汉化组提供的简体中文字符映射和字体。
