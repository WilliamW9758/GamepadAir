# Mac marketplace account

The Mac uses Cognito managed login with Sign in with Apple. The iPhone remains a paired
controller, without account credentials. Anonymous catalog browsing and downloads use no token.
AI generation is not implemented; the existing local assistant preview does not call an AI service.

## Configuration

The public issuer, native client ID, scopes and callback are in
`Sources/MacSupport/MarketplaceAuth.swift`. There is no client secret or Apple private key in the
app. `Config/MacInfo.plist` registers `pocketpad://auth/callback` and permits local networking for
the development API. Production API URLs must use HTTPS. Set the API base URL in Marketplace →
Server connection; it is stored as `marketplace-api-url` in Mac preferences. The current default
is the local development API at `http://127.0.0.1:8001`; deployment must configure a public endpoint
before distributing this integration to testers.

`server/AUTH.md` is the backend contract. This implementation does not provision AWS or change
server authentication. Sign-in uses ASWebAuthenticationSession, authorization code, PKCE S256,
cryptographically random state/nonce and exact callback validation. ID tokens are verified with
RS256 against the configured issuer's HTTPS JWKS, including issuer, audience, expiry, issued-at,
token use, nonce at login, and stable subject across refresh. API identity is issuer + subject,
not email. Only the access token is sent as the API bearer credential.

Credentials are a single data-protection Keychain item, accessible when unlocked on this Mac.
Refreshing is serialized and the old refresh token is marked consumed before any network request.
The new token set replaces the item atomically. A crash, ambiguous network result, or storage
failure requires another login rather than replaying an old rotating token. HTTP redirects are
rejected, responses are bounded, and network operations have request timeouts. No tokens are
logged, written to preferences, exported in documents, or included in phone sync.

Sign out clears local credentials, requests refresh-token revocation, and opens Cognito logout
to clear the managed-login browser session. Browser cancellation and failed remote revocation
are reported separately from local sign-out. Short-lived access tokens already issued may remain
usable by offline JWT verifiers until expiry, as described in the backend contract.

## User flow

- Marketplace loads approved community layouts without signing in.
- Sign in with Apple opens the system-managed browser session, then verifies `/v1/me`.
- Your layouts shows owned listings. Choose a saved layout from the dropdown and submit its canonical v2 JSON for review.
- Download a copy fetches the newest owned revision, including pending ones, as a fresh local copy.
- Submit selected as revision uses the dropdown selection and displayed expected revision; HTTP 409 requires refresh.
- Remove unpublishes a listing; already downloaded copies remain on other devices.
- Writes are never automatically retried. A lost response tells the user to check Your layouts
  before resubmitting, because initial POST is not idempotent.

## Verification

Automated tests cover PKCE, exact callbacks, rejected duplicate/state/error callbacks, insecure
endpoint rejection, real RSA signature verification and claim failures, concurrent refresh,
ambiguous refresh, logout during refresh, and Keychain failure before refresh transmission.
The signed Mac build passes, and anonymous browsing works against the local Docker API.
The user confirmed the sign-in/submission test succeeded. The Mac UI subsequently restored the
account and displayed the private test listing at revision 2. Public approval/download of that
listing and logout verification have not been independently observed. Marketplace browsing is
now separate from My submissions, which contains account and publishing controls.

References: [AWS token endpoint](https://docs.aws.amazon.com/cognito/latest/developerguide/token-endpoint.html),
[AWS refresh tokens](https://docs.aws.amazon.com/cognito/latest/developerguide/amazon-cognito-user-pools-using-the-refresh-token.html),
[Apple web authentication](https://developer.apple.com/documentation/authenticationservices/authenticating-a-user-through-a-web-service).

The storefront uses illustrated cards and labeled, non-downloadable examples when empty. Catalog
and submission status reload on page entry, app activation, and every minute while visible; no
manual Refresh or permanent reauthentication button is shown. Expired sessions expose ordinary
Sign in with Apple only when authentication is actually required.
