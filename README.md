<img src="./android/app/src/main/res/mipmap-xxhdpi/ic_launcher_round.png" alt="logo" width="144" height="144" align="right" />

# PixEz Flutter ![](https://camo.githubusercontent.com/f2b4fa6779c8a4825e0e7347076746a2047ed100/68747470733a2f2f696d672e736869656c64732e696f2f62616467652f6c6963656e73652d47504c2d2d332e302d6f72616e67652e737667)

[English README Here](./.github/README_en.md)<br />
[README Bahasa Indonesia klik disini](./.github/README_id.md)

使用 Flutter 编写的 pixiv 第三方客户端。

同样支持中国大陆地区直连。

本分支在保存到设备前，自动处理文件名和作者目录名中的 emoji，
以兼容无法保存 emoji 文件名的存储介质。在存储设置的「文件名中的 emoji」中，
可选择替换为下划线 `_`（默认）、剔除或替换为英文名称。
英文模式支持首字母小写或大写，例如 `🐟️` → `fish` / `Fish`；
多词名称以下划线连接，无法识别的表情回退为 `_`。英文名称离线转换，无需联网。
剔除后文件或目录名称为空时，会保留 `_` 作为名称。
普通空格、中文和日文等文字会保留，命名规则编辑页也重新允许输入空格。
例如规则 `{illust_id}_p{part} {title}` 遇到标题 `夏日🐟️` 时，
英文模式会保存为 `123_p0 夏日fish.jpg` 或 `123_p0 夏日Fish.jpg`。
此处理同样适用于自定义 JS 命名、旧下载任务重试、GIF/ZIP 导出、头像和小说导出。
建议命名规则保留 `{illust_id}` 与 `{part}`，以区分作品和页码。

用户已在原先的平板外置 TF/SD 卡场景下验证：作者名称或作品标题含 emoji 时，
可以正常保存文件到该卡。登录、空格命名及三种 emoji 处理模式均已实机确认有效。
具体范围见[验证记录](docs/VALIDATION.md)。

🎵 Mili - In Hell We Live, Lament 🎵 

# 下载

推荐渠道顺序为从左到右。

|系统|应用市场|GitHub|云盘|
|:---:|:---:|:---:|:---:|
|Android|[Google Play](https://play.google.com/store/apps/details?id=com.perol.play.pixez)|[Release](https://github.com/Notsfsssf/pixez-flutter/releases/latest)|[蓝奏云](https://wwa.lanzoui.com/b0ded45id)<br />**临时，不推荐**|
|iOS|[App Store(美区)](https://apps.apple.com/us/app/pixez/id1494435126)|[Action Ipa](https://github.com/Notsfsssf/pixez-flutter/actions/workflows/build_ios.yml)|/|
|Windows|/|[Nightly MSIX](https://github.com/Notsfsssf/pixez-flutter/actions/workflows/build_windows.yml)|/|

# 预览

|![Preview](./.github/preview/2.jpg) | ![Preview](./.github/preview/1.jpg) | 
|:-------------------:|:------------------------:|

# 关于项目 / About Repository

如你所见，Flutter 是一个能够帮助开发者快速开发界面的框架。

拥有的 Hot Reload 热重载，可以极大缩减 debug 成本，所见即所得，快速交流；

利用 PlatformChannel，可以为不同平台编写不同的平台特性的独有功能；

应用使用了 `mobx`，`flutter_bloc` (逐步弃用)，`provider` 进行状态管理，`custompainter` 来播放 ugoira。

## 贡献 / Contribute

本项目目前的贡献者列表如下：

<table>
  <tr>
    <td align="center"><a href="https://github.com/Notsfsssf"><img src="https://avatars3.githubusercontent.com/u/16934707?v=4" width="100px;" alt=""/><br /><sub><b>Perol_Notsfsssf</b></sub></a><br /><a href="https://github.com/Skimige/pixez-flutter/commits?author=Notsfsssf" title="Code">💻</a></td>
    <td align="center"><a href="https://xyx.moe"><img src="https://avatars3.githubusercontent.com/u/9017470?v=4" width="100px;" alt=""/><br /><sub><b>Skimige</b></sub></a><br /><a href="https://github.com/Skimige/pixez-flutter/commits?author=Skimige" title="Documentation">📖</a></td>
    <td align="center"><a href="https://github.com/TragicLifeHu"><img src="https://avatars3.githubusercontent.com/u/16817202?v=4" width="100px;" alt=""/><br /><sub><b>Tragic Life</b></sub></a><br /><a href="#translation-TragicLifeHu" title="Translation">🌍 (zh_TW)</a></td>
    <td align="center"><a href="http://ivtune.net"><img src="https://avatars0.githubusercontent.com/u/54385201?v=4" width="100px;" alt=""/><br /><sub><b>karin722</b></sub></a><br /><a href="#translation-karin722" title="Translation">🌍 (ja)</a></td>
    <td align="center"><a href="http://archman.fun"><img src="https://avatars0.githubusercontent.com/u/68731023?v=4" width="100px;" alt=""/><br /><sub><b>Romani-Archman</b></sub></a><br /><a href="https://github.com/Skimige/pixez-flutter/commits?author=Romani-Archman" title="Documentation">📖</a></td>
    <td align="center"><a href="https://github.com/itzXian"><img src="https://avatars1.githubusercontent.com/u/34748039?v=4" width="100px;" alt=""/><br /><sub><b>Xian</b></sub></a><br /><a href="#translation-itzXian" title="Translation">🌍 (en_US)</a></td>
    <td align="center"><a href="https://github.com/ReikiAigawara"><img src="https://avatars1.githubusercontent.com/u/66962815?v=4" width="100px;" alt=""/><br /><sub><b>Reiki Aigawara</b></sub></a><br /><a href="#translation-ReikiAigawara" title="Translation">🌍 (id_ID)</a></td>
  </tr>
</table>

如果你是有能人士，愿意为本项目贡献代码，请不要犹豫提交 Pull Request 吧！

本应用也使用了 `intl` 进行国际化，欢迎贡献[翻译](lib/l10n/intl_en_US.arb)！

觉得有些地方设计的不妥？同样欢迎分享设计。

## 常见问题及交流反馈

[使用指南 & 常见问题在这里](.github/FAQ.md)，反馈问题 / 加群询问之前请先看！（特别是旧原生版用户）

邮件反馈：PxezFeedback@outlook.com

也可以在 Telegram 群交流反馈：[@PixEzViewer](https://t.me/PixEzChannel)

Discord: [@PixEz](https://discord.gg/Em9AeJbg)

也可以进企鹅群交流经验或者反馈：815791942（闲聊为主）
