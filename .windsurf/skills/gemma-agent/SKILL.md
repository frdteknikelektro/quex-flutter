---
name: gemma-agent
description: Standard Operating Procedure for building on-device Gemma agent features in the Quex Flutter project. Use this skill when building, modifying, or debugging any AI agent, tool-calling loop, multimodal input, or streaming response feature that uses flutter_gemma and GemmaInferenceService.
---

This skill defines the canonical patterns for on-device Gemma agent development in Quex. All patterns are derived from Google AI Edge gallery (Android/Kotlin reference) and DenisovAV/flutter_gemma (Flutter layer). Quex uses `flutter_gemma ^0.13.2` with `GemmaInferenceService` as the abstraction layer over `InferenceChat`.

---

## 1. Core Architecture

### Service Layer
- **`GemmaInferenceService`** (`lib/core/ai/gemma_inference_service.dart`) — thin wrapper over `flutter_gemma`'s `InferenceChat`. Owns session lifecycle, query chunking, and response streaming.
- **`QuexAi`** (`lib/core/ai/quex_ai.dart`) — static facade. Manages single Gemma instance with token-based ownership (`acquireGemmaService` / `releaseGemmaService`). Rule-based fallback when model unavailable.
- **Agent services** (e.g., `WikiAgentService`) — orchestrate multi-turn tool-call loops on top of `GemmaInferenceService`. Never own the Gemma lifecycle — receive `service` as a parameter.
- **State notifiers** (e.g., `WikiActionController`) — Riverpod `StateNotifier` that drives UI state from agent progress. Accept `onLine` callbacks for log output.

### Ownership Pattern
```dart
// In a widget or modal — owns model lifecycle
final Object _gemmaOwnerToken = Object();

@override
void dispose() {
  unawaited(QuexAi.releaseGemmaService(_gemmaOwnerToken));
  super.dispose();
}

Future<void> _run() async {
  final service = await QuexAi.acquireGemmaService(_gemmaOwnerToken);
  // pass service down to agent, never store globally
  await agentService.runIngest(service: service, ...);
}
```

**Rule**: UI widgets acquire/release. Agent services receive `GemmaInferenceService` as a parameter and never call `QuexAi.acquireGemmaService` themselves.

---

## 2. Session Initialization

```dart
await service.createSession(
  systemInstruction: systemInstruction,
  temperature: 0.2,       // low for deterministic agent output
  topK: 1,                // greedy for tool-calling agents
  supportImage: hasImages,
  tools: const [tool1, tool2, ...],
  supportsFunctionCalls: true,
  isThinking: false,      // disable thinking for tool-call agents (saves tokens, faster)
);
```

**`isThinking`**: Set `false` for agents using function calls. Thinking mode adds overhead and is only useful for open-ended reasoning tasks. For wiki/quiz agents: always `false`.

---

## 3. Multimodal Input — CRITICAL ORDER

**Images MUST be added BEFORE text.** This is the pattern from Google AI Edge gallery (`LlmChatModelHelper.kt`): binary chunks (image/audio) first, text last — "for the accurate last token."

```dart
// CORRECT — images first, text after
for (final item in prepared) {
  for (final image in item.images) {
    await service.addImageQuery(image);
  }
}
await service.addTextQuery(prompt);

// WRONG — do not do this
await service.addTextQuery(prompt);
for (final item in prepared) {
  for (final image in item.images) {
    await service.addImageQuery(image); // too late
  }
}
```

### Material Preprocessing
Always use `MaterialPreprocessor.prepare(materials)` before attaching to session:
```dart
final prepared = await MaterialPreprocessor.prepare(materials);
final hasImages = prepared.any((p) => p.images.isNotEmpty);
// → pass hasImages to createSession(supportImage: hasImages)
// → attach prepared[i].images before text prompt
```

`MaterialPreprocessor` handles: text chunking, photo resize to ≤896px JPEG@85%, document skipping, 32-image cap.

---

## 4. Response Streaming

