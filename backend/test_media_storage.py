import base64
import hashlib
import time
import unittest
from repository import Repository
from service import Service
from security import ApiError, digest
from test_image_data import png_bytes
from migrate_media_storage import migrate


class FakeStorage:
    bucket_name='private-test-bucket'
    def __init__(self):
        self.objects={}; self.unavailable=False; self.after_put=None
    def put(self,key,content,mime,checksum):
        if self.unavailable:raise ConnectionError('unavailable')
        if key in self.objects and self.objects[key][2]!=checksum:raise ValueError('immutable object')
        self.objects[key]=('1',content,checksum)
        if self.after_put:self.after_put()
        return '1'
    def generation(self,key):
        return self.objects[key][0] if key in self.objects else None
    def read(self,key,generation):
        if self.unavailable:raise ConnectionError('unavailable')
        return self.objects[key][1]
    def delete(self,key,generation):
        if self.unavailable:raise ConnectionError('unavailable')
        self.objects.pop(key,None)


class CloudMediaTests(unittest.TestCase):
    def setUp(self):
        self.repo=Repository(':memory:');self.addCleanup(self.repo.db.close)
        self.store=FakeStorage()
        self.api=Service(self.repo,development=True,media_storage=self.store)
        for uid in ('a','b','kid'):
            self.repo.execute('INSERT INTO users(id,email,password,name,birth,verified,private) VALUES(?,?,?,?,?,1,?)',(uid,uid+'@example.com','unused',uid,'2012-01-01' if uid=='kid' else '1990-01-01',int(uid!='b')))
            self.repo.execute('INSERT INTO sessions VALUES(?,?,?,?,?)',(digest(uid),digest(uid+'refresh'),uid,time.time()+900,time.time()+3600))
        self.repo.execute("INSERT INTO guardian_links VALUES('kid','a','private',1,'active',1)")

    def call(self,method,path,data=None,actor='a'):
        return self.api.dispatch(method,path,data or {},actor)
    def upload(self,actor='a'):
        return self.call('POST','/media',{'mime':'image/png','data':base64.b64encode(png_bytes()).decode()},actor)['id']
    def denied(self,status,action):
        with self.assertRaises(ApiError) as error:action()
        self.assertEqual(status,error.exception.status)

    def test_legacy_and_cloud_media_use_same_private_endpoint(self):
        mid=self.upload();original=self.call('GET','/media/'+mid)
        self.denied(404,lambda:self.call('GET','/media/'+mid,actor='b'))
        self.assertEqual(1,self.api.process_media_jobs()['uploaded'])
        self.assertIsNone(self.repo.one('SELECT data FROM media WHERE id=?',(mid,))['data'])
        self.assertEqual(original,self.call('GET','/media/'+mid))
        self.denied(404,lambda:self.call('GET','/media/'+mid,actor='b'))
        exported=self.call('GET','/me/export')['media'][0]
        self.assertGreater(exported['bytes'],0)
        self.assertNotIn('bucket',exported)

    def test_failed_upload_keeps_blob_and_can_retry(self):
        mid=self.upload();self.store.unavailable=True
        self.assertEqual(1,self.api.process_media_jobs()['failed'])
        self.assertIsNotNone(self.repo.one('SELECT data FROM media WHERE id=?',(mid,))['data'])
        self.assertIsNotNone(self.repo.one('SELECT * FROM media_uploads WHERE media=?',(mid,)))
        self.call('GET','/media/'+mid)
        self.store.unavailable=False
        self.assertEqual(1,self.api.process_media_jobs()['uploaded'])
        self.assertEqual(0,self.api.process_media_jobs()['uploaded'])

    def test_account_deleted_during_upload_does_not_orphan_remote_object(self):
        self.upload()
        self.store.after_put=lambda:self.repo.execute("DELETE FROM users WHERE id='a'")
        self.api.process_media_jobs()
        self.assertEqual({},self.store.objects)
        self.assertEqual([],self.repo.rows('SELECT * FROM media_uploads'))
        self.assertEqual([],self.repo.rows('SELECT * FROM media_objects'))

    def test_delete_job_survives_cloud_failure_and_database_cascade(self):
        self.upload();self.api.process_media_jobs()
        self.store.unavailable=True
        self.repo.execute("DELETE FROM users WHERE id='a'")
        self.assertEqual(1,self.api.process_media_jobs()['failed'])
        self.assertEqual(1,len(self.repo.rows('SELECT * FROM media_deletions')))
        self.store.unavailable=False
        self.assertEqual(1,self.api.process_media_jobs()['deleted'])
        self.assertEqual({},self.store.objects)

    def test_quota_counts_cloud_bytes_and_missing_configuration_fails_closed(self):
        mid=self.upload();self.api.process_media_jobs()
        self.api.media_quota=1
        self.denied(413,self.upload)
        self.api.media_storage=None
        self.denied(503,lambda:self.call('GET','/media/'+mid))

    def test_checksum_failure_never_returns_remote_content(self):
        mid=self.upload();self.api.process_media_jobs()
        key=next(iter(self.store.objects))
        self.store.objects[key]=('1',b'corrupt','incorrect')
        self.denied(503,lambda:self.call('GET','/media/'+mid))

    def test_batch_migration_preserves_ids_posts_and_family_authorization(self):
        self.api.media_storage=None
        mid=self.upload('b');pid=self.call('POST','/posts',{'text':'family reference','media':mid},'b')['id']
        self.call('POST','/posts/'+pid+'/view',{'visibleMs':3000},'kid')
        endpoint=f'/guardian/children/kid/activity/posts/{pid}/media/{mid}'
        original=self.call('GET',endpoint)
        self.api.media_storage=self.store
        self.assertEqual(1,migrate(self.api,[mid])['uploaded'])
        self.assertEqual(original,self.call('GET',endpoint))
        self.call('PATCH','/guardian/children/kid',{'state':'paused'})
        self.assertEqual(original,self.call('GET',endpoint))
        self.denied(403,lambda:self.call('GET','/media/'+mid,actor='kid'))
        self.assertEqual([],self.repo.rows('PRAGMA foreign_key_check'))

    def test_lost_upload_reply_and_deleted_account_are_reconciled_after_restart(self):
        self.upload()
        def lost_reply():raise ConnectionError('lost remote response')
        self.store.after_put=lost_reply
        self.assertEqual(1,self.api.process_media_jobs()['failed'])
        self.assertEqual(1,len(self.repo.rows('SELECT * FROM media_transfers')))
        self.repo.execute("DELETE FROM users WHERE id='a'")
        self.repo.execute('UPDATE media_transfers SET created=1')
        self.store.after_put=None
        restarted=Service(self.repo,development=True,media_storage=self.store)
        self.assertEqual(1,restarted.process_media_jobs()['deleted'])
        self.assertEqual({},self.store.objects)
        self.assertEqual([],self.repo.rows('SELECT * FROM media_transfers'))

    def test_block_during_cloud_download_is_rechecked_before_response(self):
        mid=self.upload('b')
        self.call('POST','/posts',{'text':'photo','media':mid},'b')
        self.api.process_media_jobs()
        read=self.store.read
        def blocked_read(key,generation):
            content=read(key,generation)
            self.call('POST','/blocks',{'target':'a'},'b')
            return content
        self.store.read=blocked_read
        self.denied(404,lambda:self.call('GET','/media/'+mid))

