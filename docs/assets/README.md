# 界面预览与宣传素材

README 默认使用中文，英文说明也展示中文界面配图，与应用当前的简体中文界面保持一致。

## 宣传图

宣传图用于介绍产品和学习流程，包含合成场景、说明文字或组合排版；它们与下方的原生界面预览分开记录。

| 文件 | 用途 |
| --- | --- |
| `homepage-hero-zh-CN.png` | 正面书架主页，作为 README 主图。 |
| `photo-to-notes-zh-CN.png` | 批量笔记照片 → 对话整理 → 章节笔记，展示主要工作流程。 |
| `chat-explain-zh-CN.png` | 围绕导入资料进行对话、解释和补充。 |
| `read-review-zh-CN.png` | 原稿对照、阅读与知识卡片复习。 |
| `export-workflow-zh-CN.png` | PDF、Word、Markdown 与单文件 HTML 导出。 |
| `hero-zh-CN.png` | 阅读、知识卡片与导出功能概览，作为可展开的补充图。 |

书架主图以 `homepage.png` 中的实际视图为参考，使用内置图像生成工具制作；生成与中文化说明保存在 [homepage-prompts.txt](homepage-prompts.txt)。

功能概览以 `reading.png` 和 `review.png` 为参考，桌面、纸张、阴影和功能说明栏属于宣传构图。制作说明保存在 [hero-prompt.txt](hero-prompt.txt) 和 [hero-localization-prompt.txt](hero-localization-prompt.txt)。这些图使用合成演示内容制作。

四张流程功能图以 `chat.png`、`reading.png`、`review.png` 和独立演示应用的真实导出窗口截图为界面参考；照片中的手写笔记全部为原创合成示例。制作提示词见 [feature-prompts.txt](feature-prompts.txt)。画面中的对话是演示内容，不是对特定模型的实测记录。

## 原生界面预览

`homepage.png`、`reading.png`、`review.png` 和 `chat.png` 是应用实际 SwiftUI/AppKit 视图层级的位图渲染，使用 `Examples/demo-library.json` 和原创水循环示例对话。书架、阅读与复习流程也已在独立演示应用中检查。对话预览不调用模型，不包含账户配置。

预览采用浅色外观和应用阅读偏好，不包含 macOS 窗口边框。书架视口为 1320 × 900 点，阅读与复习视口为 1280 × 920 点。演示内容为本仓库原创，适用项目许可证；其中不包含私人资料库、账户配置或个人文件路径。

## 后续素材

以当前应用的中文界面和实际流程为依据，使用原创合成资料；图中涉及的模型能力、导入和导出格式须与产品一致。加入素材前检查画面与嵌入元数据，保留对应的制作说明。
