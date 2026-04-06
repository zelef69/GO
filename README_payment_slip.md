# Firebase + Thunder slip payment setup

This repo now includes a server-side package-purchase flow for `com.onetabtube.browser_default` using:

- Firebase Cloud Functions 2nd gen
- Firestore
- Cloud Storage
- Firebase Auth
- Firebase App Check
- Thunder Solution bank-slip verification API

The implementation keeps Thunder calls on the server only. The client only sends:

- `packageId` to create an order
- `orderId` and `storagePath` to verify a slip

## Files added or changed

- `functions/src/package_orders.ts`
- `functions/src/lib/thunder.ts`
- `functions/src/lib/firebase.ts`
- `functions/src/index.ts`
- `functions/package.json`
- `firebase.json`
- `firestore.rules`
- `storage.rules`

## Firestore schema

Seed at least one product document before testing:

Collection: `products`

Document: `products/pkg_599`

```json
{
  "name": "Premium 30 Days",
  "price": 599,
  "currency": "THB",
  "durationDays": 30,
  "active": true
}
```

This repo now includes a seed file and seed script:

- seed data: `functions/seeds/products.seed.json`
- seed script: `functions/scripts/seed-products.js`

Orders are created in `orders/{orderId}`.

Verified payments are written to `payments/{transRef}`.

Entitlements are written to `users/{uid}/entitlements/{packageId}`.

## Storage path

Clients should upload the bank-slip image to:

```text
slips/{uid}/{orderId}.jpg
```

`createPackageOrder` returns both the canonical `storagePath` and an `uploadUrl`.
That `uploadUrl` is a Cloud Storage resumable upload session URL for the same
object, so the Android client can upload the slip without calling Thunder or
holding any privileged Storage credentials.

Later, `verifyPackageSlip` validates that the path belongs to the current user
and order before generating a signed read URL for Thunder.

## Secrets

Do not hardcode the Thunder key in source code.

Set the secret in Firebase Secret Manager:

```bash
firebase functions:secrets:set THUNDER_API_KEY
```

If you keep the key locally in `thunder_api.txt`, do not commit it and do not copy its contents into status files.

## App Check

Both callable functions use `enforceAppCheck: true`.

Make sure your client is sending valid App Check tokens before testing against non-emulator backends.

## Local build

From repo root:

```bash
npm --prefix functions run build
```

## Local smoke without Thunder or Emulator Suite

This repo now includes a local callable smoke script that exercises the compiled
Functions business logic with in-process stubs for Firestore, Storage, and
Thunder.

Run:

```bash
npm --prefix functions run smoke:payments
```

The smoke covers:

- `createPackageOrder` happy path
- `verifyPackageSlip` paid-flow happy path
- `verifyPackageSlip` amount-mismatch path

Use this first when you want fast regression coverage without touching a live
Firebase project or Thunder.

## Seed products locally or in a target project

Dry run first:

```bash
npm --prefix functions run seed:products:dry -- --project go-play-720c1
```

Write the seed data:

```bash
npm --prefix functions run seed:products -- --project go-play-720c1
```

This upserts the products defined in `functions/seeds/products.seed.json` into the `products` collection.

If you are using the Firestore emulator, make sure `FIRESTORE_EMULATOR_HOST` is set before running the seed script.

## Seed a test entitlement for the Android Account page

This repo now includes a helper script to upsert a test entitlement doc at:

```text
users/{uid}/entitlements/{packageId}
```

Dry run:

```bash
npm --prefix functions run seed:entitlement:dry -- --project go-play-720c1 --uid 5JUdwpcXC1WFk6mLsT85kwaCgIb2 --package-id pkg_599 --days 30
```

Write the entitlement:

```bash
npm --prefix functions run seed:entitlement -- --project go-play-720c1 --uid 5JUdwpcXC1WFk6mLsT85kwaCgIb2 --package-id pkg_599 --days 30
```

Use `--inactive` if you want the Account page to resolve to the "No active package" state instead of a positive day count.

The seed helpers now print the target Firebase project before writing. They resolve project id in this order:

