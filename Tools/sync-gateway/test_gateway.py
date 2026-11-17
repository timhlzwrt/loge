import base64
import copy
import json
import threading
import time
import unittest
from concurrent.futures import ThreadPoolExecutor

from pathlib import Path

from fastapi import HTTPException
from fastapi.testclient import TestClient
import hashlib
import urllib.parse

from gateway import AdminLogin, create_app, digest

# The same examples the app's Core tests send and decode, so a field renamed on either side fails.
CONTRACT = json.loads((Path(__file__).resolve().parents[2]
                       / 'Core/Tests/LogeCoreTests/Fixtures/sync-gateway-contract.json').read_text())


class MemoryStore:
    def __init__(self):
        self.documents = {}
        self.lock = threading.Lock()
        # As CouchDB's changes feed: a database-wide sequence, and when each document last changed.
        self.sequence = 0
        self.changed_at = {}
        self.changed = threading.Condition(self.lock)

    def get(self, identifier):
        with self.lock:
            return copy.deepcopy(self.documents.get(identifier))

    def list(self, prefix):
        with self.lock:
            return [copy.deepcopy(value) for key, value in self.documents.items() if key.startswith(prefix)]

    def put(self, document):
        with self.lock:
            existing = self.documents.get(document['_id'])
            if existing is not None and existing['_rev'] != document.get('_rev'):
                raise HTTPException(409, 'Revision conflict')
            if existing is None and document.get('_rev'):
                raise HTTPException(409, 'Revision conflict')
            saved = copy.deepcopy(document)
            saved['_rev'] = str(int(existing['_rev']) + 1) if existing else '1'
            self.documents[document['_id']] = saved
            self.sequence += 1
            self.changed_at[document['_id']] = self.sequence
            self.changed.notify_all()
            return saved['_rev']

    def revisions(self, identifiers):
        with self.lock:
            return {key: self.documents[key]['_rev'] for key in identifiers if key in self.documents}, self.sequence

    def wait(self, identifiers, since, seconds):
        deadline = time.monotonic() + seconds
        with self.changed:
            while True:
                found = {key: self.documents[key]['_rev'] for key in identifiers if self.changed_at.get(key, 0) > since}
                remaining = deadline - time.monotonic()
                if found or remaining <= 0:
                    return found
                self.changed.wait(remaining)


