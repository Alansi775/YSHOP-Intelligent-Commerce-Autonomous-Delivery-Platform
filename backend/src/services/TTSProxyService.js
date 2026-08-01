// TTSProxyService.js — server-side proxy for text-to-speech synthesis.
//
// The client (Flutter/Swift) sends text + voice profile here; the actual
// provider key lives only in this process's environment and is never sent
// to any client, so it can't be extracted from a public web build or a
// decompiled app binary.
import logger from '../config/logger.js';

const TTS_API_KEY = process.env.YSHOP_TTS_API_KEY;
const TTS_BASE_URL = 'https://api.elevenlabs.io/v1';

export function isTTSAvailable() {
  return Boolean(TTS_API_KEY);
}

export async function synthesizeSpeech({ voiceId, text, modelId, voiceSettings }) {
  if (!TTS_API_KEY) {
    throw new Error('TTS not configured on server');
  }

  const response = await fetch(`${TTS_BASE_URL}/text-to-speech/${voiceId}`, {
    method: 'POST',
    headers: {
      'xi-api-key': TTS_API_KEY,
      'Content-Type': 'application/json',
      Accept: 'audio/mpeg',
    },
    body: JSON.stringify({
      text,
      model_id: modelId || 'eleven_turbo_v2_5',
      voice_settings: voiceSettings,
    }),
  });

  if (!response.ok) {
    const body = await response.text().catch(() => '');
    logger.warn(`[TTSProxy] provider returned ${response.status}: ${body.slice(0, 200)}`);
    const err = new Error(`TTS provider error ${response.status}`);
    err.status = response.status;
    throw err;
  }

  const arrayBuffer = await response.arrayBuffer();
  return Buffer.from(arrayBuffer);
}