1. `--project <projectId>`
2. `GCLOUD_PROJECT` / `GOOGLE_CLOUD_PROJECT`
3. `.firebaserc` default project

Important: `firebase login` alone is not enough for these admin seed scripts.

To perform real writes, use one of these:

1. Install Google Cloud SDK and run:

```bash
gcloud auth application-default login
```

2. Or pass a service-account JSON directly:

```bash
npm --prefix functions run seed:entitlement -- --project go-play-720c1 --service-account path/to/service-account.json --uid 5JUdwpcXC1WFk6mLsT85kwaCgIb2 --package-id pkg_599 --days 30
```

If you cannot use ADC or a service account JSON right now, create the document manually in Firestore console at:

```text
users/5JUdwpcXC1WFk6mLsT85kwaCgIb2/entitlements/pkg_599
```

with fields:

- `packageId` = string `pkg_599`
- `active` = boolean `true`
- `source` = string `manual-seed`
- `startedAt` = timestamp now
- `expiresAt` = timestamp now + 30 days
- `updatedAt` = timestamp now

## Local emulators

From repo root:

```bash
npm --prefix functions run serve
```

This starts:

- Functions emulator
- Firestore emulator
- Storage emulator

If you want authenticated callable smoke through the Emulator Suite, add Auth
emulator flow on top of this. The local smoke script above is kept as a lighter
weight fallback when emulator bring-up is blocked or not needed.

## Deploy

Do not deploy production blindly.

When you are ready to deploy to the configured Firebase project:

```bash
firebase deploy --only functions,firestore:rules,storage
```

If you only need to unblock Android Account entitlement reads first:

```bash
firebase deploy --only firestore:rules --project go-play-720c1
```

Or deploy only functions:

```bash
npm --prefix functions run deploy
```

To deploy only the native Buy-package payment functions that the Android app
expects right now:

```bash
npm --prefix functions run deploy:payments -- --project go-play-720c1
```

This should make these callable URLs exist:

- `createPackageOrder`
- `verifyPackageSlip`

## Callable APIs

### `createPackageOrder({ packageId })`

Requirements:

- authenticated user
- valid App Check token
- `products/{packageId}` exists and is active

Returns:

- `orderId`
- `expectedAmount`
- `currency`
- `durationDays`
- `expiresAt`
- default `storagePath`
- `uploadUrl` for the slip upload session

### `verifyPackageSlip({ orderId, storagePath })`

Requirements:

- authenticated user
- valid App Check token
- order belongs to the caller
- order is still `PENDING`
- slip exists in Cloud Storage

Server steps:

1. Read the order
2. Create a signed URL for the uploaded slip
3. Call Thunder server-to-server
4. Check:
   - amount match
   - duplicate slip
   - matched receiver account
5. Use a Firestore transaction to:
   - create `payments/{transRef}`
   - mark `orders/{orderId}` as `PAID`
   - update `users/{uid}/entitlements/{packageId}`

## Error handling

The verification function uses readable callable errors for business failures such as:

- order expired
- duplicate slip
- amount mismatch
- receiver account mismatch
- `SLIP_PENDING`

## Manual test flow

1. Sign in to the Android app
2. Seed products:
   ```bash
   npm --prefix functions run seed:products
   ```
3. Call `createPackageOrder({ packageId: "pkg_599" })`
4. Upload an image slip through the returned `uploadUrl`
5. Call `verifyPackageSlip({ orderId, storagePath })`
6. Confirm:
   - payment doc created
   - order marked `PAID`
   - entitlement updated for the user

## Assumptions in this implementation

- order TTL is `30 minutes`
- entitlement expiry extends from the later of:
  - now
  - existing entitlement expiry
- `matchAccount` is enabled by default
- `products/{packageId}` is the source of truth for price and duration

## Next improvements

- add integration tests using the Emulator Suite
- add a live smoke checklist for the redeploy/retest loop
- wire `verifyPackageSlip` success to refresh the Account page immediately
- add native logout and package-history/admin tooling on top of the existing Account page
