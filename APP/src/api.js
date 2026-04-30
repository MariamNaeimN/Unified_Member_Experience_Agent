// =============================================================================
// WebSocket-based API Client
// All communication goes through a single WebSocket connection.
// =============================================================================

const WS_URL = import.meta.env.VITE_WS_URL || 'wss://b4fppalzzk.execute-api.us-east-1.amazonaws.com/dev';

let token = null;
let wsInstance = null;
const pendingRequests = new Map();
let chatMessageHandler = null;

export function setToken(t) { token = t; }
export function getToken() { return token; }

/**
 * Connect to the WebSocket API Gateway with the Cognito token.
 * Returns a Promise that resolves with the WebSocket instance when connected.
 */
export function connectWebSocket(authToken) {
  return new Promise((resolve, reject) => {
    const url = `${WS_URL}?token=${encodeURIComponent(authToken)}`;
    const ws = new WebSocket(url);

    ws.onopen = () => {
      wsInstance = ws;
      resolve(ws);
    };

    ws.onerror = (err) => {
      reject(new Error('WebSocket connection failed'));
    };

    ws.onclose = (event) => {
      // Reject pending requests on close
      for (const [reqId, { reject: rej, timer }] of pendingRequests) {
        clearTimeout(timer);
        rej(new Error('WebSocket connection closed'));
      }
      pendingRequests.clear();
    };

    ws.onmessage = (event) => {
      try {
        const msg = JSON.parse(event.data);

        // If it has a requestId, it's a response to a pending request
        if (msg.requestId && pendingRequests.has(msg.requestId)) {
          const { resolve: res, reject: rej, timer } = pendingRequests.get(msg.requestId);
          clearTimeout(timer);
          pendingRequests.delete(msg.requestId);

          if (msg.type === 'error') {
            rej(new Error(msg.message || 'Request failed'));
          } else {
            res(msg.data || msg);
          }
          return;
        }

        // Otherwise it's a streaming chat message (status/chunk/done/error)
        if (chatMessageHandler && (msg.type === 'status' || msg.type === 'chunk' || msg.type === 'done' || msg.type === 'error')) {
          chatMessageHandler(msg);
        }
      } catch (e) {
        console.error('WebSocket message parse error:', e);
      }
    };
  });
}

/**
 * Register a callback for streaming chat messages (status/chunk/done/error).
 */
export function onChatMessage(handler) {
  chatMessageHandler = handler;
}

/**
 * Send a chat message over WebSocket.
 * @param {WebSocket} ws
 * @param {string} memberId
 * @param {string} message
 * @param {string} [sessionId]
 * @param {string} [mode] - 'bedrock' (default) or 'agentcore'
 */
export function sendChatMessage(ws, memberId, message, sessionId, mode) {
  const payload = {
    action: 'sendMessage',
    memberId,
    message,
    sessionId: sessionId || `session-${Date.now()}`,
  };
  if (mode) payload.mode = mode;
  ws.send(JSON.stringify(payload));
}

/**
 * Generate a unique request ID.
 */
function generateRequestId() {
  if (typeof crypto !== 'undefined' && crypto.randomUUID) {
    return crypto.randomUUID();
  }
  return `${Date.now()}-${Math.random().toString(36).slice(2, 11)}`;
}

/**
 * Send a request over WebSocket and return a Promise that resolves
 * when the matching response arrives (keyed by requestId).
 * Rejects after 30 seconds if no response.
 */
function wsRequest(action, params = {}) {
  return new Promise((resolve, reject) => {
    if (!wsInstance || wsInstance.readyState !== WebSocket.OPEN) {
      reject(new Error('WebSocket not connected'));
      return;
    }

    const requestId = generateRequestId();
    const timeout = 30000;

    const timer = setTimeout(() => {
      pendingRequests.delete(requestId);
      reject(new Error(`Request timeout: ${action}`));
    }, timeout);

    pendingRequests.set(requestId, { resolve, reject, timer });

    wsInstance.send(JSON.stringify({
      action,
      requestId,
      ...params
    }));
  });
}

/**
 * Close the WebSocket connection.
 */
export function closeWebSocket() {
  if (wsInstance) {
    wsInstance.close(1000, 'Client logout');
    wsInstance = null;
  }
}

/**
 * Get the current WebSocket instance.
 */
export function getWebSocket() {
  return wsInstance;
}

// =============================================================================
// Public API — same interface as before, now backed by WebSocket
// =============================================================================

export const api = {
  getAllMembers: () =>
    wsRequest('getMembers', {}),

  searchMembers: (search) =>
    wsRequest('getMembers', { search }),

  memberProfile: (memberId) =>
    wsRequest('getMemberProfile', { memberId }),

  notifications: (memberId) =>
    wsRequest('getNotifications', memberId ? { memberId } : {}),

  updateNotification: (memberId, notificationId, status) =>
    wsRequest('updateNotification', { memberId, notificationId, status }),

  chatHistory: (memberId) =>
    wsRequest('getChatHistory', { memberId }),
};
