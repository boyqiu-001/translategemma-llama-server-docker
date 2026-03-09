# TranslateGemma Unified Migration Plan

## Goal

Unify text and image translation onto a single stable protocol path based on `llama-server` `/completion`, avoiding the current incompatibility between:

- `llama.cpp` OpenAI-style multimodal chat request handling
- TranslateGemma GGUF embedded Jinja template expectations

This migration is intended to cover three local repositories:

- `D:\git\gitlab\translategemma-llama-server-docker`
- `D:\git\gitlab\WhisperLive-TRT-Gemma`
- `D:\git\gitlab\VoiceLinkServer1`

## Root Cause Summary

Current image translation failures are caused by a protocol mismatch:

1. `llama-server /v1/chat/completions` accepts standard multimodal content such as `image_url`.
2. Internally, `llama.cpp` rewrites image parts into `media_marker` placeholders.
3. The TranslateGemma GGUF embedded Jinja template expects a single user `content` item with:
   - `type: "text"` or `type: "image"`
   - `source_lang_code`
   - `target_lang_code`
   - direct text/image payload fields
4. As a result:
   - sending `type = "image"` is rejected by the server parser
   - sending `type = "image_url"` passes the parser but fails in the model template

Because of this, continuing to rely on `/v1/chat/completions` + Jinja for both text and image translation is fragile.

## Recommended Architecture

### Single Service Protocol

Move both text translation and image translation to:

- endpoint: `/completion`
- prompt construction: manual prompt builder
- multimodal image input: `multimodal_data`
- server mode: disable Jinja-dependent chat-template path for runtime requests

### Why This Path

Benefits:

- avoids embedded Jinja incompatibility
- supports text and image through one protocol
- removes dependency on `chat_template_kwargs`
- keeps client behavior explicit and debuggable
- avoids maintaining a custom external Jinja template unless later needed

Trade-offs:

- clients must stop using `/v1/chat/completions` for TranslateGemma
- prompt construction logic moves into client code
- streaming behavior may need to be revalidated per client

## Service-Side Changes

Repository:

- `D:\git\gitlab\translategemma-llama-server-docker`

Target changes:

1. Make Jinja usage configurable instead of always forcing `--jinja`.
2. Default runtime path toward `/completion`-friendly usage.
3. Preserve the ability to re-enable old behavior as a rollback path.

### Proposed runtime behavior

Recommended startup direction:

- disable Jinja for this deployment path
- keep multimodal enabled via `mmproj`
- allow extra args for tuning

Suggested runtime flags:

- `--no-jinja`
- `--swa-full`

Optional compatibility switch:

- keep a config option to re-enable `--jinja` temporarily if rollback is needed

### Files expected to change

- `D:\git\gitlab\translategemma-llama-server-docker\entrypoint.sh`
- `D:\git\gitlab\translategemma-llama-server-docker\compose.yaml`
- optionally `README.md`
- optionally `README.zh-CN.md`

## Client-Side Changes

### 1) WhisperLive-TRT-Gemma

Repository:

- `D:\git\gitlab\WhisperLive-TRT-Gemma`

Current behavior:

- text translation uses `POST /v1/chat/completions`
- payload uses `messages` + `chat_template_kwargs`
- optional streaming also assumes chat-completions behavior

Migration target:

- replace TranslateGemma text requests with `/completion`
- introduce a shared prompt builder for TranslateGemma text translation
- re-evaluate streaming behavior after switching endpoints

Expected files to update:

- `D:\git\gitlab\WhisperLive-TRT-Gemma\whisper_live\backend\translation_backend.py`
- possibly docs mentioning `/v1/chat/completions`

### 2) VoiceLinkServer1

Repository:

- `D:\git\gitlab\VoiceLinkServer1`

Current behavior:

- Gemma translation path uses `POST /v1/chat/completions`
- payload uses `messages` + `chat_template_kwargs`
- config declares the current mode as `openai`

Migration target:

- switch Gemma path to `/completion`
- replace OpenAI-style payload builder with completion payload builder
- support a configuration switch such as:
  - `completion`
  - `openai`
  - `auto`
- default to `completion`

Expected files to update:

- `D:\git\gitlab\VoiceLinkServer1\src\core\gemma_translate_service.py`
- `D:\git\gitlab\VoiceLinkServer1\src\core\config.py`
- possibly `README.md`

## Proposed Payload Strategy

### Text translation

Use `/completion` with a manual TranslateGemma-style prompt.

Prompt should include:

- source language name and code
- target language name and code
- instruction to output translation only
- original input text

### Image translation

Use `/completion` with:

- `prompt_string` containing a media marker such as `<__media__>`
- `multimodal_data` containing image base64

This keeps image handling aligned with `llama.cpp` multimodal completion support.

## Rollout Plan

### Phase 1: Documentation and Git Baseline

1. Save this migration plan.
2. Record Git state for all three repositories.
3. Confirm changed/untracked files before edits.

### Phase 2: Service Update

1. Update `translategemma-llama-server-docker` runtime flags.
2. Add configuration for Jinja on/off behavior.
3. Verify the service still loads model and `mmproj`.

### Phase 3: Client Migration

1. Update `WhisperLive-TRT-Gemma` to `/completion` for text translation.
2. Update `VoiceLinkServer1` to `/completion` for text translation.
3. Keep a rollback config path for older `openai` mode until validation completes.

### Phase 4: Verification

Verify at minimum:

- text translation request succeeds from `WhisperLive-TRT-Gemma`
- text translation request succeeds from `VoiceLinkServer1`
- direct image translation request succeeds against TranslateGemma service
- fallback behavior remains acceptable if Gemma translation fails

## Rollback Strategy

If migration breaks text translation unexpectedly:

1. Re-enable the previous runtime mode on the service.
2. Switch client config back to `openai` mode.
3. Keep image testing isolated until text path is stable again.

## Notes

- This plan intentionally prioritizes protocol stability over strict OpenAI chat compatibility.
- The main risk is client behavior drift after moving from chat payloads to prompt-based completion payloads.
- The main benefit is eliminating the currently observed image-translation deadlock caused by server-template incompatibility.