class GatewayTests(unittest.TestCase):
    def setUp(self):
        self.store = MemoryStore()
        self.app = create_app(self.store)
        self.public = TestClient(self.app)
        self.admin = TestClient(create_app(self.store, mode='admin', admin_secret='a' * 40), base_url='http://localhost')
        self.admin_headers = {'X-Admin-Token': 'a' * 40}
        self.envelope = {'version': 2, 'ciphertext': base64.b64encode(b'x' * 40).decode()}

    def account(self, name):
        result = self.admin.post('/admin/accounts', headers=self.admin_headers, json={'displayName': name})
        self.assertEqual(result.status_code, 200)
        created = result.json()
        result = self.public.post('/v2/redeem', json={'code': created['invitation']['code'], 'deviceName': name + ' phone'})
        self.assertEqual(result.status_code, 200)
        credential = result.json()
        return credential, {'Authorization': 'Bearer ' + credential['token']}

    def test_private_documents_are_isolated_and_cas_protected(self):
        a, auth_a = self.account('A')
        b, auth_b = self.account('B')
        saved = self.public.put('/v2/documents/progress', headers=auth_a, json=self.envelope)
        self.assertEqual(saved.status_code, 200)
        self.assertEqual(self.public.get('/v2/documents/progress', headers=auth_b).status_code, 404)
        self.assertEqual(self.public.put('/v2/documents/progress', headers=auth_a, json=self.envelope).status_code, 409)
        updated = self.envelope | {'_rev': saved.json()['rev']}
        self.assertEqual(self.public.put('/v2/documents/progress', headers=auth_a, json=updated).status_code, 200)
        self.assertEqual(self.public.get('/v2/documents/' + a['accountID'], headers=auth_b).status_code, 404)
        self.assertEqual(self.public.get('/v2/documents/progress').status_code, 401)
        self.assertEqual(self.public.get('/admin/accounts', headers=self.admin_headers).status_code, 404)

    def test_watch_later_is_a_private_document_and_counts_as_existing_data(self):
        a, auth_a = self.account('A')
        _, auth_b = self.account('B')
        self.assertEqual(self.public.put('/v2/documents/watchLater', headers=auth_a, json=self.envelope).status_code, 200)
        self.assertEqual(self.public.get('/v2/documents/watchLater', headers=auth_a).status_code, 200)
        self.assertEqual(self.public.get('/v2/documents/watchLater', headers=auth_b).status_code, 404)
        self.assertEqual(self.public.put('/v2/documents/other', headers=auth_a, json=self.envelope).status_code, 404)
        invitation = self.admin.post('/admin/accounts/' + a['accountID'] + '/invitation', headers=self.admin_headers).json()
        self.assertEqual(self.public.post('/v2/redeem', json={'code': invitation['code'], 'deviceName': 'New'}).status_code, 428)

    def test_document_fetch_answers_not_modified_for_the_revision_the_device_has(self):
        _, auth_a = self.account('A')
        _, auth_b = self.account('B')
        saved = self.public.put('/v2/documents/progress', headers=auth_a, json=self.envelope).json()['rev']
        fetched = self.public.get('/v2/documents/progress', headers=auth_a)
        self.assertEqual(fetched.headers['ETag'], '"' + saved + '"')
        unchanged = self.public.get('/v2/documents/progress', headers=auth_a | {'If-None-Match': '"' + saved + '"'})
        self.assertEqual((unchanged.status_code, unchanged.content), (304, b''))
        # Another account's document with the same revision is still not found.
        self.assertEqual(self.public.get('/v2/documents/progress', headers=auth_b | {'If-None-Match': '"' + saved + '"'}).status_code, 404)
        self.public.put('/v2/documents/progress', headers=auth_a, json=self.envelope | {'_rev': saved})
        changed = self.public.get('/v2/documents/progress', headers=auth_a | {'If-None-Match': '"' + saved + '"'})
        self.assertEqual(changed.status_code, 200)
        self.assertNotEqual(changed.json()['_rev'], saved)

    def test_changes_wait_for_the_accounts_own_documents_only(self):
        public = TestClient(create_app(self.store, changes_seconds=1))
        a, auth_a = self.account('A')
        b, auth_b = self.account('B')
        self.assertEqual(public.get('/v2/changes').status_code, 401)
        self.assertEqual(public.get('/v2/changes', headers=auth_a, params={'since': '../x'}).status_code, 400)
        # Without a position it answers at once, naming the documents there are.
        self.assertEqual(public.get('/v2/changes', headers=auth_a).json(), {'changes': [], 'since': ',,'})
        public.put('/v2/documents/progress', headers=auth_a, json=self.envelope)
        start = public.get('/v2/changes', headers=auth_a).json()
        self.assertEqual(start['changes'], ['progress'])

        def poll():
            began = time.monotonic()
            response = public.get('/v2/changes', headers=auth_a, params={'since': start['since']})
            return response, time.monotonic() - began
        with ThreadPoolExecutor(max_workers=1) as pool:
            waiting = pool.submit(poll)
            time.sleep(0.2)
            # The other account's writes neither wake this account's request nor show in it.
            public.put('/v2/documents/progress', headers=auth_b, json=self.envelope)
            public.put('/v2/documents/configuration', headers=auth_b, json=self.envelope)
            response, elapsed = waiting.result()
        self.assertGreaterEqual(elapsed, 0.9)
        self.assertEqual(response.json(), {'changes': [], 'since': start['since']})
        self.assertNotIn(b['accountID'], response.text)

        with ThreadPoolExecutor(max_workers=1) as pool:
            waiting = pool.submit(poll)
            time.sleep(0.2)
            public.put('/v2/documents/watchLater', headers=auth_a, json=self.envelope)
            response, elapsed = waiting.result()
        self.assertLess(elapsed, 0.9)
        self.assertEqual(response.json()['changes'], ['watchLater'])
        # A position from before a change answers at once.
        self.assertEqual(public.get('/v2/changes', headers=auth_a, params={'since': start['since']}).json()['changes'], ['watchLater'])
        self.assertEqual(public.get('/v2/changes', headers=auth_a, params={'since': ''}).json()['changes'], ['progress', 'watchLater'])

    def test_device_enrollment_consumes_code_once_under_concurrent_requests(self):
        created = self.app.state.service.create_account('A')
        code = created['invitation']['code']
        with ThreadPoolExecutor(max_workers=6) as pool:
            results = list(pool.map(lambda _: self.public.post('/v2/redeem', json={'code': code, 'deviceName': 'phone'}), range(6)))
        self.assertEqual(sum(result.status_code == 200 for result in results), 1)
        self.assertEqual(sum(result.status_code == 410 for result in results), 5)
        serialized = json.dumps(self.store.documents)
        self.assertNotIn(code, serialized)
        token = next(result.json()['token'] for result in results if result.status_code == 200)
        self.assertNotIn(token, serialized)
        self.assertNotIn(token.split('.')[1], serialized)

    def test_shared_setup_routes_of_older_apps_are_gone_not_broken(self):
        _, authorization = self.account('A')
        path = '/v2/groups/fedcba9876543210fedcba9876543210/'
        for method, route in (('get', path + 'document'), ('put', path + 'document'), ('delete', path + 'membership')):
            body = {} if method != 'put' else {'json': self.envelope}
            self.assertEqual(getattr(self.public, method)(route, headers=authorization, **body).status_code, 410, route)
        self.assertEqual(self.public.post('/v2/join', headers=authorization, json={'code': 'x'}).status_code, 410)
        share = {'kind': 'share', 'name': 'Shared setup', 'categories': ['addons']}
        self.assertEqual(self.public.post('/v2/invitations', headers=authorization, json=share).status_code, 410)
        self.assertEqual(self.public.post('/v2/invitations', headers=authorization, json={'kind': 'other'}).status_code, 400)
        self.assertEqual(self.public.get('/v2/me', headers=authorization).json()['groups'], [])
        self.assertFalse(any(key.startswith(('group:', 'shared:')) for key in self.store.documents))
        self.assertEqual(set(self.admin.get('/admin/access', headers=self.admin_headers).json()), {'devices', 'invitations'})

    def test_revoke_device_and_disable_account_take_effect_immediately(self):
        account, authorization = self.account('A')
        self.assertEqual(self.public.get('/v2/me', headers=authorization).status_code, 200)
        self.assertEqual(self.admin.patch('/admin/accounts/' + account['accountID'], headers=self.admin_headers, json={'enabled': False}).status_code, 200)
        self.assertEqual(self.public.get('/v2/me', headers=authorization).status_code, 401)
        self.admin.patch('/admin/accounts/' + account['accountID'], headers=self.admin_headers, json={'enabled': True})
        self.assertEqual(self.public.delete('/v2/devices/' + account['deviceID'], headers=authorization).status_code, 200)
        self.assertEqual(self.public.get('/v2/me', headers=authorization).status_code, 401)

    def test_missing_recovery_key_does_not_consume_returning_account_code(self):
        account, authorization = self.account('A')
        self.assertEqual(self.public.put('/v2/documents/configuration', headers=authorization,
            json=self.envelope).status_code, 200)
        invitation = self.admin.post('/admin/accounts/' + account['accountID'] + '/invitation',
            headers=self.admin_headers).json()
        request = {'code': invitation['code'], 'deviceName': 'New phone'}
        self.assertEqual(self.public.post('/v2/redeem', json=request).status_code, 428)
        result = self.public.post('/v2/redeem', json=request | {'hasRecoveryKey': True})
        self.assertEqual(result.status_code, 200)
        self.assertEqual(set(result.json()), {'token', 'accountID', 'displayName', 'deviceID'})

    def test_each_revoke_route_only_revokes_its_own_kind_of_record(self):
        account, authorization = self.account('A')
        invitation = self.public.post('/v2/invitations', headers=authorization, json={'kind': 'device'}).json()
        self.assertEqual(self.public.delete('/v2/devices/' + invitation['id'], headers=authorization).status_code, 404)
        self.assertEqual(self.public.delete('/v2/invitations/' + account['deviceID'], headers=authorization).status_code, 404)
        self.assertEqual(self.public.get('/v2/me', headers=authorization).status_code, 200)
        self.assertEqual(self.public.delete('/v2/invitations/' + invitation['id'], headers=authorization).status_code, 200)
        self.assertEqual(self.public.post('/v2/redeem', json={'code': invitation['code'], 'deviceName': 'Late'}).status_code, 410)

    def test_malformed_record_ids_are_not_found_on_every_route(self):
        _, authorization = self.account('A')
        for path in ('/v2/devices/..%2Faccount', '/v2/invitations/not-a-digest'):
            self.assertEqual(self.public.delete(path, headers=authorization).status_code, 404)
        for method, path in (('patch', '/admin/accounts/x'),
                             ('post', '/admin/accounts/x/invitation'), ('delete', '/admin/access/x')):
            body = {} if method == 'delete' else {'json': {'enabled': False}}
            response = getattr(self.admin, method)(path, headers=self.admin_headers, **body)
            self.assertEqual(response.status_code, 404, path)

    def test_responses_match_the_shared_app_contract(self):
        def keys(value):
            return set(value[0] if isinstance(value, list) else value)
        def check(name, response):
            self.assertEqual(response.status_code, 200, name)
            self.assertEqual(keys(response.json()), keys(CONTRACT[name]['response']), name)

        created = self.admin.post('/admin/accounts', headers=self.admin_headers, json={'displayName': 'A'}).json()
        redeem = self.public.post('/v2/redeem', json=CONTRACT['redeem']['request'] | {'code': created['invitation']['code']})
        check('redeem', redeem)
        auth_a = {'Authorization': 'Bearer ' + redeem.json()['token']}
        check('inviteDevice', self.public.post('/v2/invitations', headers=auth_a, json=CONTRACT['inviteDevice']['request']))
        check('me', self.public.get('/v2/me', headers=auth_a))
        check('putDocument', self.public.put('/v2/documents/progress', headers=auth_a, json=CONTRACT['putDocument']['request']))
        check('getDocument', self.public.get('/v2/documents/progress', headers=auth_a))
        check('devices', self.public.get('/v2/devices', headers=auth_a))
        check('changes', self.public.get('/v2/changes', headers=auth_a))

    def test_explicit_https_admin_origin_preserves_authentication_and_origin_checks(self):
        from unittest.mock import patch
        with patch.dict("os.environ", {"SYNC_ADMIN_ORIGIN": "https://sync.lan.example"}):
            admin = TestClient(create_app(self.store, mode="admin", admin_secret="a" * 40),
                               base_url="https://sync.lan.example")
        self.assertEqual(admin.get("/").status_code, 200)
        self.assertEqual(admin.get("/admin/accounts").status_code, 401)
        headers = self.admin_headers | {"Origin": "https://sync.lan.example"}
        self.assertEqual(admin.get("/admin/accounts", headers=headers).status_code, 200)
        for origin in ("https://attacker.example", "http://sync.lan.example", "http://localhost"):
            self.assertEqual(admin.get("/admin/accounts", headers=headers | {"Origin": origin}).status_code, 403)
        self.assertEqual(admin.get("/", headers={"Host": "attacker.example"}).status_code, 403)
        self.assertEqual(admin.get("/", headers={"Host": "sync.lan.example.attacker.example"}).status_code, 403)
        self.assertEqual(admin.get("/admin/accounts", headers=self.admin_headers | {"Host": "localhost"}).status_code, 200)

    def test_admin_requires_secret_local_host_and_same_origin(self):
        self.assertEqual(self.admin.get('/admin/accounts').status_code, 401)
        self.assertEqual(self.admin.get('/admin/accounts', headers=self.admin_headers | {'Origin': 'https://attacker.example'}).status_code, 403)
        self.assertEqual(self.admin.get('/admin/accounts', headers=self.admin_headers | {'Host': 'attacker.example'}).status_code, 403)
        self.assertEqual(self.admin.post('/admin/accounts', headers=self.admin_headers, json={'displayName': '<script>alert(1)</script>'}).status_code, 200)
        self.assertIn("frame-ancestors 'none'", self.admin.get('/').headers['Content-Security-Policy'])

    def test_malformed_credentials_are_rejected_without_server_errors(self):
        self.assertEqual(self.admin.get('/admin/accounts', headers={'X-Admin-Token': b'\xe9'}).status_code, 401)
        for secret in [b'\xe9', b'', b'x' * 200, b'not a valid token']:
            authorization = b'Bearer ' + b'a' * 64 + b'.' + secret
            self.assertEqual(self.public.get('/v2/me', headers={'Authorization': authorization}).status_code, 401)

    def test_invalid_envelopes_are_rejected(self):
        _, authorization = self.account('A')
        for body in [self.envelope | {'_attachments': {}}, self.envelope | {'version': True}, {'version': 2, 'ciphertext': '!'}, self.envelope | {'_id': 'account:someone'}]:
            self.assertEqual(self.public.put('/v2/documents/progress', headers=authorization, json=body).status_code, 400)
        self.assertEqual(self.public.put('/v2/documents/progress', headers=authorization, content=b'x' * 1_048_577).status_code, 413)

    def test_expired_and_revoked_invitations_cannot_be_redeemed(self):
        account = self.app.state.service.create_account('A')
        invitation = self.store.get('invitation:' + digest(account['invitation']['code']))
        invitation['expires'] = 0
        self.store.put(invitation)
        result = self.public.post('/v2/redeem', json={'code': account['invitation']['code'], 'deviceName': 'Phone'})
        self.assertEqual(result.status_code, 410)
        invitation = self.app.state.service.invitation(account['accountID'])
        self.admin.delete('/admin/access/' + invitation['id'], headers=self.admin_headers)
        result = self.public.post('/v2/redeem', json={'code': invitation['code'], 'deviceName': 'Phone'})
        self.assertEqual(result.status_code, 410)


