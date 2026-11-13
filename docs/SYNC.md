# Self-hosted sync

Sync is optional. loge has no default sync server. Your own server can carry
private playback progress, addon setup and preferences across your devices, with
separate accounts and deliberately shared setup categories.

## Connect an account

1. Ask your server administrator to create an account in the local management
   page and give you its connection code.
2. Open **Settings → Sync**, paste it into **Connection code**, and select
   **Connect account**. Apple TV accepts pasted codes through the phone's Remote
   keyboard.
3. Choose whether to start with this device's local setup/progress or the server
   version. Nothing is imported into the account before that choice.
4. For your next device, use **Add my device** on an already connected device.
   Its new connection code includes the encryption keys needed to access your
   account. Codes expire after 24 hours and work once.

Your connected devices share exact movie/episode progress, watched state and
explicit progress removals. Rewatches and backward seeks are preserved; sync does
not simply choose the furthest position. Changes to different titles merge. When
two devices play the same title independently, the position left most recently wins
without asking. When one removes a title or marks it unwatched and another plays it,
loge asks which to keep. Offline edits remain saved for the next successful sync.

Local progress is saved about every ten seconds and on pause, close, end and
backgrounding. Network checkpoints are throttled; pause/close/background attempt
an immediate push. On leaving, the app asks the system for time to finish that push;
how much it gets depends on the operating system, so a suspended device may deliver
its pending changes the next time it opens.

## Share setup with another person

Use **Share setup**, select **Addons**, **Playback preferences**, and/or
**Appearance**, then create a new code. Addons are selected by default. The other
person connects their own account first, then selects **Join shared setup**.

This creates a live shared setup: subsequent changes to selected categories sync
for everyone in that group. Only one group can control each category for an
account. Leaving a joined group stops future sharing with your account; leaving
a group you created stops it for all its members. The local management page can
also disable groups and revoke invitations.

Playback progress is always private to the account and is never included in a
sharing invitation. An addon invitation includes only the separate group's
access/key, not your account credential or personal progress key.

## Privacy, devices and recovery

Configurations and progress are AES-GCM encrypted on-device. The database stores
ciphertext, account/group metadata and hashes of random device/invitation tokens.
Personal accounts and shared setups use separate encryption keys. Device tokens
and keys stay in Keychain. Treat connection codes as secrets: share them only
with the intended recipient.

Under **Connection & recovery**, inspect/revoke connected devices and save the
recovery key. Revocation prevents future requests, but cannot erase data already
downloaded. An administrator can disable an account or issue a new enrollment
code, but cannot recover encrypted data without your recovery key or a connected
device. To recover, enter the original key under **Advanced → Recover an existing
account**, then return and connect using the administrator's new code.

Disconnecting returns to the previous local library/setup. Each account's local
Watch Later, custom lists and remembered sources remain separate on that device;
these are not currently synchronized. Stream URLs, account tokens and connection
measurements are never included in shared setup payloads.

## Host the service

Requirements: Linux, Docker Compose, Python 3 for bootstrap, an HTTPS reverse
proxy, and a hostname pointing at your server. This uses one private CouchDB
application database behind an authenticated gateway. The gateway enforces
account and group ownership; direct CouchDB membership does not isolate users'
documents.

1. Copy [Tools/sync-gateway](../Tools/sync-gateway) to `/opt/loge-sync`, then
   run its bootstrap as root. It creates the CouchDB administrator, the database
   and the gateway's own login:

   ```sh
   sudo python3 /opt/loge-sync/bootstrap.py --directory /opt/loge-sync
   ```

2. Set `SYNC_PUBLIC_ENDPOINT` to your HTTPS address ending in `/v2` and start the
   services as described in the [gateway guide](../Tools/sync-gateway/README.md).
3. Keep CouchDB private. Forward only `/v2/*` to the gateway on port 5985; never
   expose CouchDB itself through a generic proxy.
4. Keep administration on localhost or behind a management-host firewall and SSH
   tunnel. Never forward its port 5986 or `/admin` paths through public Caddy.
5. Open the local management page, unlock it with the server-only administrator
   token (or sign in through Pocket ID or another OpenID Connect provider; see
   `Tools/sync-gateway/README.md`), then create accounts and give each person
   their own enrollment code.

The management page supports creating/disabling accounts, issuing enrollment
codes, revoking devices/invitations and disabling shared setups. It cannot show
or decrypt the user's addons, preferences or playback history.

Back up `/opt/loge-sync/data`, server secrets and configuration. Preserve numeric
uid/gid 5984 and test restoration. Users must back up their recovery keys
separately; server backups contain ciphertext. Keep the pinned images updated
and run a single public gateway worker as documented in its guide.

## Earlier single-user sync

Builds before account sync offered a single encrypted `/configuration` document
per server under **Advanced → Previous sync connection**. That connection has been
removed; the app deletes its saved server login from Keychain. Connect an account
instead and choose this device's setup when asked. To upgrade such a server, see
the [gateway guide](../Tools/sync-gateway/README.md#upgrading-an-endpoint-sync-server).

References: [CouchDB database security](https://docs.couchdb.org/en/stable/api/database/security.html),
[CouchDB document API](https://docs.couchdb.org/en/stable/api/document/common.html),
[CouchDB Docker installation](https://docs.couchdb.org/en/stable/install/docker.html).