`service.generateResponses()` yields a stream of sealed `ModelResponse` subtypes:

| Type | Field | Behavior |
|------|-------|----------|
| `ThinkingResponse` | `content: String` | Per-token thinking trace. Skip for log output — not meaningful to users. |
| `TextResponse` | `token: String` | Per-token text output. Buffer — do NOT emit per-token to UI lists. |
| `FunctionCallResponse` | `name`, `args` | Complete tool call. Execute and respond. |
| `ParallelFunctionCallResponse` | `calls: List<FunctionCallResponse>` | Multiple simultaneous tool calls. |

### Streaming Loop Pattern
```dart
await for (final response in service.generateResponses()) {
  if (response is gemma.ThinkingResponse) {
    // skip — per-token, not meaningful for logs
  } else if (response is gemma.TextResponse) {
    // skip — per-token, buffer if you need the text
  } else if (response is gemma.FunctionCallResponse) {
    sawToolCall = true;
    final result = await _executeToolCall(response);
    _emitLine(onLine, result['message'] as String);
    if (response.name == 'finish_run') return; // done
  } else if (response is gemma.ParallelFunctionCallResponse) {
    sawToolCall = true;
    for (final call in response.calls) {
      final result = await _executeToolCall(call);
      _emitLine(onLine, result['message'] as String);
    }
  }
}
```

### Token Buffering (if you need text content)
If you need to display streaming text (e.g., chat reply), accumulate into a `StringBuffer` and update a single UI widget — never add per-token to a list:
```dart
final buffer = StringBuffer();
// on each TextResponse token:
buffer.write(response.token);
setState(() => _displayText = buffer.toString()); // single widget updates in place
```

---

## 5. Tool Call Response — CRITICAL

Use `Message.toolResponse()` via `service.addToolResponse()`, NOT raw JSON text via `addTextQuery`. Raw text bypasses the proper tool response protocol in the `InferenceChat` history.

```dart
// CORRECT
await service.addToolResponse(
  toolName: 'write_page',
  response: {'status': 'ok', 'path': 'sources/ch1.md'},
);

// WRONG — do not use for tool results
await service.addTextQuery(
  'Tool results: ${jsonEncode(results)}',
  noTool: true,
);
```

`GemmaInferenceService.addToolResponse` wraps `Message.toolResponse(toolName:, response:)` which sets `MessageType.toolResponse` and encodes the map as JSON — the model sees it correctly as a structured tool result, not a free-form user message.

When multiple tools fire in one turn, send one `addToolResponse` per result:
```dart
for (final result in toolResults) {
  await service.addToolResponse(
    toolName: result['tool'] as String,
    response: result,
  );
}
// then call generateResponses() for next turn
```

---

## 6. Multi-Turn Agent Loop

```dart
for (var turn = 0; turn < maxTurns; turn++) {
  var sawToolCall = false;
  final toolResults = <Map<String, Object?>>[];

  // 1. Generate
  await for (final response in service.generateResponses()) {
    if (response is gemma.FunctionCallResponse) {
      sawToolCall = true;
      final result = await _executeToolCall(response);
      toolResults.add(result);
      if (response.name == 'finish_run') return _buildResult();
    }
    // handle ParallelFunctionCallResponse similarly
  }

  // 2. If no tool call: retry or error
  if (!sawToolCall) {
    retries++;
    if (retries >= 3) throw StateError('Agent stopped without finish_run');
    await service.addTextQuery('Use tools to continue. Call finish_run when done.', noTool: true);
    continue;
  }

  // 3. Feed tool results back for next turn
  for (final result in toolResults) {
    await service.addToolResponse(
      toolName: result['tool'] as String,
      response: result,
    );
  }
}
throw StateError('Agent exceeded step limit');
```

**Max turns**: 24 for wiki agent. Adjust per task complexity.
**`noTool: true`**: Pass on retry/continuation prompts to prevent the model from trying to call tools when you just want it to keep going.

---

## 7. Log Output (onLine) Pattern

