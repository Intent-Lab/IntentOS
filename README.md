# Intent OS

An open-source, agent-native voice-and-vision framework. Turn any audio/visual device -- earbuds, smart glasses, pendants, phones -- into an always-on AI companion that can perceive, understand, and act on your behalf.

Built by [Intentlabs](https://github.com/Intent-Lab). Evolved from [VisionClaw](https://github.com/Intent-Lab/VisionClaw).

**Supported platforms:** iOS (iPhone) and Android

---

## The Problem

Today's voice AI apps (ChatGPT Voice, Gemini Live, Sesame) are **conversational but not agentic**. They can talk to you, but they cannot act for you. When they try to do complex tasks (search, multi-step workflows, API calls), they go silent for 10-30 seconds -- broken UX.

Meanwhile, agent frameworks (OpenClaw, Manus, Claude Code) can execute complex tasks but have no real-time voice interface.

**No consumer product today combines real-time voice conversation with general-purpose agent execution.** Intent OS fills this gap.

---

## Core Architecture: Dual-Agent System

Intent OS separates real-time voice interaction from asynchronous task execution, allowing both to run simultaneously without blocking each other.

```
                         +-----------------------------+
                         |       INTENT OS CORE        |
                         |                             |
 User ---- Audio ------> |  +---------------------+   |
 Device    Stream        |  |   VOICE AGENT        |   |
 (glasses,               |  |   (synchronous)      |   |
  earbuds,               |  |                      |   |
  pendant,               |  |   Real-time voice    |   |
  phone)                 |  |   conversation.      |   |
           <-- Audio --- |  |   Always responsive. |   |
               Response  |  |   Never blocked.     |   |
                         |  +----------+-----------+   |
                         |             |               |
                         |     delegates tasks         |
                         |             |               |
                         |  +----------v-----------+   |
                         |  |   ACTION AGENT        |   |
                         |  |   (asynchronous)      |   |
 User ---- Video ------> |  |                      |   |
 Device    Frames        |  |   Web search, API    |   |
 (camera   (~1fps)       |  |   calls, messaging,  |   |
  on                     |  |   smart home, etc.   |   |
  glasses,               |  |                      |   |
  phone)                 |  |   Reports results    |   |
                         |  |   back to Voice      |   |
                         |  |   Agent when ready.  |   |
                         |  +----------------------+   |
                         |                             |
                         +-----------------------------+
```

**Voice Agent** -- maintains real-time bidirectional audio with the user. Sub-second latency. Never blocked by tasks. Powered by Gemini Live API or OpenAI Realtime API.

**Action Agent** -- receives task delegations from Voice Agent. Executes complex, multi-step tasks in the background via [OpenClaw](https://github.com/nichochar/openclaw) (56+ skills: web search, messaging, smart home, notes, reminders, etc.). Reports results back to Voice Agent when ready.

**Example flow:**
1. User: "Find me the best ramen places in SF that are open late"
2. Voice Agent: "Sure, let me search for late-night ramen spots."
3. Action Agent begins web search in background
4. User: "Oh also, I want somewhere with vegetarian options"
5. Voice Agent: "Got it, I'll filter for vegetarian-friendly places too."
6. Action Agent returns results
7. Voice Agent speaks the answer conversationally

The user is never left in silence. The agent is never limited to shallow answers.

---

## Supported Hardware

Intent OS is device-agnostic. It connects to any audio I/O device:

| Device | Audio In | Audio Out | Video In | Status |
|--------|----------|-----------|----------|--------|
| Phone (built-in) | Mic | Speaker | Camera | Working |
| AirPods / earbuds | Mic | Speaker | -- | Working |
| Meta Ray-Ban glasses | Mic | Speaker | Camera (via DAT SDK) | Working |
| Any Bluetooth audio | Mic | Speaker | -- | Working |
| Sesame glasses | Mic | Speaker | Camera | Planned |
| Apple glasses | Mic | Speaker | Camera | Planned |
| Pendant devices | Mic | Speaker | Camera | Planned |

## Supported Voice Models

Intent OS is model-agnostic:

| Provider | Model | Status |
|----------|-------|--------|
| Google | Gemini 2.0 Flash (Live API) | Working |
| OpenAI | GPT-4o Realtime API | Planned |

---

## Quick Start (iOS)

### 1. Clone and open

```bash
git clone https://github.com/Intent-Lab/IntentOS.git
cd IntentOS/samples/CameraAccess
open CameraAccess.xcodeproj
```

### 2. Add your secrets

```bash
cp CameraAccess/Secrets.swift.example CameraAccess/Secrets.swift
```

Edit `Secrets.swift` with your [Gemini API key](https://aistudio.google.com/apikey) (required) and optional OpenClaw/WebRTC config.

### 3. Build and run

Select your iPhone as the target device and hit Run (Cmd+R).

### 4. Try it out

**Without glasses (iPhone mode):**
1. Tap **"Start on iPhone"** -- uses your iPhone's back camera
2. Tap the **AI button** to start a voice session
3. Talk to the AI -- it can see through your iPhone camera and execute tasks

**With Meta Ray-Ban glasses:**

First, enable Developer Mode in the Meta AI app:

1. Open the **Meta AI** app on your iPhone
2. Go to **Settings** (gear icon, bottom left)
3. Tap **App Info**
4. Tap the **App version** number **5 times** -- this unlocks Developer Mode
5. Go back to Settings -- you'll now see a **Developer Mode** toggle. Turn it on.

Then in the app:
1. Tap **"Start Streaming"**
2. Tap the **AI button** for voice + vision conversation

---

## Quick Start (Android)

### 1. Clone and open

```bash
git clone https://github.com/Intent-Lab/IntentOS.git
```

Open `samples/CameraAccessAndroid/` in Android Studio.

### 2. Configure GitHub Packages (DAT SDK)

The Meta DAT Android SDK is distributed via GitHub Packages. You need a GitHub Personal Access Token with `read:packages` scope.

1. Go to [GitHub > Settings > Developer Settings > Personal Access Tokens](https://github.com/settings/tokens) and create a **classic** token with `read:packages` scope
2. In `samples/CameraAccessAndroid/local.properties`, add:

```properties
github_token=YOUR_GITHUB_TOKEN
```

### 3. Add your secrets

```bash
cd samples/CameraAccessAndroid/app/src/main/java/com/meta/wearable/dat/externalsampleapps/cameraaccess/
cp Secrets.kt.example Secrets.kt
```

Edit `Secrets.kt` with your [Gemini API key](https://aistudio.google.com/apikey) (required) and optional OpenClaw/WebRTC config.

### 4. Build and run

1. Let Gradle sync in Android Studio
2. Select your Android phone as the target device
3. Click Run (Shift+F10)

### 5. Try it out

**Without glasses (Phone mode):**
1. Tap **"Start on Phone"** -- uses your phone's back camera
2. Tap the **AI button** to start a voice session
3. Talk to the AI -- it can see through your phone camera and execute tasks

**With Meta Ray-Ban glasses:**

Enable Developer Mode in the Meta AI app (same steps as iOS above), then:
1. Tap **"Start Streaming"** in the app
2. Tap the **AI button** for voice + vision conversation

---

## Setup: OpenClaw (Optional)

[OpenClaw](https://github.com/nichochar/openclaw) gives Intent OS the ability to take real-world actions: send messages, search the web, manage lists, control smart home devices, and more. Without it, the AI is voice + vision only (no task execution).

### 1. Install and configure OpenClaw

Follow the [OpenClaw setup guide](https://github.com/nichochar/openclaw). Make sure the gateway is enabled:

In `~/.openclaw/openclaw.json`:

```json
{
  "gateway": {
    "port": 18789,
    "bind": "lan",
    "auth": {
      "mode": "token",
      "token": "your-gateway-token-here"
    },
    "http": {
      "endpoints": {
        "chatCompletions": { "enabled": true }
      }
    }
  }
}
```

### 2. Configure the app

**iOS** -- In `Secrets.swift`:
```swift
static let openClawHost = "http://Your-Mac.local"
static let openClawPort = 18789
static let openClawGatewayToken = "your-gateway-token-here"
```

**Android** -- In `Secrets.kt`:
```kotlin
const val openClawHost = "http://Your-Mac.local"
const val openClawPort = 18789
const val openClawGatewayToken = "your-gateway-token-here"
```

Both iOS and Android also have an in-app Settings screen where you can change these values at runtime.

### 3. Start the gateway

```bash
openclaw gateway restart
```

---

## Architecture

### Project Structure (iOS)

```
samples/CameraAccess/CameraAccess/
  Core/                              # Dual-agent framework
    Protocols/
      VoiceModelProvider.swift         # Abstract voice model interface
      AgentProtocol.swift              # AgentTask, AgentResult types
    Models/
      GeminiLiveProvider.swift         # Gemini Live API adapter
    Agents/
      VoiceAgent.swift                 # Real-time voice session manager
      ActionAgent.swift                # Async task executor (OpenClaw)
      AgentCoordinator.swift           # Dual-agent orchestrator

  Gemini/                            # Voice model infrastructure
    GeminiLiveService.swift            # WebSocket client for Gemini Live API
    AudioManager.swift                 # Mic capture (PCM 16kHz) + playback (PCM 24kHz)
    GeminiSessionViewModel.swift       # Session lifecycle (delegates to AgentCoordinator)
    GeminiConfig.swift                 # API keys, model config, system prompt

  OpenClaw/                          # Task execution
    OpenClawBridge.swift               # HTTP client for OpenClaw gateway
    ToolCallRouter.swift               # Tool call routing
    ToolCallModels.swift               # Tool declarations, data types

  iPhone/                            # Phone camera fallback
    IPhoneCameraManager.swift

  WebRTC/                            # Live streaming (glasses POV to browser)
    WebRTCClient.swift
    SignalingClient.swift

  Settings/
    SettingsManager.swift
    SettingsView.swift
```

### Audio Pipeline

- **Input**: Mic -> AudioManager (PCM Int16, 16kHz mono, 100ms chunks) -> Voice Model WebSocket
- **Output**: Voice Model WebSocket -> AudioManager playback queue -> Speaker
- **Echo cancellation**: Aggressive AEC (`voiceChat`) when speaker is on phone; mild AEC (`videoChat`) when using glasses
- **Mic muting**: Automatically mutes mic while AI speaks when speaker + mic are co-located

### Tool Calling (Dual-Agent Flow)

1. User says "Add eggs to my shopping list"
2. Voice Agent acknowledges: "Sure, adding that now"
3. Voice Agent delegates `AgentTask` to Action Agent via `AgentCoordinator`
4. Action Agent sends HTTP POST to OpenClaw gateway
5. OpenClaw executes the task
6. Action Agent returns `AgentResult` to coordinator
7. Coordinator delivers result back to Voice Agent
8. Voice Agent speaks the confirmation

The Voice Agent remains responsive throughout -- the user can continue talking while tasks execute.

---

## Roadmap

### Phase 1: Voice-First Agentic Layer (current)
- [x] Dual-agent architecture (Voice Agent + Action Agent)
- [x] VoiceModelProvider protocol (model-agnostic)
- [x] Gemini Live provider
- [x] OpenClaw integration for task execution
- [x] iOS and Android apps
- [ ] OpenAI Realtime provider
- [ ] Device provider abstraction

### Phase 2: Visual Agentic Layer
- [ ] Camera-based intent inference
- [ ] Proactive assistance (auto-translate foreign text, surface contextual info)
- [ ] Cross-frame memory ("What was that sign I saw 2 minutes ago?")
- [ ] Gaze-based intent prediction (with eye-tracking hardware)

---

## Requirements

### iOS
- iOS 17.0+
- Xcode 15.0+
- Gemini API key ([get one free](https://aistudio.google.com/apikey))
- Meta Ray-Ban glasses (optional -- use iPhone mode for testing)
- OpenClaw on your Mac (optional -- for task execution)

### Android
- Android 14+ (API 34+)
- Android Studio Ladybug or newer
- GitHub account with `read:packages` token (for DAT SDK)
- Gemini API key ([get one free](https://aistudio.google.com/apikey))
- Meta Ray-Ban glasses (optional -- use Phone mode for testing)
- OpenClaw on your Mac (optional -- for task execution)

---

## Troubleshooting

**AI doesn't hear me** -- Check that microphone permission is granted. Speak clearly and at normal volume.

**OpenClaw connection timeout** -- Make sure your phone and Mac are on the same Wi-Fi network, the gateway is running (`openclaw gateway restart`), and the hostname matches your Mac's Bonjour name.

**"Gemini API key not configured"** -- Add your API key in Secrets.swift/Secrets.kt or in the in-app Settings.

**Echo/feedback in iPhone mode** -- The app mutes the mic while the AI is speaking. If you still hear echo, try turning down the volume.

**Android: Gradle sync fails with 401** -- Your GitHub token is missing or doesn't have `read:packages` scope. Check `local.properties`. Generate a new token at [github.com/settings/tokens](https://github.com/settings/tokens).

For DAT SDK issues, see the [developer documentation](https://wearables.developer.meta.com/docs/develop/) or the [discussions forum](https://github.com/facebook/meta-wearables-dat-ios/discussions).

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

This source code is licensed under the license found in the [LICENSE](LICENSE) file in the root directory of this source tree.
