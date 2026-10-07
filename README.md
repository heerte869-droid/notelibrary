# NoteLibrary

**把课件、照片和零散笔记，整理进自己的学习书架。**

一次导入多张笔记照片，在对话里告诉 AI 想怎么整理，再把内容收进章节。阅读时对照原稿，复习时切到知识卡片。NoteLibrary 是一个围绕这些日常学习过程设计的原生 macOS 应用。

[English](README.en.md) · [开始使用](#开始使用) · [功能图集](docs/SHOWCASE.zh-CN.md) · [界面预览](#界面预览) · [参与贡献](CONTRIBUTING.md)

**macOS 15+ · 简体中文界面 · MIT 开源 · 源码预览版**

![NoteLibrary 中文书架主页，按笔记本组织学习资料](docs/assets/homepage-hero-zh-CN.png)

## 从一叠笔记照片，到按章节整理的笔记

1. **把资料放进来。** 一次选择多张拍摄的笔记照片，加入同一段对话；也可以导入 PDF、Word、PowerPoint、Markdown 和文字。
2. **说清楚想怎么整理。** 告诉 AI 科目、主题和整理要求，接着追问、补充例子或调整结构。
3. **收进自己的书架。** 将整理结果保存为章节与笔记。之后添入新资料、回看原稿，或者搜索某个知识点，都能接着用。

![批量导入笔记照片，通过对话整理为章节笔记的流程](docs/assets/photo-to-notes-zh-CN.png)

## 读不懂的继续问，记不牢的单独练

| 围绕资料继续问 | 阅读与复习，各有自己的界面 |
| --- | --- |
| 让 AI 解释一段内容、比较两个概念，或结合已有笔记补充例子。配置联网检索后，还可以查找网页来源。 | 阅读模式可调整字号、行距和版心，旁边打开原稿对照。术语、公式、概念和图示用独立卡片呈现；书内复习先回忆，再翻看答案。 |
| ![围绕导入资料进行对话和讲解](docs/assets/chat-explain-zh-CN.png) | ![原稿对照、阅读与知识卡片复习](docs/assets/read-review-zh-CN.png) |

## 整理好了，就带走

同一篇笔记可以导出为 **PDF、Word、Markdown 或单文件 HTML**：打印阅读、接着编辑、迁移到其他工具，按用途选择格式。

<details>
<summary>查看导出流程</summary>

![按用途选择 PDF、Word、Markdown 或 HTML 导出](docs/assets/export-workflow-zh-CN.png)

</details>

## 开始使用

当前从源码构建。使用 **Xcode 26.3 或更高版本**，构建机器需满足 Xcode 自身的系统要求；编译出的应用可运行于 macOS 15 及以上。

```sh
./scripts/build.sh
```

完成后打开脚本打印路径中的 `.app`。也可以用 Xcode 打开 `macOS/NoteLibrary.xcodeproj`，选择 `NoteLibrary` scheme 运行。官方公证安装包尚未提供。

想先看看阅读和复习效果，可以创建带示例笔记的独立演示应用：

```sh
python3 scripts/make_demo.py .build/release/Build/Products/Release/NoteLibrary.app
```

打开命令打印的演示路径即可。无需 API 密钥，演示内容保存在独立临时资料库中。详见[演示说明](Examples/README.md)。

使用 AI 时，在 **设置 → 服务与模型** 中添加自己的服务和模型，或连接已登录的本机 Codex。API 费用由服务商收取。[使用指南](docs/GETTING_STARTED.md)介绍了配置与第一篇笔记的整理步骤。

## 给不同任务，选合适的 AI

日常对话、读图、编排、校对和生图可以分别分配模型。内置 OpenAI、DeepSeek、Claude、Gemini、Kimi、GLM、Qwen、Doubao、MiniMax、OpenRouter、SiliconFlow 预设，也支持自定义接口。

配置 Tavily 或 Brave 后，可以在对话中查找网页来源；分配合适的生图模型后，也能直接生成图片。接口选择和能力说明见[服务商与协议文档](docs/PROVIDERS.md)。

## 资料保存在自己的 Mac 上

笔记、附件和复习记录都在本机保存。阅读、编辑、本地搜索和复习不需要调用 AI；AI 与联网检索请求会发送给你配置的服务。

[隐私与密钥保存](PRIVACY.md) · [导出与备份](docs/GETTING_STARTED.md#data-and-backups)

## 界面预览

下面使用应用的原生视图和原创演示资料呈现实际界面。宣传图与预览的制作方式见[素材说明](docs/assets/README.md)。

<details>
<summary>展开查看书架、阅读器和知识卡片</summary>

### 书架

![NoteLibrary 原生书架，展示演示笔记本](docs/assets/homepage.png)

### 阅读器

![NoteLibrary 原生阅读器，展示水循环笔记与图示](docs/assets/reading.png)

### 知识卡片

![NoteLibrary 原生概念卡片，按章节组织](docs/assets/review.png)

</details>

<details>
<summary>查看阅读与复习功能概览</summary>

![NoteLibrary 中文阅读、知识卡片与导出功能宣传图](docs/assets/hero-zh-CN.png)

</details>

## 一起把它做好

欢迎试用示例，告诉我们哪里不好用，或者直接提交改进。文档导入样例、接口测试、无障碍体验和翻译都很有帮助。公开反馈请使用合成资料。

开发时可运行 `./scripts/test.sh` 执行离线测试，具体流程见[贡献指南](CONTRIBUTING.md)，接下来的方向见[路线图](docs/ROADMAP.md)。如果这个书架正合你用，欢迎留下一颗 Star。

## 许可证

[MIT](LICENSE)。依赖与素材保留各自许可，详见[第三方说明](THIRD_PARTY_NOTICES.md)。
