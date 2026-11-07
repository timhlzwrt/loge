import base64
import copy
import json
import threading
import unittest
from concurrent.futures import ThreadPoolExecutor

from pathlib import Path

from fastapi import HTTPException
from fastapi.testclient import TestClient
from gateway import create_app, digest

# The same examples the app's Core tests send and decode, so a field renamed on either side fails.
CONTRACT = json.loads((Path(__file__).resolve().parents[2]
                       / 'Core/Tests/LogeCoreTests/Fixtures/sync-gateway-contract.json').read_text())


class MemoryStore:
    def __init__(self):
        self.documents = {}
        self.lock = threading.Lock()

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
            return saved['_rev']


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

    def test_share_grants_only_group_access_and_leave_revokes_it(self):
        a, auth_a = self.account('A')
        b, auth_b = self.account('B')
        _, auth_c = self.account('C')
        created = self.public.post('/v2/invitations', headers=auth_a, json={'kind': 'share', 'name': 'Household', 'categories': ['addons']}).json()
        group = created['groupID']
        path = '/v2/groups/' + group + '/document'
        self.assertEqual(self.public.put(path, headers=auth_a, json=self.envelope).status_code, 200)
        self.assertEqual(self.public.get(path, headers=auth_b).status_code, 404)
        joined = self.public.post('/v2/join', headers=auth_b, json={'code': created['code']})
        self.assertEqual(joined.status_code, 200)
        self.assertEqual(joined.json()['categories'], ['addons'])
        self.assertEqual(self.public.get(path, headers=auth_b).status_code, 200)
        self.assertEqual(self.public.get(path, headers=auth_c).status_code, 404)
        self.assertEqual(self.public.get('/v2/documents/progress', headers=auth_b).status_code, 404)
        self.assertEqual(self.public.post('/v2/invitations', headers=auth_b, json={'kind': 'share', 'groupID': group}).status_code, 403)
        self.assertEqual(self.public.post('/v2/invitations', headers=auth_a, json={'kind': 'share', 'groupID': group}).status_code, 200)
        self.assertEqual(self.public.delete('/v2/groups/' + group + '/membership', headers=auth_b).status_code, 200)
        self.assertEqual(self.public.get(path, headers=auth_b).status_code, 404)

    def test_revoke_device_and_disable_account_take_effect_immediately(self):
        account, authorization = self.account('A')
        self.assertEqual(self.public.get('/v2/me', headers=authorization).status_code, 200)
        self.assertEqual(self.admin.patch('/admin/accounts/' + account['accountID'], headers=self.admin_headers, json={'enabled': False}).status_code, 200)
        self.assertEqual(self.public.get('/v2/me', headers=authorization).status_code, 401)
        self.admin.patch('/admin/accounts/' + account['accountID'], headers=self.admin_headers, json={'enabled': True})
        self.assertEqual(self.public.delete('/v2/devices/' + account['deviceID'], headers=authorization).status_code, 200)
        self.assertEqual(self.public.get('/v2/me', headers=authorization).status_code, 401)

    def test_owner_leaving_stops_shared_access_without_deleting_data(self):
        _, auth_a = self.account('A')
        _, auth_b = self.account('B')
        invitation = self.public.post('/v2/invitations', headers=auth_a,
            json={'kind': 'share', 'categories': ['addons']}).json()
        group_id = invitation['groupID']
        path = '/v2/groups/' + group_id + '/document'
        self.assertEqual(self.public.put(path, headers=auth_a, json=self.envelope).status_code, 200)
        self.assertEqual(self.public.post('/v2/join', headers=auth_b, json={'code': invitation['code']}).status_code, 200)
        self.assertEqual(self.public.delete('/v2/groups/' + group_id + '/membership', headers=auth_a).status_code, 200)
        self.assertEqual(self.public.get(path, headers=auth_b).status_code, 404)
        self.assertEqual(self.public.get('/v2/me', headers=auth_b).json()['groups'], [])
        self.assertIsNotNone(self.store.get('shared:' + group_id))

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

    def test_disabled_owner_stops_sharing_for_existing_members(self):
        owner, auth_a = self.account('A')
        _, auth_b = self.account('B')
        invitation = self.public.post('/v2/invitations', headers=auth_a,
            json={'kind': 'share', 'categories': ['addons']}).json()
        path = '/v2/groups/' + invitation['groupID'] + '/document'
        self.assertEqual(self.public.put(path, headers=auth_a, json=self.envelope).status_code, 200)
        self.assertEqual(self.public.post('/v2/join', headers=auth_b, json={'code': invitation['code']}).status_code, 200)
        self.assertEqual(self.public.get(path, headers=auth_b).status_code, 200)
        self.admin.patch('/admin/accounts/' + owner['accountID'], headers=self.admin_headers, json={'enabled': False})
        self.assertEqual(self.public.get(path, headers=auth_b).status_code, 404)
        self.assertEqual(self.public.get('/v2/me', headers=auth_b).json()['groups'], [])

    def test_malformed_record_ids_are_not_found_on_every_route(self):
        _, authorization = self.account('A')
        for path in ('/v2/devices/..%2Faccount', '/v2/invitations/not-a-digest'):
            self.assertEqual(self.public.delete(path, headers=authorization).status_code, 404)
        for method, path in (('patch', '/admin/accounts/x'), ('patch', '/admin/groups/x'),
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
        _, auth_b = self.account('B')
        check('inviteDevice', self.public.post('/v2/invitations', headers=auth_a, json=CONTRACT['inviteDevice']['request']))
        share = self.public.post('/v2/invitations', headers=auth_a, json=CONTRACT['inviteShare']['request'])
        check('inviteShare', share)
        check('join', self.public.post('/v2/join', headers=auth_b, json=CONTRACT['join']['request'] | {'code': share.json()['code']}))
        check('me', self.public.get('/v2/me', headers=auth_b))
        check('putDocument', self.public.put('/v2/documents/progress', headers=auth_a, json=CONTRACT['putDocument']['request']))
        check('getDocument', self.public.get('/v2/documents/progress', headers=auth_a))
        check('devices', self.public.get('/v2/devices', headers=auth_a))

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

    def test_invalid_envelope_and_untrusted_group_metadata_are_rejected(self):
        _, authorization = self.account('A')
        for body in [self.envelope | {'_attachments': {}}, self.envelope | {'version': True}, {'version': 2, 'ciphertext': '!'}, self.envelope | {'_id': 'account:someone'}]:
            self.assertEqual(self.public.put('/v2/documents/progress', headers=authorization, json=body).status_code, 400)
        for categories in [['progress'], [{}], [], ['addons', 'addons']]:
            self.assertEqual(self.public.post('/v2/invitations', headers=authorization, json={'kind': 'share', 'categories': categories}).status_code, 400)
        self.assertEqual(self.public.put('/v2/documents/progress', headers=authorization, content=b'x' * 1_048_577).status_code, 413)

    def test_expired_and_revoked_invitations_cannot_be_redeemed(self):
        account = self.app.state.service.create_account('A')
        invitation = self.store.get('invitation:' + digest(account['invitation']['code']))
        invitation['expires'] = 0
        self.store.put(invitation)
        result = self.public.post('/v2/redeem', json={'code': account['invitation']['code'], 'deviceName': 'Phone'})
        self.assertEqual(result.status_code, 410)
        invitation = self.app.state.service.invitation(account['accountID'], 'device')
        self.admin.delete('/admin/access/' + invitation['id'], headers=self.admin_headers)
        result = self.public.post('/v2/redeem', json={'code': invitation['code'], 'deviceName': 'Phone'})
        self.assertEqual(result.status_code, 410)


if __name__ == '__main__':
    unittest.main()
