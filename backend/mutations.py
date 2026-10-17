"""Persist creation receipts in the same transaction as their side effects."""
import hashlib
import json
import re
import time
from security import ApiError


def supported(method, path):
    parts = path.strip('/').split('/')
    return method == 'POST' and (path in ('/posts', '/stories', '/media', '/reports', '/family/discussions') or
        (len(parts) == 2 and parts[0] == 'messages') or
        (len(parts) == 4 and parts[:2] == ['guardian', 'children'] and parts[3] == 'discussions'))


def execute(service, actor, method, path, data, key, operation):
    if not isinstance(key, str) or not re.fullmatch(r'[A-Za-z0-9_-]{16,128}', key):
        raise ApiError(400, 'Identificador da operação inválido.')
    service.active(actor)
    fingerprint = hashlib.sha256(json.dumps([method, path, data], sort_keys=True, separators=(',', ':'), ensure_ascii=False).encode()).hexdigest()
    repo = service.repo
    repo.execute('DELETE FROM mutation_receipts WHERE expires<=?', (time.time(),))
    previous = repo.one('SELECT * FROM mutation_receipts WHERE actor=? AND key=?', (actor['id'], key))
    if previous:
        if previous['fingerprint'] != fingerprint:
            raise ApiError(409, 'Este identificador já foi usado em outra operação.')
        return json.loads(previous['response'])
    result = operation()
    repo.execute('INSERT INTO mutation_receipts VALUES(?,?,?,?,?)', (actor['id'], key, fingerprint, json.dumps(result), time.time() + 86400))
    return result
