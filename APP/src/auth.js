const COGNITO_URL = 'https://cognito-idp.us-east-1.amazonaws.com';
const CLIENT_ID = import.meta.env.VITE_COGNITO_CLIENT_ID || '3ru1bf0hq0027uc49v8d38mvtu';
const USER_POOL_ID = import.meta.env.VITE_COGNITO_USER_POOL_ID || 'us-east-1_vvcOmWFgl';

async function cognitoRequest(target, body) {
  const res = await fetch(COGNITO_URL, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-amz-json-1.1',
      'X-Amz-Target': `AWSCognitoIdentityProviderService.${target}`,
    },
    body: JSON.stringify(body),
  });
  const data = await res.json();
  if (data.__type) throw new Error(data.message || data.__type);
  return data;
}

export async function login(username, password) {
  const data = await cognitoRequest('InitiateAuth', {
    AuthFlow: 'USER_PASSWORD_AUTH',
    ClientId: CLIENT_ID,
    AuthParameters: { USERNAME: username, PASSWORD: password },
  });
  if (data.AuthenticationResult) {
    const jwt = parseJwt(data.AuthenticationResult.IdToken);
    return {
      idToken: data.AuthenticationResult.IdToken,
      name: jwt.name || username,
      email: jwt.email || username,
    };
  }
  throw new Error('Authentication failed');
}

export async function signUp(name, email, password) {
  await cognitoRequest('SignUp', {
    ClientId: CLIENT_ID,
    Username: email,
    Password: password,
    UserAttributes: [
      { Name: 'name', Value: name },
      { Name: 'email', Value: email },
    ],
  });
  return { email, needsConfirmation: true };
}

export async function confirmSignUp(email, code) {
  await cognitoRequest('ConfirmSignUp', {
    ClientId: CLIENT_ID,
    Username: email,
    ConfirmationCode: code,
  });
  return { confirmed: true };
}

function parseJwt(token) {
  try {
    return JSON.parse(atob(token.split('.')[1]));
  } catch { return {}; }
}
