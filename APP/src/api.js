const API_URL = import.meta.env.VITE_API_URL || (import.meta.env.DEV ? '/api' : 'https://87slbidh3k.execute-api.us-east-1.amazonaws.com/dev');

let token = null;

export function setToken(t) { token = t; }
export function getToken() { return token; }

async function request(method, path, body = null, params = {}) {
  let url = API_URL + path;
  const queryParts = Object.entries(params)
    .filter(([, v]) => v !== undefined && v !== null && v !== '')
    .map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`);
  if (queryParts.length) url += '?' + queryParts.join('&');

  const opts = {
    method,
    headers: { 'Authorization': token, 'Content-Type': 'application/json' },
  };
  if (body) opts.body = JSON.stringify(body);

  const res = await fetch(url, opts);
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`API ${res.status}: ${text}`);
  }
  return res.json();
}

export const api = {
  chat: (memberId, message, sessionId) =>
    request('POST', '/chat', { memberId, message, sessionId }),
  chatHistory: (memberId) =>
    request('GET', '/chat', null, { memberId }),
  searchMembers: (search) =>
    request('GET', '/members', null, { search }),
  memberProfile: (memberId) =>
    request('GET', '/members/profile', null, { memberId }),
  notifications: (memberId) =>
    request('GET', '/notifications', null, memberId ? { memberId } : {}),
};
