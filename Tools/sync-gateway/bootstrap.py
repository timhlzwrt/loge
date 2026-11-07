"""Set up, or upgrade, the CouchDB database and credentials behind the sync gateway.

Run as root in the deployment directory after copying this directory there. A fresh
directory gets a new CouchDB administrator and an empty database; an existing one keeps
its data and administrator. Either way, afterwards only the gateway's own login is a
member of the application database, and no person's login can read it directly.
"""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import secrets
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--directory', default='/opt/loge-sync')
parser.add_argument('--database-url', default='http://127.0.0.1:5984/loge')
parser.add_argument('--admin-user', default='loge-admin')
args = parser.parse_args()
root = Path(args.directory).resolve()
secret_directory = root / 'secrets'
database = args.database_url.rstrip('/')
server = database.rsplit('/', 1)[0]
COUCHDB_UID = 5984


def write_secret(path, value, owner=0):
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o400)
    with os.fdopen(descriptor, 'w') as output:
        output.write(value)
    os.chown(path, owner, owner)


def create_administrator():
    if not all((root / name).is_file() for name in ('compose.yml', 'local.ini', 'validate.js')):
        raise RuntimeError('Copy the sync-gateway directory into ' + str(root) + ' first.')
    data = root / 'data'
    if data.exists() and any(data.iterdir()):
        raise RuntimeError('data/ is not empty but secrets/ is missing; inspect before continuing.')
    data.mkdir(mode=0o700, exist_ok=True)
    os.chown(data, COUCHDB_UID, COUCHDB_UID)
    secret_directory.mkdir(mode=0o700)
    password = secrets.token_urlsafe(36)
    salt = secrets.token_hex(16)
    hashed = hashlib.pbkdf2_hmac('sha256', password.encode(), salt.encode(), 600000).hex()
    write_secret(secret_directory / 'admin.ini',
                 '[admins]\n' + args.admin_user + ' = -pbkdf2:sha256-' + hashed + ',' + salt + ',600000\n',
                 owner=COUCHDB_UID)
    write_secret(secret_directory / 'bootstrap.json', json.dumps({'admin': password}))
    compose = ['docker', 'compose', '-f', str(root / 'compose.yml')]
    # Compose checks every service's settings, including the endpoint only administration uses.
    environment = os.environ | {'SYNC_PUBLIC_ENDPOINT': os.environ.get('SYNC_PUBLIC_ENDPOINT', 'https://unset.invalid/v2')}
    subprocess.run(compose + ['config', '--quiet'], check=True, env=environment)
    subprocess.run(compose + ['up', '-d', 'couchdb'], check=True, env=environment)


fresh = not (secret_directory / 'bootstrap.json').exists()
if fresh:
    if secret_directory.exists():
        raise RuntimeError('secrets/ exists without bootstrap.json; inspect before continuing.')
    create_administrator()
administrator = json.loads((secret_directory / 'bootstrap.json').read_text())['admin']
authorization = 'Basic ' + base64.b64encode((args.admin_user + ':' + administrator).encode()).decode()


def request(method, url, data=None):
    encoded = json.dumps(data).encode() if data is not None else None
    req = urllib.request.Request(url, data=encoded, method=method,
        headers={'Authorization': authorization, 'Content-Type': 'application/json'})
    try:
        with urllib.request.urlopen(req, timeout=15) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        if error.code in (404, 412) and method in ('GET', 'PUT'):
            return None
        raise RuntimeError('Bootstrap request failed with HTTP ' + str(error.code)) from None


for _ in range(60):
    try:
        if request('GET', server + '/_up') is not None:
            break
    except (OSError, RuntimeError):
        pass
    time.sleep(0.5)
else:
    raise RuntimeError('CouchDB did not start; inspect the service state before retrying.')

for name in ('_users', '_replicator', 'loge'):
    request('PUT', server + '/' + name)

credential_path = secret_directory / 'gateway.json'
if not credential_path.exists():
    write_secret(credential_path, json.dumps({'username': 'loge-sync-gateway', 'password': secrets.token_urlsafe(48)}),
                 owner=COUCHDB_UID)
gateway = json.loads(credential_path.read_text())
user_url = server + '/_users/' + urllib.parse.quote('org.couchdb.user:' + gateway['username'], safe='')
user = request('GET', user_url)
if user is None:
    request('PUT', user_url, {'name': gateway['username'], 'password': gateway['password'],
                              'roles': ['loge_sync_gateway'], 'type': 'user'})
elif user.get('roles') != ['loge_sync_gateway']:
    raise RuntimeError('Existing gateway account has unexpected roles; inspect before continuing.')

# CouchDB membership grants read access to every document, so the gateway is the only member.
security = request('GET', database + '/_security') or {}
removed = sorted(set(security.get('members', {}).get('names', [])) - {gateway['username']})
request('PUT', database + '/_security', {'admins': {'names': [args.admin_user], 'roles': []},
                                         'members': {'names': [gateway['username']], 'roles': []}})
# The id predates the gateway; replacing the existing document keeps a single validator.
validator = request('GET', database + '/_design/configuration') or {'_id': '_design/configuration'}
validator['validate_doc_update'] = (root / 'validate.js').read_text()
request('PUT', database + '/_design/configuration', validator)

admin_token = secret_directory / 'gateway-admin-token'
if not admin_token.exists():
    write_secret(admin_token, secrets.token_urlsafe(48), owner=COUCHDB_UID)
print('Database ready; only the gateway can read it.')
if removed:
    print('Removed database access for: ' + ', '.join(removed))
