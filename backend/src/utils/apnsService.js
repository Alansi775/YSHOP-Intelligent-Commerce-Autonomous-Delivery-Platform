import https from 'https';
import jwt from 'jsonwebtoken';
import logger from '../config/logger.js';

// APNs configuration — set these in your .env file:
//   APNS_KEY_ID       = your 10-char key ID from Apple Developer Portal
//   APNS_TEAM_ID      = your 10-char Team ID from Apple Developer Portal
//   APNS_PRIVATE_KEY  = contents of the .p8 file (newlines as \n)
//   APNS_BUNDLE_ID    = com.yourteam.YShop  (must match Xcode bundle ID)
//   APNS_PRODUCTION   = false (use true only for App Store builds)

const KEY_ID     = process.env.APNS_KEY_ID;
const TEAM_ID    = process.env.APNS_TEAM_ID;
const PRIVATE_KEY = process.env.APNS_PRIVATE_KEY?.replace(/\\n/g, '\n');
const BUNDLE_ID  = process.env.APNS_BUNDLE_ID;
const IS_PROD    = process.env.APNS_PRODUCTION === 'true';

const APNS_HOST = IS_PROD
  ? 'api.push.apple.com'
  : 'api.sandbox.push.apple.com';

let _cachedToken = null;
let _tokenExpiresAt = 0;

function getJWT() {
  const now = Math.floor(Date.now() / 1000);
  if (_cachedToken && now < _tokenExpiresAt - 60) return _cachedToken;

  _cachedToken = jwt.sign({ iss: TEAM_ID, iat: now }, PRIVATE_KEY, {
    algorithm: 'ES256',
    header: { alg: 'ES256', kid: KEY_ID },
  });
  _tokenExpiresAt = now + 3600;
  return _cachedToken;
}

async function sendAPNs(deviceToken, payload, apnsTopic) {
  if (!KEY_ID || !TEAM_ID || !PRIVATE_KEY || !BUNDLE_ID) {
    logger.warn('[APNs] Missing credentials — skipping push');
    return;
  }

  const body = JSON.stringify(payload);
  const topic = apnsTopic ?? `${BUNDLE_ID}.push-type.liveactivity`;

  return new Promise((resolve, reject) => {
    const req = https.request(
      {
        host: APNS_HOST,
        port: 443,
        path: `/3/device/${deviceToken}`,
        method: 'POST',
        headers: {
          authorization: `bearer ${getJWT()}`,
          'apns-topic': topic,
          'apns-push-type': 'liveactivity',
          'apns-priority': '10',
          'content-type': 'application/json',
          'content-length': Buffer.byteLength(body),
        },
      },
      (res) => {
        let data = '';
        res.on('data', (chunk) => (data += chunk));
        res.on('end', () => {
          if (res.statusCode === 200) {
            resolve();
          } else {
            logger.warn(`[APNs] HTTP ${res.statusCode}: ${data}`);
            resolve();
          }
        });
      }
    );
    req.on('error', (err) => {
      logger.error('[APNs] request error:', err.message);
      resolve();
    });
    req.write(body);
    req.end();
  });
}

/**
 * Push a Live Activity content-state update.
 * contentState must match OrderLiveActivityAttributes.ContentState fields exactly.
 */
export async function pushLiveActivityUpdate(pushToken, contentState, alertTitle, alertBody) {
  const payload = {
    aps: {
      timestamp: Math.floor(Date.now() / 1000),
      event: 'update',
      'content-state': contentState,
      ...(alertTitle && {
        alert: { title: alertTitle, body: alertBody ?? '' },
        sound: 'default',
      }),
    },
  };
  await sendAPNs(pushToken, payload);
}

/**
 * End a Live Activity via push.
 */
export async function pushLiveActivityEnd(pushToken, contentState) {
  const payload = {
    aps: {
      timestamp: Math.floor(Date.now() / 1000),
      event: 'end',
      'content-state': contentState,
      'dismissal-date': Math.floor(Date.now() / 1000) + 7200,
    },
  };
  await sendAPNs(pushToken, payload);
}
