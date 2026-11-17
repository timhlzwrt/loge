# Self-hosted sync

Sync is optional. loge has no default sync server. Your own server can carry
private playback progress, Watch Later, addon setup and preferences across your devices, with
a separate account for each person.

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

While the app is open, each device keeps one request waiting at the server
(`GET /v2/changes`), which answers as soon as another of your devices saves, so
progress, Watch Later and setup changes show up within moments rather than at the
next launch. It stops when the app goes to the background and resumes on return;
while the server can't be reached it asks again after a growing pause, up to a
minute, without changing the Sync page's status. Documents that haven't changed
since the device last saw them aren't downloaded again.

Local progress is saved about every ten seconds and on pause, close, end and
backgrounding. Network checkpoints are throttled, to about two seconds while the
server is listening and fifteen otherwise; pause/close/background attempt
an immediate push. Before Play, Resume or the next episode picks where to start,
the device asks the server for the latest progress, waiting at most a second. On leaving, the app asks the system for time to finish that push;
how much it gets depends on the operating system, so a suspended device may deliver
its pending changes the next time it opens.

Watch Later syncs as its own document. For each title the latest action wins,
adding or removing, without asking; the list stays newest-added first. Removals are
remembered for 90 days, so a device that was offline longer can bring back a title
removed meanwhile. Connecting a device adds its Watch Later to the account's, whichever
setup you choose. Gateways from before Watch Later synced refuse the document: the
Sync page then says **Update the sync server to sync Watch Later**, Watch Later stays
on each device and everything else keeps syncing. Gateways from before live updates
have no `/v2/changes`: devices then sync at launch, on returning to the app and
after local changes, as before. One redeploy of the gateway (see
[Host the service](#host-the-service)) brings both Watch Later and live updates.

The setup syncs too: addons, playback preferences and Home's shelves. Home's
arrangement is one setting: edits on two devices before they sync are a conflict loge
asks about, like other settings. Addon shelves name the addon by its manifest ID,
never its URL, and a device without that addon keeps the shelf without showing it.

## Give someone your addons

Sharing with another person doesn't need sync or a server. In **Settings → Addons**,
select **Share Setup…** on iPhone, iPad or Mac. Choose whether to include your
playback preferences (audio and subtitle language, maximum bitrate), then share the
link or copy the code. The other person opens the link, or pastes it or the code
into **Settings → Addons → Import Setup…** (on Apple TV with the phone's Remote
keyboard). They see the addons' hosts, then choose **Add to My Addons**, which keeps
theirs and adds the ones they don't have, or **Replace My Addons**, which removes
the others once every addon in the setup has installed.

It is a one-time copy: later changes on either side stay where they're made. The
code contains your addons' full addresses, which often include account keys (a
debrid service, for example). Anyone with it can use them, so send it only to
people you trust. Nothing in it is sent to a sync server.

## Updating from shared setups

Earlier versions could share setup categories live between accounts. That was
replaced by the copy above. Update the apps first, then the gateway:

1. When updated, a device that was in a shared setup keeps the addons and
   preferences it shows. They become the account's own again: its next sync keeps
   these values over the account's older copy, and the shared setup's key is
   deleted from Keychain.
2. Then update the gateway and run `bootstrap.py` again (see
   [Host the service](#host-the-service)). Old app versions calling the removed
   endpoints get HTTP 410 Gone.

The groups and their encrypted documents stay in the database unused. To delete
them, run this on the server from `/opt/loge-sync`; it uses CouchDB's administrator
login from `secrets/bootstrap.json`:

```sh
sudo python3 - <<'END'
import base64, json, urllib.request
password = json.load(open('secrets/bootstrap.json'))['admin']
headers = {'Authorization': 'Basic ' + base64.b64encode(('loge-admin:' + password).encode()).decode(),
           'Content-Type': 'application/json'}
def call(path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request('http://127.0.0.1:5984/loge/' + path, data, headers)
    return json.load(urllib.request.urlopen(request))
rows = call('_all_docs?include_docs=true')['rows']
old = [row['doc'] for row in rows if row['id'].startswith(('group:', 'shared:'))
       or (row['id'].startswith('invitation:') and row['doc'].get('kind') == 'share')]
call('_bulk_docs', {'docs': [{'_id': doc['_id'], '_rev': doc['_rev'], '_deleted': True} for doc in old]})
print(len(old), 'documents deleted')
END
```

## Privacy, devices and recovery

Configurations, progress and Watch Later are AES-GCM encrypted on-device. The database stores
ciphertext, account metadata and hashes of random device/invitation tokens.
Device tokens and keys stay in Keychain. Treat connection codes as secrets: share them only
with the intended recipient.

Under **Connection & recovery**, inspect/revoke connected devices and save the
recovery key. Revocation prevents future requests, but cannot erase data already
downloaded. An administrator can disable an account or issue a new enrollment
code, but cannot recover encrypted data without your recovery key or a connected
device. To recover, enter the original key under **Advanced → Recover an existing
account**, then return and connect using the administrator's new code.

Disconnecting returns to the previous local library/setup. Each account's
remembered sources remain separate on that device and are not synchronized. Stream URLs, account tokens and connection
measurements are never included in synced setup.

## Host the service

Requirements: Linux, Docker Compose, Python 3 for bootstrap, an HTTPS reverse
proxy, and a hostname pointing at your server. This uses one private CouchDB
application database behind an authenticated gateway. The gateway enforces
account ownership; direct CouchDB membership does not isolate users'
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
codes and revoking devices/invitations. It cannot show
or decrypt the user's addons, preferences or playback history.

Back up `/opt/loge-sync/data`, server secrets and configuration. Preserve numeric
uid/gid 5984 and test restoration. Users must back up their recovery keys
separately; server backups contain ciphertext. Keep the pinned images updated
and run a single public gateway worker as documented in its guide.

## Earlier single-user sync

Builds before account sync offered a single encrypted `/configuration` document
per server under **Advanced → Previous sync connection**. That connection has been
removed. Connect an account
instead and choose this device's setup when asked. To upgrade such a server, see
the [gateway guide](../Tools/sync-gateway/README.md#upgrading-an-endpoint-sync-server).

References: [CouchDB database security](https://docs.couchdb.org/en/stable/api/database/security.html),
[CouchDB document API](https://docs.couchdb.org/en/stable/api/document/common.html),
[CouchDB Docker installation](https://docs.couchdb.org/en/stable/install/docker.html).
