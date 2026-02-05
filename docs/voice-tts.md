# 语音功能 (Voice & TTS)

OpenClaw 支持完整的语音交互功能，包括语音消息收发和实时语音对话。

## 功能概览

| 功能 | 说明 | 平台 |
|-----|------|------|
| **语音消息接收** | 自动转录收到的语音消息 | Telegram, WhatsApp 等 |
| **语音消息发送** | AI 回复转为语音消息发送 | Telegram, WhatsApp 等 |
| **Talk Mode** | 实时语音对话（麦克风+扬声器） | macOS/iOS/Android App |
| **Voice Wake** | 语音唤醒词检测 | macOS/iOS/Android App |

## Telegram/WhatsApp 语音消息

### 工作流程

```
你发语音 ──► 自动转录（Whisper/OpenAI）──► AI 处理 ──► TTS 生成 ──► 发送语音回复
```

Telegram 会显示为原生圆形语音气泡，不是普通音频附件。

### 配置 TTS

编辑配置文件：

```bash
# 推荐方式（自动处理权限）
openclaw-config edit

# 或手动方式
openclaw-shell
sudo nano ~/.openclaw/openclaw.json
```

#### 方案 1: 免费 Edge TTS（推荐新手）

无需 API Key，使用微软 Neural 语音：

```json
{
  "messages": {
    "tts": {
      "auto": "inbound",
      "provider": "edge",
      "edge": {
        "voice": "zh-CN-XiaoxiaoNeural"
      }
    }
  }
}
```

常用中文语音：
- `zh-CN-XiaoxiaoNeural` - 女声（活泼）
- `zh-CN-YunxiNeural` - 男声（自然）
- `zh-CN-YunjianNeural` - 男声（新闻播报风格）

英文语音：
- `en-US-JennyNeural` - 女声
- `en-US-GuyNeural` - 男声

#### 方案 2: ElevenLabs（最高质量）

需要 [ElevenLabs API Key](https://elevenlabs.io/)：

```json
{
  "messages": {
    "tts": {
      "auto": "inbound",
      "provider": "elevenlabs",
      "elevenlabs": {
        "apiKey": "your_elevenlabs_api_key",
        "voiceId": "your_voice_id",
        "modelId": "eleven_multilingual_v2"
      }
    }
  }
}
```

#### 方案 3: OpenAI TTS

需要 [OpenAI API Key](https://platform.openai.com/)：

```json
{
  "messages": {
    "tts": {
      "auto": "inbound",
      "provider": "openai",
      "openai": {
        "apiKey": "your_openai_api_key",
        "model": "gpt-4o-mini-tts",
        "voice": "alloy"
      }
    }
  }
}
```

OpenAI 语音选项：`alloy`, `echo`, `fable`, `onyx`, `nova`, `shimmer`

### TTS 自动模式

| 模式 | 说明 |
|-----|------|
| `off` | 关闭，只发文字 |
| `always` | 所有回复都转语音 |
| `inbound` | **只在收到语音消息后回语音** ✨ 推荐 |
| `tagged` | 只有包含 `[[tts]]` 标签的回复转语音 |

### 聊天命令

在 Telegram/WhatsApp 中直接发送：

```
/tts always      # 开启自动语音回复
/tts inbound     # 只回语音给语音消息
/tts off         # 关闭语音回复
/tts status      # 查看当前状态
/tts audio 你好  # 发送一条语音测试
```

## 语音转录（接收语音）

OpenClaw 自动转录收到的语音消息，支持多种后端：

### 自动检测顺序

1. 本地 CLI（如已安装）：`sherpa-onnx-offline`, `whisper-cli`, `whisper`
2. Gemini CLI
3. 云服务：OpenAI → Groq → Deepgram → Google

### 手动配置

```json
{
  "tools": {
    "media": {
      "audio": {
        "enabled": true,
        "maxBytes": 20971520,
        "models": [
          { "provider": "openai", "model": "gpt-4o-mini-transcribe" }
        ]
      }
    }
  }
}
```

## Talk Mode（实时语音对话）

Talk Mode 是连续语音对话功能，需要麦克风和扬声器。

### 架构说明

```
┌─────────────────────────────────────────────────────────────┐
│                      macOS Host                              │
│  ┌─────────────────┐    ┌─────────────────────────────────┐ │
│  │  OpenClaw macOS │◄──►│        OrbStack VM               │ │
│  │      App        │ WS │  ┌─────────────────────────┐    │ │
│  │                 │    │  │   openclaw-gateway      │    │ │
│  │ - Voice Wake    │    │  │   (systemd service)     │    │ │
│  │ - Talk Mode     │    │  │                         │    │ │
│  │ - 麦克风/扬声器  │    │  │ - AI 模型调用           │    │ │
│  └─────────────────┘    │  │ - ElevenLabs TTS API    │    │ │
│                         │  └─────────────────────────┘    │ │
│                         └─────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

**重要**: OrbStack VM 内没有音频硬件，Talk Mode 需要配合 macOS/iOS/Android App 使用。

### 获取 OpenClaw App

1. 访问 [OpenClaw Releases](https://github.com/openclaw/openclaw/releases)
2. 下载对应平台的 App
3. 配置连接到 Gateway: `ws://openclaw-vm.orb.local:18789`

### Talk Mode 配置

```json
{
  "talk": {
    "voiceId": "elevenlabs_voice_id",
    "modelId": "eleven_v3",
    "apiKey": "elevenlabs_api_key",
    "interruptOnSpeech": true
  }
}
```

## Voice Wake（语音唤醒）

全局唤醒词检测，支持自定义触发词。

### 配置文件

`~/.openclaw/settings/voicewake.json`：

```json
{
  "triggers": ["openclaw", "claude", "computer"],
  "updatedAtMs": 1730000000000
}
```

### 通过 App 编辑

在 macOS/iOS/Android App 的设置中可以直接编辑唤醒词，会自动同步到 Gateway。

## 完整配置示例

```json
{
  "messages": {
    "tts": {
      "auto": "inbound",
      "provider": "elevenlabs",
      "summaryModel": "openai/gpt-4.1-mini",
      "elevenlabs": {
        "apiKey": "your_elevenlabs_api_key",
        "voiceId": "your_voice_id",
        "modelId": "eleven_multilingual_v2",
        "voiceSettings": {
          "stability": 0.5,
          "similarityBoost": 0.75,
          "speed": 1.0
        }
      }
    }
  },
  "tools": {
    "media": {
      "audio": {
        "enabled": true,
        "models": [
          { "provider": "openai", "model": "gpt-4o-mini-transcribe" }
        ]
      }
    }
  },
  "talk": {
    "voiceId": "elevenlabs_voice_id",
    "modelId": "eleven_v3",
    "interruptOnSpeech": true
  }
}
```

## 故障排查

### 语音消息不回复

1. 检查 TTS 是否启用：发送 `/tts status`
2. 检查配置文件语法
3. 检查 API Key 是否正确

### 语音转录失败

```bash
openclaw-shell
# 查看日志
openclaw logs 2>&1 | grep -i audio
```

### Talk Mode 无法使用

确认：
1. 已安装 OpenClaw macOS/iOS/Android App
2. App 已连接到 Gateway
3. 已授予麦克风权限

## 相关文档

- [OpenClaw TTS 官方文档](https://docs.openclaw.ai/tts)
- [OpenClaw Audio 官方文档](https://docs.openclaw.ai/nodes/audio)
- [OpenClaw Talk Mode 官方文档](https://docs.openclaw.ai/nodes/talk)
