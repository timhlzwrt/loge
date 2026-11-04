import argparse, base64, hashlib, http.client, json, os, pathlib, secrets, subprocess, time
parser = argparse.ArgumentParser(description='Bootstrap a fresh loge configuration CouchDB instance. Run as root after copying Compose, local.ini and validate.js.')
parser.add_argument('--directory', default='/opt/loge-sync')
parser.add_argument('--host', default='127.0.0.1')
args = parser.parse_args()
root = pathlib.Path(args.directory).resolve()
if not (root.is_dir() and all(((root / f).is_file() for f in ('docker-compose.yml', 'local.ini', 'validate.js')))):
    raise RuntimeError('Bootstrap failed. Inspect the service state before retrying.')
if (root / 'secrets').exists():
    raise RuntimeError('Already bootstrapped: refusing to replace credentials')
if not (not (root / 'data').exists() or not any((root / 'data').iterdir())):
    raise RuntimeError('Data already exists')
(root / 'data').mkdir(mode=0o700, exist_ok=True)
os.chown(root / 'data', 5984, 5984)
(root / 'secrets').mkdir(mode=0o700)
admin = secrets.token_urlsafe(36)
password = secrets.token_urlsafe(36)
salt = secrets.token_hex(16)
hashed = hashlib.pbkdf2_hmac('sha256', admin.encode(), salt.encode(), 600000).hex()
p = root / 'secrets/admin.ini'
p.write_text('[admins]\nloge-admin = -pbkdf2:sha256-' + hashed + ',' + salt + ',600000\n')
os.chown(p, 5984, 5984)
p.chmod(0o400)
p = root / 'secrets/bootstrap.json'
p.write_text(json.dumps({'admin': admin, 'username': 'loge-sync', 'password': password}))
p.chmod(0o600)
subprocess.run(['docker', 'compose', '-f', str(root / 'docker-compose.yml'), 'config', '--quiet'], check=True)
subprocess.run(['docker', 'compose', '-f', str(root / 'docker-compose.yml'), 'up', '-d'], check=True)

def req(method, path, data=None, user='loge-admin', pw=admin):
    c = http.client.HTTPConnection(args.host, 5984, timeout=15)
    h = {'Authorization': 'Basic ' + base64.b64encode((user + ':' + pw).encode()).decode(), 'Content-Type': 'application/json'}
    c.request(method, path, json.dumps(data) if data is not None else None, h)
    r = c.getresponse()
    body = r.read()
    c.close()
    return (r.status, json.loads(body) if body else None)
for _ in range(40):
    try:
        if req('GET', '/_up')[0] == 200:
            break
    except OSError:
        pass
    time.sleep(0.5)
if req('GET', '/_up')[0] != 200:
    raise RuntimeError('Bootstrap failed. Inspect the service state before retrying.')
for db in ('_users', '_replicator', 'loge'):
    if req('PUT', '/' + db)[0] not in (201, 202, 412):
        raise RuntimeError('Bootstrap failed. Inspect the service state before retrying.')
if not req('PUT', '/_users/org.couchdb.user:loge-sync', {'name': 'loge-sync', 'password': password, 'roles': [], 'type': 'user'})[0] == 201:
    raise RuntimeError('Bootstrap failed. Inspect the service state before retrying.')
if not req('PUT', '/loge/_security', {'admins': {'names': ['loge-admin'], 'roles': []}, 'members': {'names': ['loge-sync'], 'roles': []}})[0] == 200:
    raise RuntimeError('Bootstrap failed. Inspect the service state before retrying.')
validator = (root / 'validate.js').read_text()
if not req('PUT', '/loge/_design/configuration', {'validate_doc_update': validator})[0] == 201:
    raise RuntimeError('Bootstrap failed. Inspect the service state before retrying.')
if not req('GET', '/loge/configuration', user='loge-sync', pw=password)[0] == 404:
    raise RuntimeError('Bootstrap failed. Inspect the service state before retrying.')
print('Backend bootstrapped; private document is empty; credentials stored root-only')
