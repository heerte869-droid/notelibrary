# MacPaw/OpenAI

Source: https://github.com/MacPaw/OpenAI
Revision: c155b5245243f4984791bbe2db80be509b00854a (2026-10-01)
License: MIT, see LICENSE.

Vendored Sources and Package.swift only. Local patch: pass the caller URLSession configuration through OpenAI -> ImplicitURLSessionStreamingSessionFactory -> FoundationURLSessionFactory. Upstream streaming created a new default session instead of inheriting the supplied session. This patch preserves networking configuration and allows the exact production streaming code to be tested without external requests. No model-specific parsing patch.

When updating, reapply this small injection patch and run the protocol fixture tests before release.

Second narrow upstream patch: apply the SDK's existing relaxed metadata policy to ChatStreamResult.created and Choice.index, matching its handling of id/model/object. Missing/null transport metadata may default; delta/content and application note-plan validation remain strict.

Privacy patch: remove the debug print of raw Responses API event payloads. Error propagation is unchanged.

Streaming HTTP metadata patch (2026-10-07): notify the existing response middleware when headers arrive, with a nil body. The normal streaming-data hook still receives each body chunk once. This preserves the real status when upstream decodes an APIErrorResponse (otherwise the status is lost and a 400 parameter rejection cannot be distinguished from 401/429/5xx). The app's compatibility policy remains status-aware; no vendor/model branch is added. Regression fixtures include typed error envelopes and real DeepSeek responses.
