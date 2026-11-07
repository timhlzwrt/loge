"""Small authenticated boundary around one private CouchDB application database."""
import base64
import copy
import hashlib
import hmac
import json
import os
import re
import secrets
import time
import threading
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

from fastapi import FastAPI, HTTPException, Request, Response
from fastapi.responses import HTMLResponse
from starlette.concurrency import run_in_threadpool

MAX_BODY = 1_048_576
CATEGORIES = {"addons", "playback", "appearance"}
ID = re.compile(r"^[a-f0-9]{32}$")


def fail(status, message):
    raise HTTPException(status_code=status, detail=message)


def digest(value):
    return hashlib.sha256(value.encode()).hexdigest()


def now():
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


class CouchStore:
    def __init__(self, endpoint, credential_file):
        self.endpoint = endpoint.rstrip("/")
        credential = json.loads(Path(credential_file).read_text())
        self.authorization = "Basic " + base64.b64encode(
            (credential["username"] + ":" + credential["password"]).encode()).decode()

    def request(self, method, path, document=None):
        body = json.dumps(document).encode() if document is not None else None
        request = urllib.request.Request(self.endpoint + path, data=body, method=method,
            headers={"Authorization": self.authorization, "Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(request, timeout=10) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            if error.code == 404:
                return None
            if error.code == 409:
                fail(409, "Document changed. Fetch its latest revision and retry.")
            fail(503, "Sync storage is unavailable.")
        except (OSError, ValueError):
            fail(503, "Sync storage is unavailable.")

    def get(self, identifier):
        return self.request("GET", "/" + urllib.parse.quote(identifier, safe=""))

    def put(self, document):
        result = self.request("PUT", "/" + urllib.parse.quote(document["_id"], safe=""), document)
        return result["rev"]

    def list(self, prefix):
        query = urllib.parse.urlencode({"include_docs": "true", "startkey": json.dumps(prefix),
                                       "endkey": json.dumps(prefix + "\uffff")})
        result = self.request("GET", "/_all_docs?" + query)
        return [row["doc"] for row in result["rows"] if "doc" in row]


class Service:
    def __init__(self, store):
        self.store = store
        # One public worker coordinates membership checks spanning group/invitation documents.
        self.membership_lock = threading.RLock()

    def update(self, identifier, change):
        for _ in range(5):
            document = self.store.get(identifier)
            if document is None:
                fail(404, "Not found.")
            result = change(document)
            try:
                self.store.put(document)
                return result
            except HTTPException as error:
                if error.status_code != 409:
                    raise
        fail(409, "Changed concurrently. Try again.")

    def authenticate(self, request):
        authorization = request.headers.get("Authorization", "")
        if not authorization.startswith("Bearer "):
            fail(401, "Connect this device to continue.")
        parts = authorization[7:].split(".")
        if len(parts) != 2 or not re.fullmatch(r"[a-f0-9]{64}", parts[0]) or not re.fullmatch(r"[A-Za-z0-9_-]{32,128}", parts[1]):
            fail(401, "Device credential is invalid.")
        invitation = self.store.get("invitation:" + parts[0])
        device = invitation.get("device") if invitation else None
        if not device or invitation.get("revoked") or not hmac.compare_digest(device["tokenHash"], digest(parts[1])):
            fail(401, "This device is no longer connected.")
        account = self.store.get("account:" + invitation["accountID"])
        if not account or not account.get("enabled"):
            fail(401, "This account is disabled.")
        return account, invitation

    def invitation(self, account_id, kind, group_id=None):
        code = secrets.token_urlsafe(32)
        identifier = digest(code)
        document = {"_id": "invitation:" + identifier, "type": "invitation", "kind": kind,
                    "accountID": account_id, "expires": time.time() + 86400, "createdAt": now(),
                    "consumed": False, "revoked": False}
        if group_id:
            document["groupID"] = group_id
        self.store.put(document)
        result = {"id": identifier, "code": code,
                  "expiresAt": datetime.fromtimestamp(document["expires"], timezone.utc).isoformat().replace("+00:00", "Z")}
        if group_id:
            result["groupID"] = group_id
        return result

    def consume(self, code, kind, account_id=None, device_name=None, has_recovery_key=False):
        if not isinstance(code, str) or len(code) > 128:
            fail(400, "Invitation code is invalid.")
        identifier = digest(code)
        secret = secrets.token_urlsafe(32)
        def change(document):
            if document["kind"] != kind or document["consumed"] or document["revoked"] or document["expires"] <= time.time():
                fail(410, "Invitation expired or already used.")
            owner = self.store.get("account:" + document["accountID"])
            if not owner or not owner.get("enabled"):
                fail(410, "Invitation is no longer available.")
            requires_key = kind == "device" and any(self.store.get("document:" + owner["id"] + ":" + item) is not None
                                                    for item in ("configuration", "progress"))
            if requires_key and not has_recovery_key:
                fail(428, "This account already has encrypted data. Enter its recovery key or use Add My Device on a connected device.")
            document["consumed"] = True
            if kind == "device":
                document["device"] = {"id": identifier, "name": device_name, "createdAt": now(), "tokenHash": digest(secret)}
                return {"token": identifier + "." + secret, "accountID": owner["id"],
                        "displayName": owner["displayName"], "deviceID": identifier,
                        "requiresRecoveryKey": requires_key}
            if account_id == document["accountID"]:
                fail(400, "You already own this group.")
            group = self.store.get("group:" + document["groupID"])
            if not group or not group.get("enabled"):
                fail(410, "Shared setup is no longer available.")
            if any(set(group["categories"]) & set(existing["categories"]) for existing in self.groups(account_id)):
                fail(409, "Leave the existing shared setup for these settings before joining another.")
            document["joinedBy"] = account_id
            return group_summary(group)
        return self.update("invitation:" + identifier, change)

    def groups(self, account_id):
        joined = {document.get("groupID") for document in self.store.list("invitation:")
                  if document.get("joinedBy") == account_id and not document.get("revoked")}
        return [group for group in self.store.list("group:")
                if group.get("enabled") and (group["ownerID"] == account_id or group["id"] in joined)]

    def group(self, account_id, group_id):
        if not ID.fullmatch(group_id):
            fail(404, "Shared setup not found.")
        group = next((group for group in self.groups(account_id) if group["id"] == group_id), None)
        if group is None:
            fail(404, "Shared setup not found.")
        return group

    def create_account(self, display_name):
        identifier = secrets.token_hex(16)
        self.store.put({"_id": "account:" + identifier, "type": "account", "id": identifier,
                        "displayName": display_name, "enabled": True, "createdAt": now()})
        return {"accountID": identifier, "displayName": display_name,
                "invitation": self.invitation(identifier, "device")}


def group_summary(group):
    return {key: group[key] for key in ("id", "name", "categories", "ownerID")}


def envelope(document):
    return {"version": document["version"], "ciphertext": document["ciphertext"], "_rev": document["_rev"]}


async def body(request):
    data = bytearray()
    async for chunk in request.stream():
        data.extend(chunk)
        if len(data) > MAX_BODY:
            fail(413, "Request exceeds 1 MiB.")
    try:
        value = json.loads(data)
    except (ValueError, UnicodeError):
        fail(400, "Expected JSON.")
    if not isinstance(value, dict):
        fail(400, "Expected a JSON object.")
    return value


def text(value, label, maximum=80):
    if not isinstance(value, str) or not value.strip() or len(value) > maximum or any(ord(c) < 32 for c in value):
        fail(400, "Enter a valid " + label + ".")
    return value.strip()


def validate_envelope(value):
    if set(value) - {"version", "ciphertext", "_rev"} or type(value.get("version")) is not int or value["version"] != 2:
        fail(400, "Expected an encrypted configuration envelope.")
    ciphertext = value.get("ciphertext")
    if not isinstance(ciphertext, str) or len(ciphertext) > 1_000_000:
        fail(400, "Encrypted payload is invalid.")
    try:
        decoded = base64.b64decode(ciphertext, validate=True)
    except ValueError:
        fail(400, "Encrypted payload is invalid.")
    if len(decoded) < 28 or ("_rev" in value and not isinstance(value["_rev"], str)):
        fail(400, "Encrypted payload is invalid.")


def create_app(store=None, mode=None, admin_secret=None):
    store = store or CouchStore(os.environ["SYNC_DATABASE_URL"], os.environ["SYNC_DATABASE_CREDENTIAL_FILE"])
    service = Service(store)
    mode = mode or os.environ.get("SYNC_MODE", "public")
    app = FastAPI(docs_url=None, redoc_url=None, openapi_url=None)
    app.state.service = service

    @app.middleware("http")
    async def headers(request, call_next):
        response = await call_next(request)
        response.headers["Cache-Control"] = "no-store"
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["Referrer-Policy"] = "no-referrer"
        return response

    if mode == "admin":
        secret = admin_secret or Path(os.environ["SYNC_ADMIN_SECRET_FILE"]).read_text().strip()
        if len(secret) < 32:
            raise ValueError("Administrative secret must contain at least 32 characters")

        def administrator(request):
            # A local page still needs origin checks: hostile websites can target localhost.
            host = request.headers.get("host", "")
            if not re.fullmatch(r"(?:localhost|127\.0\.0\.1)(?::[0-9]+)?", host):
                fail(403, "Open the admin page through a localhost SSH tunnel.")
            if request.headers.get("origin") not in (None, "http://" + host):
                fail(403, "Origin is not allowed.")
            token = request.headers.get("X-Admin-Token", "")
            if not hmac.compare_digest(token.encode(), secret.encode()):
                fail(401, "Enter the local administrator token.")

        def enrollment_code(invitation):
            endpoint = os.environ.get("SYNC_PUBLIC_ENDPOINT")
            if endpoint:
                setup = {"version": 2, "kind": "account", "endpoint": endpoint, "code": invitation["code"]}
                invitation["setupCode"] = base64.b64encode(json.dumps(setup).encode()).decode()
            return invitation

        @app.get("/")
        def admin_page(request: Request):
            host = request.headers.get("host", "")
            if not re.fullmatch(r"(?:localhost|127\.0\.0\.1)(?::[0-9]+)?", host):
                fail(403, "Use a localhost SSH tunnel.")
            return HTMLResponse(Path(__file__).with_name("admin.html").read_text(),
                headers={"Content-Security-Policy": "default-src 'self'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'"})

        @app.get("/admin/accounts")
        def accounts(request: Request):
            administrator(request)
            return [{key: account[key] for key in ("id", "displayName", "enabled", "createdAt")}
                    for account in store.list("account:")]

        @app.post("/admin/accounts")
        async def create_account(request: Request):
            administrator(request)
            value = await body(request)
            result = await run_in_threadpool(service.create_account, text(value.get("displayName"), "name"))
            enrollment_code(result["invitation"])
            return result

        @app.patch("/admin/accounts/{account_id}")
        async def update_account(account_id: str, request: Request):
            administrator(request)
            value = await body(request)
            if not isinstance(value.get("enabled"), bool):
                fail(400, "Choose an account state.")
            await run_in_threadpool(service.update, "account:" + account_id, lambda document: document.update(enabled=value["enabled"]))
            return {"ok": True}

        @app.post("/admin/accounts/{account_id}/invitation")
        def enrollment(account_id: str, request: Request):
            administrator(request)
            account = store.get("account:" + account_id)
            if not account or not account.get("enabled"):
                fail(404, "Enabled account not found.")
            return enrollment_code(service.invitation(account_id, "device"))

        @app.get("/admin/access")
        def access(request: Request):
            administrator(request)
            devices = []
            invitations = []
            for entry in store.list("invitation:"):
                common = {"id": entry["_id"].split(":", 1)[1], "accountID": entry["accountID"],
                          "revoked": entry["revoked"], "kind": entry["kind"]}
                if entry.get("device"):
                    devices.append({**common, **{key: entry["device"][key] for key in ("name", "createdAt")}})
                elif not entry["consumed"]:
                    invitations.append({**common, "expiresAt": entry["expires"]})
            return {"devices": devices, "invitations": invitations,
                    "groups": [group_summary(group) | {"ownerID": group["ownerID"], "enabled": group["enabled"]}
                               for group in store.list("group:")]}

        @app.delete("/admin/access/{identifier}")
        def revoke(identifier: str, request: Request):
            administrator(request)
            service.update("invitation:" + identifier, lambda document: document.update(revoked=True))
            return {"ok": True}

        @app.patch("/admin/groups/{group_id}")
        async def update_group(group_id: str, request: Request):
            administrator(request)
            value = await body(request)
            if not isinstance(value.get("enabled"), bool):
                fail(400, "Choose a group state.")
            await run_in_threadpool(service.update, "group:" + group_id, lambda document: document.update(enabled=value["enabled"]))
            return {"ok": True}
        return app

    @app.get("/v2/health")
    def health():
        return {"ok": True, "version": 2}

    @app.post("/v2/redeem")
    async def redeem(request: Request):
        value = await body(request)
        return await run_in_threadpool(service.consume, value.get("code"), "device", device_name=text(value.get("deviceName"), "device name"), has_recovery_key=value.get("hasRecoveryKey") is True)

    @app.get("/v2/me")
    def me(request: Request):
        account, credential = service.authenticate(request)
        return {"accountID": account["id"], "displayName": account["displayName"],
                "deviceID": credential["device"]["id"], "groups": [group_summary(group) for group in service.groups(account["id"])]}

    def resource(request, resource):
        account, _ = service.authenticate(request)
        if resource not in ("configuration", "progress"):
            fail(404, "Document not found.")
        return "document:" + account["id"] + ":" + resource

    def read(identifier):
        document = store.get(identifier)
        if document is None:
            fail(404, "Document not found.")
        return envelope(document)

    async def write(request, identifier):
        value = await body(request)
        validate_envelope(value)
        revision = await run_in_threadpool(store.put, {**value, "_id": identifier, "type": "encrypted"})
        return {"ok": True, "rev": revision}

    @app.get("/v2/documents/{document}")
    def get_document(document: str, request: Request):
        return read(resource(request, document))

    @app.put("/v2/documents/{document}")
    async def put_document(document: str, request: Request):
        identifier = await run_in_threadpool(resource, request, document)
        return await write(request, identifier)

    @app.get("/v2/groups/{group_id}/document")
    def get_group(group_id: str, request: Request):
        account, _ = service.authenticate(request)
        service.group(account["id"], group_id)
        return read("shared:" + group_id)

    @app.put("/v2/groups/{group_id}/document")
    async def put_group(group_id: str, request: Request):
        account, _ = await run_in_threadpool(service.authenticate, request)
        await run_in_threadpool(service.group, account["id"], group_id)
        return await write(request, "shared:" + group_id)

    def create_invitation(account, value):
        with service.membership_lock:
            return create_invitation_locked(account, value)

    def create_invitation_locked(account, value):
        kind = value.get("kind")
        if kind == "device":
            return service.invitation(account["id"], kind)
        if kind == "share" and value.get("groupID"):
            group = service.group(account["id"], str(value["groupID"]))
            if group["ownerID"] != account["id"]:
                fail(403, "Only the owner can invite someone to this shared setup.")
            return service.invitation(account["id"], kind, group["id"])
        categories = value.get("categories")
        if kind != "share" or not isinstance(categories, list) or not categories or not all(isinstance(item, str) for item in categories) or len(categories) != len(set(categories)) or not set(categories) <= CATEGORIES:
            fail(400, "Choose what to share.")
        if any(set(categories) & set(group["categories"]) for group in service.groups(account["id"])):
            fail(409, "These settings already belong to a shared setup.")
        group_id = secrets.token_hex(16)
        store.put({"_id": "group:" + group_id, "type": "group", "id": group_id,
                   "name": text(value.get("name", "Shared setup"), "group name"),
                   "categories": categories, "ownerID": account["id"], "enabled": True})
        return service.invitation(account["id"], kind, group_id)

    @app.post("/v2/invitations")
    async def invite(request: Request):
        account, _ = await run_in_threadpool(service.authenticate, request)
        value = await body(request)
        return await run_in_threadpool(create_invitation, account, value)

    @app.post("/v2/join")
    async def join(request: Request):
        account, _ = await run_in_threadpool(service.authenticate, request)
        value = await body(request)
        def join_group():
            with service.membership_lock:
                return service.consume(value.get("code"), "share", account_id=account["id"])
        return await run_in_threadpool(join_group)

    @app.delete("/v2/groups/{group_id}/membership")
    def leave_group(group_id: str, request: Request):
        account, _ = service.authenticate(request)
        group = service.group(account["id"], group_id)
        if group["ownerID"] == account["id"]:
            service.update("group:" + group_id, lambda document: document.update(enabled=False))
            return {"ok": True}
        for entry in store.list("invitation:"):
            if entry.get("groupID") == group_id and entry.get("joinedBy") == account["id"] and not entry["revoked"]:
                service.update(entry["_id"], lambda document: document.update(revoked=True))
        return {"ok": True}

    @app.get("/v2/devices")
    def devices(request: Request):
        account, _ = service.authenticate(request)
        return [{key: invitation["device"][key] for key in ("id", "name", "createdAt")}
                for invitation in store.list("invitation:") if invitation["accountID"] == account["id"]
                and invitation.get("device") and not invitation["revoked"]]

    @app.get("/v2/invitations")
    def invitations(request: Request):
        account, _ = service.authenticate(request)
        return [{"id": entry["_id"].split(":", 1)[1], "kind": entry["kind"],
                 "expiresAt": datetime.fromtimestamp(entry["expires"], timezone.utc).isoformat().replace("+00:00", "Z")}
                for entry in store.list("invitation:") if entry["accountID"] == account["id"]
                and not entry["consumed"] and not entry["revoked"] and entry["expires"] > time.time()]

    def revoke_own(request, identifier):
        account, _ = service.authenticate(request)
        def change(document):
            if document["accountID"] != account["id"]:
                fail(404, "Access record not found.")
            document["revoked"] = True
        service.update("invitation:" + identifier, change)
        return {"ok": True}

    @app.delete("/v2/devices/{identifier}")
    def revoke_device(identifier: str, request: Request):
        return revoke_own(request, identifier)

    @app.delete("/v2/invitations/{identifier}")
    def revoke_invite(identifier: str, request: Request):
        return revoke_own(request, identifier)

    return app