Agent services accept `WikiAgentLineCallback? onLine` (`typedef void Function(String line)`). Only emit **meaningful discrete events** — tool call results, phase markers, final summary. Never emit per-token text/thinking.

```dart
// Good log entries — discrete meaningful events
_emitLine(onLine, 'Wrote sources/chapter1.md');
_emitLine(onLine, 'Read concepts/photosynthesis.md');
_emitLine(onLine, result.summary); // final summary

// Never emit
_emitLine(onLine, response.token);    // per-token text
_emitLine(onLine, response.content);  // per-token thinking
```

State notifier adds each `onLine` call as a new entry in `state.lines` → rendered as a terminal-style log list in the modal.

---

## 8. Tool Definition Pattern

```dart
static const _writePageTool = gemma.Tool(
  name: 'write_page',
  description: 'Write or overwrite a wiki page. Use relative paths like sources/chapter1.md.',
  parameters: {
    'path': {'type': 'string', 'description': 'Relative file path'},
    'content': {'type': 'string', 'description': 'Full markdown content'},
  },
);
```

Always include a `finish_run` tool so the agent can signal completion:
```dart
static const _finishTool = gemma.Tool(
  name: 'finish_run',
  description: 'Call when the task is fully complete.',
  parameters: {
    'summary': {'type': 'string', 'description': 'One-sentence summary of what was done'},
  },
);
```

---

## 9. UI Modal Pattern

Agents run inside a full-screen modal (no `barrierDismissible`, `useSafeArea: false`):

```dart
void _openAgentModal(BuildContext context) {
  showDialog(
    context: context,
    barrierDismissible: false,
    useSafeArea: false,
    builder: (_) => MyAgentModal(sessionId: sessionId),
  );
}
```

Modal structure:
- `ConsumerStatefulWidget` — watches agent state provider
- `initState` → acquire Gemma → call notifier action
- `dispose` → release Gemma (always, even if disposed mid-run)
- `ref.listen` on action state → on success: invalidate providers + 600ms delay + pop; on error: snackbar + pop
- UI: close button, pulsing emoji (AnimatedSwitcher → ✅ on complete), status text, terminal log ListView (auto-scroll), indeterminate `LinearProgressIndicator`

---

## 10. Checklist Before Shipping an Agent Feature

- [ ] Images added BEFORE text prompt
- [ ] `isThinking: false` unless explicitly needed
- [ ] Tool results sent via `addToolResponse()`, not `addTextQuery()`  
- [ ] `onLine` only called for discrete events (tool results, summary) — not per-token
- [ ] Gemma ownership token held by the widget/modal, released in `dispose()`
- [ ] `finish_run` tool defined and handled in loop
- [ ] Max turn limit set (24 recommended for wiki-scale tasks)
- [ ] `mounted` check after every `await` before calling `setState`/`Navigator`
- [ ] Agent service tested with `fvm flutter analyze` — zero issues

---

## Key Files

| File | Role |
|------|------|
| `lib/core/ai/gemma_inference_service.dart` | Session management, query chunking, streaming |
| `lib/core/ai/quex_ai.dart` | Singleton Gemma ownership facade |
| `lib/core/ai/material_preprocessor.dart` | Image resize + text chunking for materials |
| `lib/core/wiki/wiki_agent_service.dart` | Reference agent implementation (tool-calling loop) |
| `lib/core/state/wiki_state.dart` | Reference state notifier with onLine → state.lines |
| `lib/features/wiki/wiki_build_modal.dart` | Reference modal (acquire/release + UI pattern) |

## Reference Sources

- [google-ai-edge/gallery](https://github.com/google-ai-edge/gallery) — Android reference: image ordering, agent chat, thinking vs text streaming
- [DenisovAV/flutter_gemma](https://github.com/DenisovAV/flutter_gemma) — Flutter layer: `Message.*`, `ModelResponse` subtypes, `addQueryChunk`
- [On-Device Function Calling](https://developers.googleblog.com/on-device-function-calling-in-google-ai-edge-gallery/) — Tool call state machine reference
