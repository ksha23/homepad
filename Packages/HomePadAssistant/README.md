# HomePadAssistant

HomeView's Siri AI, but with any AI provider. This package implements `AssistantService` (installed into `services.assistant`), the generic assistant tools, voice in and out, the Siri-style overlay, the Assistant app and the AI Assistant settings pane.

## Features

- **Providers.** Apple Intelligence on device (Foundation Models), OpenAI, Claude, Gemini, Grok, Meta Muse, Mistral, DeepSeek, Groq, Perplexity, OpenRouter, Ollama and LM Studio. Every provider streams text, calls tools and (where the model can) takes images.
- **Wire formats.** One OpenAI Chat Completions client covers most vendors through presets. OpenAI and xAI use the Responses API, because their newest models only support tool calling there. Claude and Gemini use their native APIs. Apple's model runs its own tool loop, bridged with `DynamicGenerationSchema`.
- **Routing.** A request's own provider, then the person's provider, then the household default, then the fallback order, then any ready provider. If a provider fails before anything was said or done, the next one answers.
- **Conversation engine.** A system prompt with live context (date, time, location and weather from `services.weather`, the recognized person, their "About me", what is on screen, a compact home summary, the tool list), per-person history kept on this iPad, and a tool loop of up to six rounds over `registry.tools`. Personal tools are offered only when `household.isPersonalContentUnlocked`.
- **What is on screen.** The shell puts the open app in `AppServices.visibleAppID`, and the module that owns it describes its screen with a `ScreenContextProvider` on the registry: Recipes the card or the cooking step with its ingredients, or the meal plan's week, Home the accessory or camera full screen with the doors beside it, Calendar the day, Photos the album, and the doorbell over every screen while it rings. When someone asks on this iPad, `ScreenContextReader` turns that into an "On screen" line, and the prompt says that this, these and here mean what is on screen. So "unlock this door" on a camera and "add these ingredients to my shopping list" on a recipe work with the existing tools. Personal summaries, and apps that need recognition, stay out until someone is recognized. Requests from other modules (recipe import, Ask About This) leave the screen out.
- **Generic tools.** `list_devices`, `control_device` (several devices and mixed kinds in one call, for example lights off plus thermostat to 68), `activate_scene`, `get_weather`, `get_time`, `get_calendar`, `add_reminder` (one title or several items, such as a recipe's ingredients), `add_event`, `start_timer`, `list_timers`, `cancel_timer`, `play_music`, `media_control`, `set_volume`, `intercom_announce`, `open_app`, `show_face`.
- **Tools from other modules.** Modules register their own tools, which the engine offers next to the generic ones, for example Personal's `find_device` and `play_sound_on_device` for Find My ("where is everyone's phone", "ping my iPad"), Kitchen's meal plan tools (`get_meal_plan`, `plan_meal`, `remove_planned_meal` and `add_meal_plan_to_groceries`: "what's for dinner Thursday", "put chili on Friday"), Audio's `play_radio` and Smart Home's `home_assistant_service`. Tools marked `requiresRecognizedMember` are offered only while someone is recognized, and refused otherwise.
- **Text tasks for other modules.** A module that wants scanned text read into a structure (Kitchen's recipe import, Camera Lab's flyer events) sends `AssistantRequest.textTask(_:)`, which sets `isSelfContained`, and reads the reply with `services.assistant.answerText(to:timeout:)` (in Core). The provider then gets that text with a two-sentence system prompt (`textTaskSystemPrompt`) and nothing else: no tools, so it cannot act on what it reads, no chat history, and nothing about the household, the person or the screen. The exchange is kept in nobody's history, and nothing is spoken or shown.
- **Confirmations.** Unlocking, opening a garage door or gate, and disarming security ask first ("Unlock the Front Door?"). Answer by tapping, saying yes or no, or nodding or shaking with AirPods (`.headGesture`). Other modules' tools whose names look like unlock, disarm or open garage get the same question.
- **Voice in.** On-device speech to text with SpeechAnalyzer and SpeechTranscriber, falling back to SFSpeechRecognizer with `requiresOnDeviceRecognition`. Audio always comes from `services.microphone`. End of speech is detected from pauses. Push-to-talk, follow-up listening, the shell's swipe-down (`.invokeAssistant`) and the wake phrase all lead to the same flow.
- **Wake phrase.** `CoreSettings.wakePhrase` when `CoreSettings.wakeWordEnabled`. It runs only on a HomePad (`AppRole`), never on the iPhone or Mac companion. It runs only when the microphone is already allowed (it never shows a permission prompt), and pauses during conversations, while the display sleeps with nobody around, while `services.audioSession` holds long-form AirPlay playback, and when the microphone privacy switch is off.
- **Voice out.** Apple voices by default: the best installed system voice (Personal Voice when allowed, then premium, enhanced, default). Natural is an opt-in neural voice (Kokoro-82M on MLX, run on the iPad after a one-time 330 MB download), and OpenAI voices are a third choice. Answers are spoken sentence by sentence while they stream, without the Markdown of their bold facts. Saying "stop" or tapping interrupts. Apple voices speak in their own system audio session, as Siri does. Natural and OpenAI voices play through HomePad's session and hold a `.playback` claim on `services.audioSession`.
- **Announcements.** Other modules post `.speak(text)` (Core's `AssistantEventName.speak`), as Home Assistant's `homepad_speak` does. The assistant says it in the chosen voice with music lowered, as for an answer. While someone is talking to the assistant it is skipped, so it never talks over a request or is heard as one, and the sender shows the text anyway. Quiet Hours are for the sender to check.
- **Overlay.** A glass orb animated by phase, and a glowing edge while listening and working on a request, which fades out once the answer or an error is up, as on HomeView (its view is removed, so it stops redrawing). The live transcript, the answer in large type that adapts to `\.proximity` (its first words, or an error, replace the thinking line with a fade and a short rise, and later words stream in unanimated), cards (calendar, weather, accessories, timers, images), confirmation prompts, a follow-up microphone and a close button. Night mode uses `nightModeAware()`. The overlay stays dark in either appearance (`.environment(\.colorScheme, .dark)` on itself), since it floats over whatever is on screen.
- **Answer style.** As on HomeView, the one to three facts that answer the question are in bold. When the answer shows in the overlay or the Assistant app, the prompt asks for Markdown bold on those facts and nothing else. `AnswerMarkdown` reads it with inline-only parsing, so stray Markdown never becomes a heading or a list, and a bold run still streaming in shows no asterisks. Speech, Siri and Handoff get plain words. Sources show as small chips under the answer: the first by its site (wikipedia.org), then "+N" with the rest in a menu, each opening its link.
- **Assistant app.** It follows the app's light or dark appearance, and so do the answer cards in its chat: calendar rows deepen their color in Light and lighten it in Dark, and accessory tiles show their state in the primary color until lit. Chat history for the current person, typing with the onscreen keyboard, photo attachments, a provider switcher, and settings for admins. The history is already kept per person (`ConversationStore`) and the chat opens at its latest answer. The app also reopens on each recognized person's tab (`AssistantAppState.tab`, an `@AppState` kept per member), Settings only for someone who may change them. A request for a tab (`requestedAppTab`, `-HomePadAssistantTab`) wins. A half-typed question is not kept.
- **No keys.** With no provider ready, the overlay and the app show a friendly "Add an AI Provider" state with a Set Up button.

## Structure

```
Sources/HomePadAssistant/
  AssistantModule.swift        Registers the service, tools, overlay, app and settings pane
  Models/                      ChatMessage, ChatRequest, ProviderDescriptor, AssistantError
  Networking/                  SSE parser, HTTP transport, stream runner, tool call accumulator
  Providers/                   ChatProvider, the shared HTTP client shape, catalog, factory, tester
    OpenAICompatible/          Chat Completions and Responses encoders, decoders, clients
    Anthropic/ Gemini/ Apple/  Native clients, Foundation Models bridge and schema converter
  Conversation/                Engine (tool loop, failover), router, history, system prompt,
                               what is on screen, answer Markdown
  Tools/                       Toolset, invoker, arguments, cards, and the generic tools
    Home/                      Target resolver, command mapper, executor, named colors
  Confirmation/                ConfirmationCenter, sensitive action policy, yes or no reader
  Voice/                       Wake phrase monitor
    Input/                     Transcription engines, end of speech, barge-in, permissions
    Output/                    Speech controller, Apple and OpenAI voices, sentence chunker
      Natural/                 The Natural voice: Kokoro engine, model download, playback
  Service/                     AssistantRuntime (the AssistantService) and its session state
  Settings/                    Setting keys, per-person preferences, provider store
  Views/Overlay/ Cards/ App/ Settings/
  Views/Components/            Orb, edge glow and their palette (the assistant's own look), photo thumbnail
  Demo/                        Launch arguments for screenshots
  Resources/                   KokoroVoices.npz, the Natural voice's bundled voices
```

Buttons, pills and settings icons come from HomePadUI (`GlassIconButton`, `CloseButton`, `GlassPill`, `SettingsIcon`). The orb and edge glow are the assistant's signature, so they stay here.

## Settings

Settings, AI Assistant (pane id `assistant`, admins only) and the Assistant app's settings tab show the same grouped Form.

- **Providers.** On or off, API key (keychain account `assistant.<providerID>`), server address (prominent for Ollama and LM Studio, under Advanced for the rest), model from a suggested list, the live model list, or any typed ID, and a Test button.
- **Choosing a Provider.** Default provider and fallback order.
- **People.** Per person: provider, model, personality and a short "About me" (up to 240 characters, sent only when that person is recognized). Stored in `member.preferences` under `assistantProvider`, `assistantModel`, `assistantPersonality` and `assistantAboutMe`.
- **Personality.** Concise, Friendly or Detailed.
- **Voice.** Speak answers, Apple, Natural or OpenAI voices, the voice, speaking rate (Slower, Normal, Faster), Personal Voice, the Natural voice download and a sample.
- **Listening.** Wake phrase on or off, the phrase (three reliable choices), how long to wait after you speak, and follow-up listening.
- **History.** Clear the current person's conversation history.

Setting keys are under `assistant.*` (see `Settings/AssistantSettings.swift`).

## Model defaults (checked October 2026)

| Provider | Default | Also suggested |
| --- | --- | --- |
| OpenAI (Responses) | gpt-6.1-sol | gpt-6-astra, gpt-6-luna |
| Claude | claude-haiku-5-5 | claude-sonnet-5-5, claude-opus-5-5, claude-fable-5-1 |
| Gemini | gemini-3.8-flash | gemini-4-argon, gemini-3.5-flash-lite |
| Grok (Responses) | grok-4.7 | grok-4.3 |
| Meta Muse | muse-spark-1.3 | muse-wonder-1.0 |
| Mistral | mistral-medium-latest | mistral-small-latest, mistral-large-latest |
| DeepSeek | deepseek-v4-pro | deepseek-flash |
| Groq | openai/gpt-oss-120b | openai/gpt-oss-20b, llama-3.1-8b-instant |
| Perplexity | sonar-pro | sonar |
| OpenRouter | openrouter/auto | live list |

Meta Muse uses the Meta Model API, a public preview that is OpenAI compatible at `api.meta.ai/v1`. Availability varies by country.

Request details worth knowing:

- Claude requests use effort `low` for quick spoken answers, `eager_input_streaming` on tools (arguments are validated before anything runs), and server-side `fallbacks: "default"` on models that support it. Thinking blocks from a tool loop are sent back unchanged. History between turns is plain text, so edited system prompts never invalidate earlier thinking.
- Responses API requests are stateless (`store: false`). OpenAI also returns encrypted reasoning so tool loops keep their reasoning.
- Gemini parts are echoed verbatim inside a tool loop, which keeps the thought signatures Gemini 3 and later require. Gemini 3 and later get `thinkingLevel: low`.
- DeepSeek's `reasoning_content` is sent back during tool loops, as its API requires.
- Perplexity has no tool calling. Its citations become link cards.

## Launch arguments

```
-HomePadAssistantDemo listening|thinking|answer|calendar|home|weather|confirm|setup|error|chat
-HomePadOpenApp assistant -HomePadAssistantTab chat|settings
-HomePadOpenApp assistant -HomePadAssistantTab settings -HomePadAssistantProvider <id>
-HomePadVoiceReport YES
```

`-HomePadAssistantDemo` shows the overlay in that state (`chat` fills the Assistant app's history). `-HomePadVoiceReport` writes every voice the app can see to Documents/voice-report.txt. None of these call a provider.

## Tests

Swift Testing, 93 tests, no network: SSE parsing and decoding for each wire format (Chat Completions, Responses, Anthropic, Gemini), tool call accumulation from streamed chunks, request bodies per provider including tools and images, provider endpoints and headers through a mock transport, the device command mapping, target resolution and the multi-device executor (against Core's demo smart home), the tool loop with failover and invalid JSON, routing order, tool selection, wake phrase matching, end of speech, sentence chunking, yes or no, barge-in, dates, history, the system prompt, what is on screen and who may hear it, bold key facts and their plain spoken form, source chip names, several reminders in one call, schema conversion for the on-device model and the Natural voice's bundled voices, text splitting and download check.

## Dependencies

The provider clients use no SDK. They are thin `URLSession` code. SDKs such as MacPaw/OpenAI were considered, but HomePad needs one tool loop across five wire formats with provider data echoed verbatim (Claude thinking blocks, Gemini thought signatures, OpenAI encrypted reasoning, DeepSeek reasoning), which no single SDK covers. The tested clients are small, so adding SDKs would not remove much code.

The Natural voice is the one exception: Kokoro-82M runs on MLX through `mlx-swift` and `MLXUtilsLibrary` (pinned in `Package.swift`) and the vendored KokoroSwift and MisakiSwift in `../ThirdParty`. None of it loads unless someone picks the Natural voice.

## Needs real-device testing

- Speech recognition with SpeechAnalyzer and the SFSpeechRecognizer fallback, end of speech timing, and the first-use model download.
- The wake phrase: accuracy, false triggers, power use, and the pause conditions.
- Barge-in: whether "stop" is heard over HomePad's own voice without voice processing on the shared microphone.
- Audio session handoffs between speaking, listening and AirPlay music.
- Personal Voice authorization and premium voices.
- AirPods nod and shake confirmations (needs the Presence module's head gesture events).
- Apple Intelligence on iPads that support it (tool calling quality on the small model, image input on iPadOS 27).
- Every cloud provider with a real key, including the live model lists and the Test button.
- How each model follows the bold rule (only the key facts), and acting on what is on screen: "unlock this door" on a camera, "add these ingredients to my shopping list" on a recipe card.

## Known gaps

- Image generation is not included. `ImageCreator` is deprecated in iPadOS 27 in favor of the interactive Image Playground sheet, which does not fit a tool call.
- Perplexity uses its Chat Completions path, which Perplexity converts to its Agent API. Moving to the Agent API would add tools and images.
- History is per iPad and does not sync with iCloud.
- A module's text task runs through the same runtime as a spoken request, so it stops an answer in progress, as module requests always have.
- Wake phrase detection uses a speech recognizer, not a dedicated keyword model, so it costs more power than a hardware wake word.