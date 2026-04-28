const COGNITO_URL = 'https://cognito-idp.us-east-1.amazonaws.com';
const CLIENT_ID = import.meta.env.VITE_COGNITO_CLIENT_ID || '3ru1bf0hq0027uc49v8d38mvtu';

export async function login(username, password) {
  const res = await fetch(COGNITO_URL, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-amz-json-1.1',
      'X-Amz-Target': 'AWSCognitoIdentityProviderService.InitiateAuth',
    },
    body: JSON.stringify({
      AuthFlow: 'USER_PASSWORD_AUTH',
      ClientId: CLIENT_ID,
      AuthParameters: { USERNAME: username, PASSWORD: password },
    }),
  });
  const data = await res.json();
  if (data.AuthenticationResult) {
    return {
      idToken: data.AuthenticationResult.IdToken,
      name: parseJwt(data.AuthenticationResult.IdToken).name || username,
      email: parseJwt(data.AuthenticationResult.IdToken).email || username,
    };
  }
  throw new Error(data.message || 'Authentication failed');
}

function parseJwt(token) {
  try {
    return JSON.parse(atob(token.split('.')[1]));
  } catch { return {}; }
}
