# v1 API（推荐使用）
## 健康检查
curl "http://localhost:8080/api/v1/health"
## 获取配置信息
curl "http://localhost:8080/api/v1/config"

## 获取语音列表
### 方式 1：Bearer Token 认证（推荐）
curl -H "Authorization: Bearer YOUR_TTS_API_KEY" \
  "http://localhost:8080/voices"

### 方式 2：Query 参数认证
curl "http://localhost:8080/voices?api_key=YOUR_TTS_API_KEY"

## 文本转语音

###方式 1：GET 请求 + Query 参数认证
curl "http://localhost:8080/api/v1/tts?text=你好，世界&voice=zh-CN-XiaoxiaoNeural&api_key=YOUR_TTS_API_KEY" \
  -o output.mp3

### 方式 2：POST 请求 + Bearer Token 认证（推荐）
curl -X POST "http://localhost:8080/api/v1/tts" \
  -H "Authorization: Bearer YOUR_TTS_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "text": "你好，世界",
    "voice": "zh-CN-XiaoxiaoNeural",
    "rate": 20,
    "pitch": 10,
    "style": "cheerful"
  }' -o output.mp3

### 方式 3：POST 请求 + 请求体中的 api_key
curl -X POST "http://localhost:8080/api/v1/tts" \
  -H "Content-Type: application/json" \
  -d '{
    "text": "你好，世界",
    "voice": "zh-CN-XiaoxiaoNeural",
    "rate": 20,
    "pitch": 10,
    "style": "cheerful",
    "api_key": "YOUR_TTS_API_KEY"
  }' -o output.mp3
参数说明：

text: 文本内容
voice: 语音风格
rate: 语速，范围 -100 到 100
pitch: 语调，范围 -100 到 100
style: 情感风格，可选值为 sad, angry, cheerful, neutral
认证说明： 所有 TTS 相关接口支持以下三种认证方式：

Bearer Token (推荐): Authorization: Bearer YOUR_TTS_API_KEY
Query 参数: ?api_key=YOUR_TTS_API_KEY
请求体参数: JSON 中包含 "api_key": "YOUR_TTS_API_KEY"
兼容性 API
原版 TTS API
## 无认证（如果配置了 API Key 则需要认证）
curl "http://localhost:8080/tts?t=你好，世界&v=zh-CN-XiaoxiaoNeural" -o output.mp3

## 使用 Query 参数认证
curl "http://localhost:8080/tts?t=你好，世界&v=zh-CN-XiaoxiaoNeural&api_key=YOUR_TTS_API_KEY" -o output.mp3
OpenAI 兼容 API
### 方式 1：Bearer Token 认证（推荐）
curl -X POST "http://localhost:8080/v1/audio/speech" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer YOUR_TTS_API_KEY" \
  -d '{
    "model": "tts-1",
    "input": "你好，世界！",
    "voice": "zh-CN-XiaoxiaoNeural",
    "speed": 0.5
  }' -o output.mp3

### 方式 2：请求体中包含 api_key
curl -X POST "http://localhost:8080/v1/audio/speech" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "tts-1",
    "input": "你好，世界！",
    "voice": "zh-CN-XiaoxiaoNeural",
    "speed": 0.5,
    "api_key": "YOUR_TTS_API_KEY"
  }' -o output.mp3
参数说明：

model: 模型名称，对应情感风格
input: 文本内容
voice: 语音风格
speed: 语速，0.0 到 2.0
api_key: API 密钥（可选，也可通过 Bearer Token 或 Query 参数提供）
认证说明： 支持 Bearer Token、Query 参数或请求体中的 api_key 参数进行认证