class ProviderLogin(AdminLogin):
    """Answers as Pocket ID would, recording each request."""
    def __init__(self, groups=('loge-admins',)):
        super().__init__('https://id.example', 'loge-admin', 'loge-admins', 'Pocket ID')
        self.groups = list(groups)
        self.requests = []

    def fetch(self, url, form=None, token=None):
        self.requests.append((url, form, token))
        if url == 'https://id.example/.well-known/openid-configuration':
            return {'issuer': 'https://id.example', 'authorization_endpoint': 'https://id.example/authorize',
                    'token_endpoint': 'https://id.example/api/oidc/token', 'userinfo_endpoint': 'https://id.example/api/oidc/userinfo'}
        if url.endswith('/token'):
            return {'access_token': 'access-' + form['code']}
        if url.endswith('/userinfo') and token == 'access-good':
            return {'sub': 'user-1', 'name': 'Tim', 'groups': self.groups}
        raise OSError('unexpected request')


class AdminSignInTests(unittest.TestCase):
    def client(self, login):
        return TestClient(create_app(MemoryStore(), mode='admin', admin_secret='a' * 40, admin_login=login),
                          base_url='http://localhost:5986', follow_redirects=False)

    def sign_in(self, admin, code='good'):
        location = urllib.parse.urlsplit(admin.get('/oidc/login').headers['location'])
        query = dict(urllib.parse.parse_qsl(location.query))
        return query, admin.get('/oidc/callback', params={'state': query['state'], 'code': code})

    def test_group_member_signs_in_with_pkce_and_signs_out(self):
        login = ProviderLogin()
        admin = self.client(login)
        self.assertEqual(admin.get('/admin/session').json(), {'signIn': True, 'provider': 'Pocket ID', 'name': None})
        query, callback = self.sign_in(admin)
        self.assertEqual((query['client_id'], query['redirect_uri'], query['code_challenge_method']),
                         ('loge-admin', 'http://localhost:5986/oidc/callback', 'S256'))
        verifier = next(form for url, form, _ in login.requests if url.endswith('/token'))['code_verifier']
        challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).rstrip(b'=').decode()
        self.assertEqual(challenge, query['code_challenge'])
        self.assertTrue(callback.headers['location'].startswith('/#session='))
        session = {'X-Admin-Session': callback.headers['location'].split('=', 1)[1]}
        self.assertEqual(admin.get('/admin/session', headers=session).json()['name'], 'Tim')
        self.assertEqual(admin.get('/admin/accounts', headers=session).status_code, 200)
        self.assertEqual(admin.get('/admin/accounts', headers=session | {'Origin': 'http://localhost:3000'}).status_code, 403)
        self.assertEqual(admin.get('/oidc/callback', params={'state': query['state'], 'code': 'good'}).headers['location'], '/#signin=failed')
        admin.delete('/admin/session', headers=session)
        self.assertEqual(admin.get('/admin/accounts', headers=session).status_code, 401)

    def test_users_outside_the_group_and_failed_sign_ins_get_no_session(self):
        _, callback = self.sign_in(self.client(ProviderLogin(groups=['media'])))
        self.assertEqual(callback.headers['location'], '/#signin=denied')
        _, callback = self.sign_in(self.client(ProviderLogin()), code='rejected')
        self.assertEqual(callback.headers['location'], '/#signin=failed')
        admin = self.client(ProviderLogin())
        self.assertEqual(admin.get('/oidc/callback', params={'state': 'forged', 'code': 'good'}).headers['location'], '/#signin=failed')
        self.assertEqual(admin.get('/admin/accounts', headers={'X-Admin-Session': 'forged'}).status_code, 401)

    def test_token_still_works_while_the_provider_is_down(self):
        login = ProviderLogin()
        login.fetch = lambda *arguments, **keywords: (_ for _ in ()).throw(OSError('down'))
        admin = self.client(login)
        self.assertEqual(admin.get('/oidc/login').headers['location'], '/#signin=unavailable')
        self.assertEqual(admin.get('/admin/accounts', headers={'X-Admin-Token': 'a' * 40}).status_code, 200)

    def test_sign_in_is_off_without_configuration_and_requires_https(self):
        admin = TestClient(create_app(MemoryStore(), mode='admin', admin_secret='a' * 40), base_url='http://localhost')
        self.assertEqual(admin.get('/admin/session').json()['signIn'], False)
        self.assertEqual(admin.get('/oidc/login').status_code, 404)
        with self.assertRaises(ValueError):
            AdminLogin('http://id.example', 'loge-admin', 'loge-admins')
        with self.assertRaises(ValueError):
            AdminLogin('https://id.example', 'loge-admin', '')


if __name__ == '__main__':
    unittest.main()
