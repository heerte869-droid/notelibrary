# Getting started

[English overview](../README.md) · [中文介绍](../README.zh-CN.md)

NoteLibrary is a native macOS application. The current interface is in Simplified Chinese; this guide includes the corresponding control labels.

## Build and open

Requirements:

- A Mac that meets Xcode 27's system requirements, with Xcode 27 and its macOS SDK installed. Other Xcode versions have not been verified.
- macOS 15 or later to run the resulting application; this deployment target is separate from the build machine's requirements.

Download or clone the repository, then run these commands from its root:

```sh
./scripts/build.sh
./scripts/test.sh
```

The build script prints the location of the app. Open that `.app`, or open `macOS/NoteLibrary.xcodeproj` in Xcode and run the `NoteLibrary` scheme. The test script runs the offline suite; it does not require a paid provider account.

This source preview has no official notarized installer. A local build is not an Apple-notarized release. Do not disable macOS security protections to install an untrusted build.

## Configure AI

Open **设置** (Settings), or press **⌘,**. Choose **服务与模型** (Services and models).

1. Choose **添加服务商** (Add provider), then a preset or **自定义 API** (Custom API).
2. Enter your own API key and check the service address and protocol. Use the address supplied by your provider, including the correct region and any required path.
3. Add a model using its exact identifier. Enable only the capabilities that the model and endpoint actually support.
4. Run the relevant connection test and save the service. Tests make real requests and can incur charges.
5. Choose the service and model for the conversation. In **AI 功能分配** (AI function assignments), set separate models for tasks such as reading images, organizing notes, or generating images when needed.

An available, signed-in local Codex installation is another connection option. Its availability and model access depend on that installation and account. A local Codex connection does not imply that inference runs offline.

The repository contains no API keys or credits. API plans, model access, regional availability, and billing are managed by the service provider. A chat model does not automatically support image generation or external search.

### Custom services

Select the protocol that the endpoint actually implements: Chat Completions, Responses, or Claude Messages. Preserve the supplied model identifier, host, port, and base path. For image services, select the corresponding image protocol separately.

Use a local endpoint without a key only when that service is intentionally configured without authentication. Do not expose an unauthenticated service to an untrusted network.

## Make a first notebook

Start with original, non-sensitive sample material. For example, paste this into a new conversation:

> 请把下面的材料整理成一篇“三角形基础”笔记，放入“数学演示”笔记本，解释定义并增加一道复习题：三角形由三条线段首尾相接围成。在欧几里得平面中，三角形的内角和为 180°。等边三角形的三条边相等。

You can also use **导入学习资料…** (Import study material, **⌘O**) or drag a supported file into the window. Images, PDF, Word, PowerPoint, Markdown, and text can be used as sources. Recognition quality depends on the file and the configured model.

After organization finishes, open the saved note and inspect its text, formulas, and sources. Continue the conversation to request a specific revision. Check the saved result rather than relying only on the assistant's completion message. Version records and undo are available for supported note changes.

## Read, search, and review

Use **阅读** (Read) or **⌘⇧R** to enter the focused reader. **Aa** adjusts reading style. Source comparison lets you inspect imported material beside the note.

Search looks through local content and presents matching passages. Within a notebook, terms, formulas, concepts, and diagrams have dedicated views for quick browsing.

Open **书内复习** (Book review), recall the answer, then reveal it. Record whether you remembered it, found it difficult, or need another try. The app uses a simple local interval schedule; it does not measure or guarantee mastery.

## Generate an image or search the web

Configure an image-capable service and assign it to **生图** (Image generation) before asking for an image. A successful chat connection test is not an image-generation test.

For external search, configure Tavily or Brave and its required credentials. Explicitly ask the conversation to search the web, then inspect the returned source links. Search access can depend on the account's active plan.

Image generation and search can cost money. Do not include sensitive material in a request unless you are comfortable sending it to the selected service.

## Export

Open a note's actions and choose **导出笔记…** (Export note). Select a format for the intended use:

| Format | Intended use |
| --- | --- |
| PDF | A paginated document for reading or printing. |
| Word (`.docx`) | Continue editing the document, tables, and supported formulas. |
| Markdown | Move the text and LaTeX to other tools, with associated image files. |
| HTML | Read a self-contained document with embedded assets in a browser. |

Choose page and source options where available, and inspect the exported file. Long tables, unusual formulas, and complex source material may need additional review.

## Data and backups

The default library is in:

```text
~/Library/Application Support/NoteLibrary/
```

`Library.sqlite` stores notes and application state. `Assets/` stores attachments. Notes are not stored as a folder of Markdown files; Markdown is an export format.

API keys are stored separately in `Credentials/api-keys.json`. The credentials directory uses permissions `0700` and its files use `0600`; the key file is not encrypted. These permissions restrict other local accounts, but do not prevent software running as your account from reading the file. Never publish or attach the entire library directory.

The app's **导出完整备份…** (Export full backup) command creates a backup without the credentials store. Backups still contain private notes and sources, so keep them private. Note exports can also contain source names or citations according to your choices.

Reading, editing, local search, and review do not need an AI request. AI, image, and external search operations send relevant request content to the selected service. Refer to that provider's data policies when deciding what to send.

## If a request fails

| Symptom | What to check |
| --- | --- |
| Authentication or permission error | The key, account permissions, region, and service address. |
| Quota or rate limit | The provider's available balance, plan, and rate limits. |
| Chat works but image generation fails | Image-model assignment, image protocol, and account access to that model. |
| Chat works but search fails | Search-service credentials and the active search plan. |
| Model is missing | The model identifier and which capabilities were enabled for it. |
| Response is incomplete | Network connectivity, output limits, and the model's structured-output support. |

Avoid repeated paid retries when the error indicates missing access or quota. If reporting a problem, follow the [sanitized bug-report guidance](../CONTRIBUTING.md#report-a-problem); do not attach raw credentials, personal notes, or full API logs.
