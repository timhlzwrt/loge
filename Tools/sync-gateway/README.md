# Account sync gateway

This optional gateway adds isolated accounts, device enrollment and selective live
setup sharing to the existing CouchDB backend. One private application database
holds account metadata, hashed device/invitation credentials and encrypted payloads.
CouchDB is never exposed as a multi-user document API: its database permissions
cannot isolate individual documents from other database members.

## Installation

First bootstrap the existing backend using `Tools/configuration-sync`. Copy this
directory to `/opt/loge-sync/gateway`, then run as root:

```sh
python3 /opt/loge-sync/gateway/bootstrap.py
export SYNC_PUBLIC_ENDPOINT=https://sync.example.com/v2
cd /opt/loge-sync
docker compose -f docker-compose.yml -f gateway/compose.yml up -d --build
```

The bootstrap preserves the legacy configuration document, adds a separate scoped
service credential and updates its write validator. Administrative secrets remain
under `secrets/`; no encryption key belongs on the server. Keep `data/`, secrets,
source and Compose configuration in your backup and test a restore.

Forward only `/v2/*` from the HTTPS reverse proxy to `127.0.0.1:5985`; retain the
existing `/configuration` route for older clients. Cap request bodies at 1 MiB and
set `Cache-Control: no-store`. Disable access/body logging. Do not forward `/admin`
or port 5986. If the proxy runs on another host, bind the gateway on a private
address and firewall it to the proxy. Administrative port 5986 must remain
localhost-only or restricted to a management host reached through an SSH tunnel.
The admin application additionally checks Host, Origin and a separate token.

Open `http://localhost:5986` locally (or through an SSH tunnel) and privately read
`secrets/gateway-admin-token` to unlock it. The token stays only in that browser
tab's memory. Create an account to obtain its one-use, 24-hour enrollment code.
Set the correct public endpoint before creating codes. Existing accounts need
their recovery key or a code from a connected device; administrative enrollment
cannot decrypt or recover their data.

The page supports account creation/disabling, new enrollment codes, device and
invitation revocation, and shared-setup disabling. Disabling or revoking stops
future API access; it cannot erase data already downloaded by another device.
Run one public gateway worker: its membership lock makes the cross-document
category checks atomic within this deployment. Device invitation consumption and
all encrypted-document writes independently use CouchDB revision checks.

## API

The endpoint entered into the app ends in `/v2`. Public paths:

- `POST /redeem`: `{code, deviceName, hasRecoveryKey}` -> device token/account metadata.
- `GET /me`: account, current device and authoritative shared-group metadata.
- `GET/PUT /documents/configuration` and `/documents/progress`: private account envelopes.
- `GET/PUT /groups/{id}/document`: shared envelopes, checked against membership.
- `POST /invitations`: device invitation or shared group/category invitation.
- `POST /join`: redeem a share invitation while signed into a different account.
- `GET /devices`, `DELETE /devices/{id}`: list/revoke your own devices.
- `GET /invitations`, `DELETE /invitations/{id}`: list/revoke your invitations.
- `DELETE /groups/{id}/membership`: leave a joined group; an owner stops sharing the group for everyone.

All except redemption/health require `Authorization: Bearer <device token>`.
Tokens/codes are random 256-bit capabilities; only SHA-256 digests are stored.
Invitation consumption and device creation are one revision-checked write, so
concurrent redemptions cannot both succeed. Administrative and public applications
run separately and do not register each other's routes.

Encrypted envelopes contain `{version:2,ciphertext,_rev?}`. `ciphertext` is base64
AES-GCM data encrypted by the app; revision conflicts return 409. Group categories
are `addons`, `playback` (audio/subtitle preferences), and `appearance`. Personal
watch progress is never a sharing category. A code from an existing device includes the
private profile key; a sharing code includes only its separate group key. An
initial administrator enrollment creates a key on the first device of a new
account. Enrollment for an existing account requires its recovery key and
returns 428 without consuming the code when the key is missing.

## Tests

```sh
python3 -m venv /tmp/loge-gateway-tests
/tmp/loge-gateway-tests/bin/pip install -r Tools/sync-gateway/requirements-dev.txt
/tmp/loge-gateway-tests/bin/python -m unittest discover -s Tools/sync-gateway -p 'test_*.py'
```

The suite covers user isolation, document conflicts, simultaneous enrollment,
revocation, expiry, local-admin CSRF/Host checks and shared-group scope. Live tests
must use disposable accounts and revoke their device tokens afterward.

Dependencies: [FastAPI](https://pypi.org/project/fastapi/),
[Uvicorn](https://pypi.org/project/uvicorn/),
[CouchDB security](https://docs.couchdb.org/en/stable/api/database/security.html).
