# Self-hosted configuration sync

Sync is optional and off by default. loge has no default sync server. Each user
chooses a compatible HTTPS endpoint in **Settings → Sync**. This service carries
addon setup and app preferences; Trakt separately carries watch progress/history.

## Connect devices

1. Deploy the single-user backend below, or obtain its configuration URL and app
   credentials from the administrator of a compatible instance.
2. In **Settings → Sync**, enter the full HTTPS configuration URL, username and app
   password. Select **Generate New Recovery Key** for a new setup, then **Connect**.
3. Keep the recovery key somewhere safe. The server cannot recover it. On the
   connected device, **Show Setup Code** includes the connection and key for your
   other devices. Treat this code like a password; anyone with it can read and
   change the synchronized setup.
4. On another device, paste the code into **Setup code**, select **Use Setup Code**,
   then **Connect**. Apple TV accepts pasted text through the phone's Remote
   keyboard. You can also enter the same connection and recovery key manually.
5. If a server setup already exists, choose which initial setup to keep.

The encrypted document includes ordered addon manifest URLs, audio/subtitle
languages, subtitle size, automatic source size limit and accent. Manifest URLs
can contain addon credentials, so the entire configuration is AES-GCM encrypted
before uploading. A random 256-bit key and the server credentials are stored in
each device's Keychain. The server sees ciphertext and revision metadata.

Account tokens, remembered stream URLs, connection speed, search recents, Watch
Later and custom lists are excluded. Sync runs on launch, foreground, manual
request and after local settings edits. Offline edits remain on the device and
are reconciled when sync succeeds. Changes to different settings merge; conflicting
edits to the same setting require a choice. The ordered addon list is a single
field, so a removed addon is not silently reinstalled by combining lists.

Changing server requires disconnecting and connecting again. Disconnect keeps
local addons/preferences and removes this device's saved connection/key. Keep
another copy of the recovery key before disconnecting your last device.

## Deploy a backend

The included setup uses one CouchDB node and one encrypted document for one user
or household. It is not an open registration or multi-tenant service. Separate
users need separate isolated instances or a separately designed authenticated
routing layer. Arbitrary WebDAV servers are not compatible with this protocol.

Requirements: Linux with Docker Compose, Python 3, a hostname pointing at the
server, and an HTTPS reverse proxy. Copy the files from
[Tools/configuration-sync](../Tools/configuration-sync) to `/opt/loge-sync`.
Run the bootstrap once as root on a fresh directory:

```sh
sudo python3 /opt/loge-sync/bootstrap.py --directory /opt/loge-sync
```

This starts CouchDB, creates a dedicated non-admin app account, restricts database
membership and installs a validator that permits only an encrypted configuration
envelope. Credentials are written to `/opt/loge-sync/secrets/bootstrap.json`,
readable only by root; retrieve them privately for app setup. Do not use the
administrator credential in loge. The bootstrap refuses an existing secrets/data
directory to avoid replacing an installed service's credentials.

The sample binds CouchDB only to `127.0.0.1:5984`. Never expose port 5984 publicly.
Use this route with Caddy running on the same host, replacing `sync.example.com`
with your hostname. Other reverse proxies must enforce the same restrictions.

```caddyfile
sync.example.com {
    @configuration {
        path /configuration
        method GET HEAD PUT
    }
    handle @configuration {
        request_body {
            max_size 1MB
        }
        rewrite * /loge/configuration?
        reverse_proxy 127.0.0.1:5984 {
            header_down Cache-Control "no-store"
        }
    }
    respond 404
}
```

The trailing `?` deliberately clears query parameters. In particular,
`new_edits=false` must not bypass revision checks. The app URL is
`https://sync.example.com/configuration`. Keep administration, `_users`, bulk
writes, deletion and every other endpoint off the public route. Do not enable
request-body or credential logging. The app requires HTTPS and rejects redirects.
For a proxy on another machine, use a private bind address and firewall port 5984
to that proxy and management host only.

Back up `/opt/loge-sync/data` and `secrets`, and test restoration. The recovery key
must be backed up separately by the user; database backups contain ciphertext.
Keep the pinned image updated deliberately and preserve the data ownership
(uid/gid 5984). The service runs without Linux capabilities and has a 384 MiB
memory limit. Resource usage depends on workload.

## Protocol and failures

GET returns the encrypted envelope and CouchDB `_rev`; PUT includes that revision.
A stale write returns HTTP 409. loge rereads and merges instead of overwriting the
new revision blindly. A missing document on first connection creates a new setup;
a document removed after an established sync is reported for explicit recovery.
Wrong credentials, wrong recovery keys and invalid configurations leave the local
setup intact. Use **Sync Now** to retry after correcting the server connection.

References: [CouchDB document API](https://docs.couchdb.org/en/stable/api/document/common.html),
[CouchDB Docker installation](https://docs.couchdb.org/en/stable/install/docker.html).
