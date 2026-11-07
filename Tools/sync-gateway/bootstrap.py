"""Add gateway-only credentials and validation to an existing single-user backend."""
import argparse
import base64
import json
import os
from pathlib import Path
import secrets
import urllib.error
import urllib.parse
import urllib.request

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--directory', default='/opt/loge-sync')
parser.add_argument('--database-url', default='http://127.0.0.1:5984/loge')
parser.add_argument('--admin-user', default='loge-admin')
args = parser.parse_args()
root = Path(args.directory).resolve()
credentials = json.loads((root / 'secrets/bootstrap.json').read_text())
authorization = 'Basic ' + base64.b64encode((args.admin_user + ':' + credentials['admin']).encode()).decode()
database = args.database_url.rstrip('/')
server = database.rsplit('/', 1)[0]


def request(method, url, data=None):
    encoded = json.dumps(data).encode() if data is not None else None
    req = urllib.request.Request(url, data=encoded, method=method,
        headers={'Authorization': authorization, 'Content-Type': 'application/json'})
    try:
        with urllib.request.urlopen(req, timeout=15) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        if error.code == 404:
            return None
        raise RuntimeError('Gateway bootstrap request failed with HTTP ' + str(error.code)) from None


def write_secret(path, value):
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o400)
    with os.fdopen(descriptor, 'w') as output:
        output.write(value)
    os.chown(path, 5984, 5984)


credential_path = root / 'secrets/gateway.json'
if not credential_path.exists():
    write_secret(credential_path, json.dumps({'username': 'loge-sync-gateway', 'password': secrets.token_urlsafe(48)}))
gateway = json.loads(credential_path.read_text())
user_url = server + '/_users/' + urllib.parse.quote('org.couchdb.user:' + gateway['username'], safe='')
user = request('GET', user_url)
if user is None:
    request('PUT', user_url, {'name': gateway['username'], 'password': gateway['password'],
                            'roles': ['loge_sync_gateway'], 'type': 'user'})
elif user.get('roles') != ['loge_sync_gateway']:
    raise RuntimeError('Existing gateway account has unexpected roles; inspect before continuing.')
security = request('GET', database + '/_security')
names = security.setdefault('members', {}).setdefault('names', [])
if gateway['username'] not in names:
    names.append(gateway['username'])
    request('PUT', database + '/_security', security)
validator = request('GET', database + '/_design/configuration') or {}
validator['validate_doc_update'] = Path(__file__).with_name('validate.js').read_text()
request('PUT', database + '/_design/configuration', validator)
admin_token = root / 'secrets/gateway-admin-token'
if not admin_token.exists():
    write_secret(admin_token, secrets.token_urlsafe(48))
print('Gateway credentials and validator ready; legacy configuration preserved.')
