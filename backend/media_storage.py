"""Private cloud objects with durable upload/deletion queues; legacy BLOB reads remain valid."""
import base64
import hashlib
import re
import time
from security import ApiError


def object_key(media_id):
    return 'conexia/media/'+hashlib.sha256(media_id.encode()).hexdigest()


class FirebaseMediaStorage:
    def __init__(self, app, bucket_name):
        from firebase_admin import storage
        self.bucket_name=bucket_name
        self.bucket=storage.bucket(bucket_name,app=app)
        self.bucket.reload(timeout=15)
        policy=self.bucket.get_iam_policy(requested_policy_version=3,timeout=15)
        if any(set(binding['members']) & {'allUsers','allAuthenticatedUsers'} for binding in policy.bindings):
            raise ValueError('O bucket de mídia não pode ter acesso público.')
        if self.bucket.iam_configuration.public_access_prevention!='enforced':
            raise ValueError('Ative a prevenção de acesso público no bucket antes de habilitar a mídia.')

    def put(self, key, content, mime, checksum):
        from google.api_core.exceptions import PreconditionFailed
        blob=self.bucket.blob(key)
        blob.metadata={'conexia_sha256':checksum}
        blob.cache_control='private, no-store'
        try:
            blob.upload_from_string(content,content_type=mime,if_generation_match=0,timeout=20,retry=None)
        except PreconditionFailed:
            # Resume a transfer committed remotely before the local transaction.
            blob.reload(timeout=15)
            if (blob.metadata or {}).get('conexia_sha256')!=checksum or int(blob.size)!=len(content):
                raise ValueError('Objeto remoto diferente; nenhuma imagem será sobrescrita.')
        return str(blob.generation)

    def generation(self,key):
        from google.api_core.exceptions import NotFound
        blob=self.bucket.blob(key)
        try:blob.reload(timeout=20,retry=None)
        except NotFound:return None
        return str(blob.generation)

    def read(self, key, generation):
        return self.bucket.blob(key,generation=int(generation)).download_as_bytes(timeout=20,retry=None)

    def delete(self, key, generation):
        from google.api_core.exceptions import NotFound
        if not re.fullmatch(r'conexia/media/[0-9a-f]{64}',key):
            raise ValueError('Objeto fora do espaço de mídia do Conexia.')
        try:self.bucket.blob(key).delete(if_generation_match=int(generation),timeout=20,retry=None)
        except NotFound:pass


class CloudRead:
    def __init__(self,store,row):
        self.store=store
        self.reference=tuple(row[k] for k in ('id','bucket','object_key','generation','sha256','mime'))
    def download(self):
        _,_,key,generation,checksum,mime=self.reference
        try:
            content=self.store.read(key,generation)
            if hashlib.sha256(content).hexdigest()!=checksum:raise ValueError('Checksum mismatch')
        except Exception:
            raise ApiError(503,'Não foi possível carregar a imagem privada. Tente novamente.') from None
        return {'mime':mime,'data':base64.b64encode(content).decode()}


def read_media(service, mid):
    row=service.repo.one('SELECT m.*,o.bucket,o.object_key,o.generation,o.sha256 FROM media m LEFT JOIN media_objects o ON o.media=m.id WHERE m.id=?',(mid,))
    if not row:raise ApiError(404,'Imagem indisponível.')
    content=row['data']
    if content is None:
        store=service.media_storage
        if not store or row['bucket']!=store.bucket_name:
            raise ApiError(503,'O armazenamento privado desta imagem não está configurado.')
        return CloudRead(store,row)
    return {'mime':row['mime'],'data':base64.b64encode(content).decode()}


def process_jobs(service, limit=3):
    store=service.media_storage
    if not store:return {'uploaded':0,'deleted':0,'failed':0}
    result={'uploaded':0,'deleted':0,'failed':0}
    r=service.repo
    # A transfer journal survives account deletion and a process crash after
    # remote upload. The grace period exceeds the bounded remote request timeout.
    for transfer in r.rows('SELECT t.* FROM media_transfers t LEFT JOIN media m ON m.id=t.media WHERE m.id IS NULL AND t.bucket=? AND t.created<? ORDER BY t.created LIMIT ?',(store.bucket_name,time.time()-300,limit)):
        try:
            generation=store.generation(transfer['object_key'])
            with r.transaction():
                if generation and not r.one('SELECT 1 FROM media_objects WHERE bucket=? AND object_key=? AND generation=?',(store.bucket_name,transfer['object_key'],generation)):
                    r.execute('INSERT OR IGNORE INTO media_deletions VALUES(?,?,?,?)',(store.bucket_name,transfer['object_key'],generation,time.time()))
                r.execute('DELETE FROM media_transfers WHERE media=?',(transfer['media'],))
        except Exception:result['failed']+=1
    for row in r.rows('SELECT m.* FROM media_uploads q JOIN media m ON m.id=q.media WHERE m.data IS NOT NULL ORDER BY q.created LIMIT ?',(limit,)):
        try:
            key=object_key(row['id']);checksum=hashlib.sha256(row['data']).hexdigest()
            # Network I/O runs outside the API lock. Reconcile after upload so
            # an account deleted during transfer cannot leave a live object.
            r.execute('INSERT OR IGNORE INTO media_transfers VALUES(?,?,?,?)',(row['id'],store.bucket_name,key,time.time()))
            generation=store.put(key,row['data'],row['mime'],checksum)
            with r.transaction():
                current=r.one('SELECT data FROM media WHERE id=?',(row['id'],))
                if current and current['data']==row['data']:
                    r.execute('INSERT INTO media_objects VALUES(?,?,?,?,?,?)',(row['id'],store.bucket_name,key,generation,len(row['data']),checksum))
                    r.execute('UPDATE media SET data=NULL WHERE id=?',(row['id'],))
                    r.execute('DELETE FROM media_uploads WHERE media=?',(row['id'],))
                    result['uploaded']+=1
                elif not r.one('SELECT 1 FROM media_objects WHERE bucket=? AND object_key=? AND generation=?',(store.bucket_name,key,generation)):
                    r.execute('INSERT OR IGNORE INTO media_deletions VALUES(?,?,?,?)',(store.bucket_name,key,generation,time.time()))
                r.execute('DELETE FROM media_transfers WHERE media=?',(row['id'],))
        except Exception:
            result['failed']+=1
            # Keep both durable job and local bytes for retry; never lose the photo.
    for row in r.rows('SELECT * FROM media_deletions WHERE bucket=? ORDER BY created LIMIT ?',(store.bucket_name,limit)):
        try:
            store.delete(row['object_key'],row['generation'])
            r.execute('DELETE FROM media_deletions WHERE bucket=? AND object_key=? AND generation=?',(row['bucket'],row['object_key'],row['generation']))
            result['deleted']+=1
        except Exception:result['failed']+=1
    return result
