# Provider integration

Presets supply a starting address and protocol. They do not supply credentials or guarantee account access. Exact model IDs, regions, rate limits and capabilities remain provider-specific. Check the linked official documentation when configuring a service.

| Preset | Default conversation protocol | Documentation |
| --- | --- | --- |
| OpenAI | Responses | [Official docs](https://developers.openai.com/api/docs/quickstart) |
| DeepSeek | Chat Completions | [Official docs](https://api-docs.deepseek.com/) |
| Claude | Messages | [Official docs](https://platform.claude.com/docs/en/api/overview) |
| Gemini | Google's OpenAI-compatible Chat Completions endpoint | [Official docs](https://ai.google.dev/gemini-api/docs/openai) |
| Kimi | Chat Completions | [Official docs](https://platform.moonshot.ai/docs/api/chat) |
| GLM | Chat Completions | [Official docs](https://docs.bigmodel.cn/) |
| Qwen | DashScope compatible-mode Chat Completions | [Official docs](https://help.aliyun.com/en/model-studio/base-url) |
| Doubao | Chat Completions | [Official docs](https://docs.volcengine.com/docs/ark/compatible-with-openai-sdk?lang=zh) |
| MiniMax | Chat Completions | [Official docs](https://platform.minimax.io/docs/api-reference/text-openai-api) |
| OpenRouter | Chat Completions | [Official docs](https://openrouter.ai/docs/quickstart) |
| SiliconFlow | Chat Completions | [Official docs](https://docs.siliconflow.cn/en/userguide/quickstart) |
| Custom | Explicit choice of Chat Completions, Responses or Messages | Use the endpoint operator's specification |

Image generation has a separate model assignment and protocol selection. Current adapters cover OpenAI Images-compatible responses and the configured SiliconFlow, DashScope, Gemini, GLM, Doubao, MiniMax and OpenRouter image formats. A text-only model cannot gain image-generation capability by changing its label in NoteLibrary. Search is similarly separate: configure Tavily, Brave, or an actually supported built-in model search capability.

## Compatibility work

`CompatibleAIClient.swift` is the shared transport and normalization boundary. Keep custom hosts and base paths intact; a display name is not authority to rewrite an endpoint. Do not forward provider credentials when downloading a generated image from a different host. Preserve cancellation and distinguish authentication, quota, unsupported capability and malformed response failures.

The public tests use synthetic requests and responses. They exercise protocol handling and regression cases, not every combination of model version, region, endpoint and account. A successful connection test only establishes the request it actually performed.

When adding a service, include sanitized protocol fixtures for successful text, errors, incomplete responses and any supported image result shape. Use opt-in synthetic live tests outside ordinary CI when account verification is needed. Do not commit captured personal conversations or credentials.