class FirebaseAdapterTests(unittest.TestCase):
    def storage(self,bindings=None):
        from unittest.mock import MagicMock,patch
        from media_storage import FirebaseMediaStorage
        bucket=MagicMock()
        bucket.get_iam_policy.return_value.bindings=bindings or []
        bucket.iam_configuration.public_access_prevention='enforced'
        with patch('firebase_admin.storage.bucket',return_value=bucket):
            return FirebaseMediaStorage(None,'private-test'),bucket

    def test_public_bucket_is_rejected(self):
        with self.assertRaises(ValueError):
            self.storage([{'role':'roles/storage.objectViewer','members':{'allUsers'}}])

    def test_upload_retry_accepts_only_matching_remote_object(self):
        from google.api_core.exceptions import PreconditionFailed
        storage,bucket=self.storage()
        blob=bucket.blob.return_value
        blob.upload_from_string.side_effect=PreconditionFailed('exists')
        blob.size=3;blob.generation=42
        # reload restores server metadata, as the real SDK does.
        checksum=hashlib.sha256(b'abc').hexdigest()
        blob.reload.side_effect=lambda **kwargs:setattr(blob,'metadata',{'conexia_sha256':checksum})
        self.assertEqual('42',storage.put('key',b'abc','image/png',checksum))
        blob.reload.side_effect=lambda **kwargs:setattr(blob,'metadata',{'conexia_sha256':'different'})
        with self.assertRaises(ValueError):storage.put('key',b'abc','image/png',checksum)

    def test_cloud_delete_rejects_foreign_object_and_uses_generation(self):
        storage,bucket=self.storage()
        with self.assertRaises(ValueError):storage.delete('other-app/file','42')
        from media_storage import object_key
        storage.delete(object_key('photo'),'42')
        bucket.blob.return_value.delete.assert_called_once_with(if_generation_match=42,timeout=20,retry=None)
