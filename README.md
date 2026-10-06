# 边狱公司 中英双语汉化包（剧情 / 小故事）

把官方英文与「都市零协」中文整合成**同一个自定义语言包**，让剧情文本与各类小故事以

```
英文原文
中文译文
```

的形式上下并列显示（英文在上、中文在下）。**界面、战斗提示、状态、技能介绍等一律保持中文单语**，不做双语。

> ⚠️ **禁止商用。** 中文文本来自 [LocalizeLimbusCompany](https://github.com/LocalizeLimbusCompany)（都市零协），授权为 **CC BY-NC-SA 4.0**；英文文本版权归 **Project Moon**。本包只是把两者整合，不含任何游戏资源本体。

---

## 一、这个包里有什么

| 内容 | 说明 |
| --- | --- |
| 全部 `*.json` | 100% 中文（含最新的第八/九/十章剧情） |
| 其中的剧情与故事文本 | 双语：`英文\n中文` |
| `Font\Context\ChineseFont.ttf` | 中文显示所需字体（沿用零协原包） |
| `Info\` | 零协的授权文件与版本信息 |

**双语化的范围**（共 13 条规则，写在 `StoryFields.json`）：

- `StoryData\*.json` —— 全部主线/支线剧情对话
- `AbnormalityGuides*.json` —— 观察记录、异想体小故事
- `StoryTheaterDanteNote*.json`、`StoryTheaterDanteNoteDetail*.json` —— 但丁笔记
- `StoryTheaterMain*.json`、`StoryTheaterMirrorWorld.json`、`StoryTheaterOther.json` —— 剧场文字
- `Egos.json`、`Egos-*.json` —— E.G.O 的名称与故事文本
- `Personalities.json`、`Personalities-*.json`、`Personality_Get_Condition.json` —— 人格故事
- `Story-a1c8p3.json` —— 但丁能力台词

**保持中文单语的**：技能（`Skills*`）、被动（`Passives*`）、E.G.O 礼物（`EGOgift*`）、状态与战斗关键词（`Bufs*`、`BattleKeywords*`、`BattleHint*`）、全部界面文本（`*UIText*`、`MainUIText*`、`StoryTheaterUIText.json` 等）、语音台词、BGM 歌词。这些文件与已安装的零协中文包**逐字节一致**，没有被改动。

语言无关的标识字段（`id`、`model`（韩文角色标识）、`codeName`、`level` 等）原样保留。

---

## 二、安装

### 方法一：手动复制（最直接）

1. 下载本仓库（点 **Code → Download ZIP**，或用 git clone）。
2. 把仓库里的**全部内容**放进游戏目录下新建的文件夹：

   ```
   ...\steamapps\common\Limbus Company\LimbusCompany_Data\Lang\LLC_zh-CN_bilingual\
   ```

   ⚠️ **不要多套一层目录**：`LLC_zh-CN_bilingual` 里应该直接看到 `StoryData\` 等文件夹和一堆 `.json`。

3. 用记事本打开同级的

   ```
   ...\LimbusCompany_Data\Lang\config.json
   ```

   把 `lang` 的值改成 `LLC_zh-CN_bilingual`，例如：

   ```json
   {"lang": "LLC_zh-CN_bilingual", "titleFont": "", "contextFont": "", "samplingPointSize": 78, "padding": 5}
   ```

4. 启动游戏。

原版的 `LLC_zh-CN` 目录不用动，随时把 `lang` 改回 `LLC_zh-CN` 就能切回纯中文。

### 方法二：用脚本

```powershell
# 在本仓库目录里执行
.\install-bilingual.ps1
```

脚本会把语言包复制到 `Lang\LLC_zh-CN_bilingual`（已存在先备份改名），并自动把 `config.json` 的 `lang` 改好。游戏装在非默认位置时：

```powershell
.\install-bilingual.ps1 -LangRoot "你的\Limbus Company\LimbusCompany_Data\Lang"
```

---

## 三、数据来源

| | 来源 | 用途 |
| --- | --- | --- |
| 英文 | 游戏官方英文本地化<br>`LimbusCompany_Data\Assets\Resources_moved\Localize\en`（文件名带 `EN_` 前缀） | 双语中的英文 |
| 中文 | **已安装的零协语言包**<br>`LimbusCompany_Data\Lang\LLC_zh-CN`（2387 个 json） | 双语中的中文、以及所有单语文件 |
| 兜底 | [LocalizeLimbusCompany/LLC_Release](https://github.com/LocalizeLimbusCompany/LLC_Release) | 补上官方英文里没有的 7 个文件 |

> 为什么中文源用**已安装的语言包**而不是发布仓的 `CN/`？因为发布仓的 `CN/StoryData` 只到第七章（最大 `S737B`），**完全没有第八/九/十章**；已安装的 `LLC_zh-CN` 有 991 个 `StoryData` 文件、最新到 `S951B`，才是完整的。

---

## 四、校验结果

合并脚本自带一个校验脚本，重新合并后可以随时复核：

```powershell
.\verify-story-bilingual.ps1 `
  -OfficialEnDir "D:\SteamLibrary\steamapps\common\Limbus Company\LimbusCompany_Data\Assets\Resources_moved\Localize\en" `
  -InstalledCnDir "D:\SteamLibrary\steamapps\common\Limbus Company\LimbusCompany_Data\Lang\LLC_zh-CN" `
  -OutDir ".\" `
  -ModeFile ".\StoryFields.json" `
  -ReportPath ".\verify-report.txt"
```

最近一次全量校验：

| 项目 | 结果 |
| --- | --- |
| 语言无关字段（`model` 等）被改动的 | **0** |
| 文本不是「英文＋换行＋中文」也不是单侧的 | **0** |
| 英文条目在产物里丢失的 | **0** |
| 产物里多出、英文侧没有的键 | **0** |
| 范围外文件与中文包**逐字节一致** | **1333 / 1333** |
| 范围内但缺官方英文的文件（原样保留中文） | 7 / 7 逐字节一致 |

---

## 五、自己重新生成

需要重跑合并（例如游戏更新后）时：

```powershell
# 1) 合并（约 7~8 分钟）
.\merge-story-bilingual.ps1 `
  -OfficialEnDir "D:\SteamLibrary\steamapps\common\Limbus Company\LimbusCompany_Data\Assets\Resources_moved\Localize\en" `
  -InstalledCnDir "D:\SteamLibrary\steamapps\common\Limbus Company\LimbusCompany_Data\Lang\LLC_zh-CN" `
  -ReleaseCnDir "<LLC_Release>\CN" `
  -ReleaseEnDir "<LLC_Release>\EN" `
  -ModeFile ".\StoryFields.json" `
  -OutDir ".\out"

# 2) 校验
.\verify-story-bilingual.ps1 -OfficialEnDir "..." -InstalledCnDir "..." -OutDir ".\out" -ModeFile ".\StoryFields.json"
```

想把某个文件也纳入双语（或排除），只改 `StoryFields.json` 的 `scopes` / `excludeFields` 即可。

---

## 六、授权与致谢

- 中文文本：**都市零协 LocalizeLimbusCompany**，授权 **CC BY-NC-SA 4.0**（见 `Info\LICENSE`）——**禁止商用**，转载/修改需同样以 CC BY-NC-SA 4.0 发布并署名。
- 英文文本：版权归 **Project Moon**。
- 本整合包不含游戏本体资源，请支持正版。
