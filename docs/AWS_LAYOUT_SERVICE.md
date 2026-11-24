# AWS layout service proposal

Prepared November 23, 2026. No AWS resources, billing commitments, or credentials have been created. This is the proposed small-launch architecture, not a deployed backend.

## Product flow

Mac-first “Find a layout”: search by game or scenario, filter existing community layouts, preview bindings and compatibility, download a personal copy. If no result fits, offer generation using sourced game-control research. Leave fine placement/mapping edits in the existing editor. No persistent AI chat. Downloads and local play should not require an account; publishing needs a stable owner. Generated private drafts are not automatically published.

## Proposed components

| Need | Initial service/design |
| --- | --- |
| Published JSON and preview images | Private S3 bucket, served through CloudFront origin access control. Immutable revision paths and compressed JSON. Separate unpublished uploads from approved objects. |
| API | API Gateway HTTP API + Lambda. Public read routes; authenticated upload/edit/delete routes. No EC2 or always-on application server initially. |
| Listings and ownership | DynamoDB on-demand: layout metadata, immutable revision metadata, owner listing index, game/scenario/input-type indexes, moderation records and generation jobs. |
| Game discovery | Small versioned game/alias catalog; resolve a query to canonical game IDs, then query indexed layouts. For scenarios, maintain bounded normalized token/tag indexes. Do not perform table-wide scans per keystroke or claim DynamoDB supplies native full-text/fuzzy search. |
| Publishing identity | Cognito user pool with Sign in with Apple; JWT authorizer on write routes. Server trusts token subject, not client-supplied author ID. Browse/download remain anonymous. |
| Generation | HTTP endpoint creates an asynchronous job → SQS → Lambda worker → validated private draft in S3 + job status in DynamoDB. Use Anthropic API directly so the user's applicable Anthropic credits can be used; do not assume they apply to AWS Bedrock billing. |
| Secrets and operations | Secrets Manager for provider/Apple secrets, scoped IAM roles, CloudWatch metrics and short-retention redacted logs, AWS Budgets alerts and application-level generation quotas. |

Use one region for the initial service; `us-east-1` is a working proposal, not a committed choice. Avoid a VPC/NAT gateway for these public AWS service/API calls unless there is a concrete need. Delay dedicated full-text/vector search infrastructure until catalog size and measured query quality justify it.

## API contract outline

- `GET /v1/games?q=...` → bounded canonical game/alias matches.
- `GET /v1/layouts?gameId=...&inputType=...&tag=...&cursor=...` → paginated approved listings only.
- `GET /v1/layouts/{id}` → revision, metadata, compatible schema, digest and download information. Respect removed/blocked status.
- `POST /v1/layouts` → authenticated submission, schema/semantic validation, pending moderation. Return publication ID, never trust client moderation/owner fields.
- `PUT /v1/layouts/{id}/revisions` → owner-only immutable revision, expected current revision to avoid overwriting concurrent edits.
- `DELETE /v1/layouts/{id}` → owner-only unpublish/tombstone; remove listing indexes and invalidate cached metadata/previews. Define bounded CDN cache expiry so removal is effective. Previously downloaded personal copies remain local.
- `POST /v1/reports`, `PUT /v1/blocked-authors/{id}`, `DELETE /v1/account` → moderation, author blocking and account deletion flows.
- `POST /v1/generation-jobs` → idempotency key + game/scenario/preferences + disclosure consent; returns job ID. `GET /v1/generation-jobs/{id}` → authorized status/result. Private results never use a public predictable URL.

## Data and safety boundaries

Store revision payloads in S3; DynamoDB stores searchable metadata and the payload digest/key, not repeated complete layouts. Schema/version/input type/game ID are indexed fields. Publication ID and revision are server-assigned; local layout UUIDs never grant ownership. Use conditional writes for revisions and quota reservations.

Validate both client and server, with decompressed size limits, bounded strings/control counts, allowlisted outputs, no executable fields, no remote image/URL execution in the controller. Render previews from the validated geometry or sanitize/re-encode uploaded images; do not blindly serve SVG/HTML from users. Reject private device data. Moderate names/descriptions/images, offer reporting and blocking, and document support and publication licensing before enabling uploads.

Use public URLs only for approved public material. Cache invalidation and tombstones are required for removals; never assume an immutable CDN cache makes moderation immediate. Define account deletion, public attribution, backups and retention before launch. Public content cannot be promised to disappear from other users' saved local copies.

## Cost and abuse controls

Do not promise the service is free based solely on credits. First agree an AWS monthly budget, then estimate storage, egress, requests, auth users and model calls. Set billing alerts, API throttles, Lambda concurrency limits, bounded upload sizes, log retention, S3 lifecycle cleanup and a global generation kill switch. Billing alerts are monitoring; enforce model quotas before dispatching work, including retries and parallel jobs. Reserve estimated tokens/cost atomically, reconcile actual usage, and bound maximum response tokens.

Anonymous browsing is low-friction. Anonymous generation is harder to protect: use short-lived installation credentials/attestation where supported plus per-install/IP/global limits, or require Apple sign-in only for generation if abuse makes that necessary. Do not ship a shared secret in the app as authentication. Put publisher sign-in and ownership in place before uploads.

## What to decide/set up next

1. AWS account with root MFA and an IAM Identity Center/deployment role; no root or permanent AWS keys in the app.
2. Region, monthly budget and alert destination; development/production separation.
3. Domain for API, downloads, support and privacy (or initial service URLs). HTTPS certificate and DNS.
4. Confirm Apple sign-in publisher flow, public nickname, upload license, moderation owner/contact and retention/deletion policy.
5. Set up Sign in with Apple/Cognito artifacts: App ID, Services ID, signing key and team ID; maintain secret rotation. No need for customers to sign in just to play locally.
6. Finalize the layout schema/adapter; deploy infrastructure from versioned IaC (suggest AWS SAM or CDK) with least-privilege roles, rollback and alarms.
7. Build a small curated catalog and read-only browse/download first. Add authenticated publishing/moderation, then generation jobs. Test authorization failures and deletion before external beta.

## AWS references checked

- HTTP API JWT authorization: https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-jwt-authorizer.html
- S3 origin access control: https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-restricting-access-to-s3.html
- DynamoDB partition/index design: https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/bp-partition-key-design.html
- Cognito + Apple setup requirements: https://docs.aws.amazon.com/cognito/latest/developerguide/cognito-user-pools-social-idp-apple.html
