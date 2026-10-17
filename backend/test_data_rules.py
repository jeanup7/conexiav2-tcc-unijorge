import base64
import io
import sqlite3
import time
import unittest
import tempfile
from pathlib import Path
from unittest.mock import patch
from PIL import Image
from repository import Repository
from service import Service
from security import ApiError, digest
from test_image_data import png_bytes


class DataRulesTests(unittest.TestCase):
    def setUp(self):
        self.repo = Repository(':memory:')
        self.api = Service(self.repo, development=True)
        for uid in ('a', 'b', 'c', 'kid', 'kid2'):
            child = uid.startswith('kid')
            self.repo.execute('INSERT INTO users(id,email,password,name,birth,verified,private,messages) VALUES(?,?,?,?,?,1,?,1)',
                (uid, uid+'@example.com', 'unused', uid, '2015-01-01' if child else '1990-01-01', int(child)))
            self.repo.execute('INSERT INTO sessions VALUES(?,?,?,?,?)', (digest(uid), digest(uid+'refresh'), uid, time.time()+900, time.time()+86400))
        for cid, guardian in (('kid', 'a'), ('kid2', 'b')):
            self.repo.execute('INSERT INTO guardian_links VALUES(?,?,?,?,?,?)', (cid, guardian, 'Private name', 1, 'active', time.time()))

    def tearDown(self):
        self.repo.db.close()

    def call(self, method, path, data=None, actor='a', key=None):
        return self.api.dispatch(method, path, data or {}, actor, idempotency_key=key)

    def denied(self, status, operation):
        with self.assertRaises(ApiError) as caught:
            operation()
        self.assertEqual(status, caught.exception.status)

    def invite(self, source='kid', target='b'):
        return self.call('POST', '/contacts', {'target': target}, source)['requestId']

    def consent(self, rid, cid='kid', actor='a', approve=True):
        return self.call('PATCH', '/guardian/children/'+cid+'/contacts/'+rid, {'approved': approve}, actor)

    def test_recipient_cannot_bypass_guardian(self):
        rid = self.invite()
        result = self.call('POST', '/contacts/approve', {'target': 'kid'}, 'b')
        self.assertEqual('awaiting_guardian', result['status'])
        self.assertFalse(self.api.contact('kid', 'b'))
        self.assertEqual('approved', self.consent(rid)['status'])
        self.assertTrue(self.api.contact('kid', 'b'))
        self.assertTrue(self.api.contact('b', 'kid'))

    def test_two_minors_require_both_guardians_and_recipient(self):
        rid = self.invite(target='kid2')
        self.consent(rid)
        self.consent(rid, 'kid2', 'b')
        self.assertFalse(self.api.contact('kid', 'kid2'))
        self.call('POST', '/contacts/approve', {'target': 'kid'}, 'kid2')
        self.assertTrue(self.api.contact('kid', 'kid2'))

    def test_child_and_unrelated_adult_cannot_forge_consent(self):
        rid = self.invite()
        self.denied(404, lambda: self.consent(rid, actor='kid'))
        self.denied(404, lambda: self.consent(rid, actor='c'))
        self.denied(404, lambda: self.call('GET', '/guardian/children/kid/contacts', actor='c'))
        self.assertFalse(self.api.contact('kid', 'b'))

    def test_parent_cannot_approve_unrelated_invitation(self):
        rid = self.invite('c', 'b')
        self.denied(404, lambda: self.consent(rid))

    def test_paused_family_blocks_consent(self):
        rid = self.invite()
        self.call('PATCH', '/guardian/children/kid', {'state': 'paused'})
        self.denied(403, lambda: self.consent(rid))

    def test_parent_rejection_cannot_be_reaccepted(self):
        rid = self.invite()
        self.consent(rid, approve=False)
        self.denied(404, lambda: self.call('POST', '/contacts/approve', {'target': 'kid'}, 'b'))
        self.assertFalse(self.api.contact('kid', 'b'))

    def test_expired_invitation_is_not_resurrected_by_accept(self):
        rid = self.invite()
        self.repo.execute('UPDATE contact_requests SET expires=0 WHERE id=?', (rid,))
        self.denied(404, lambda: self.call('POST', '/contacts/approve', {'target': 'kid'}, 'b'))
        self.assertEqual([], self.call('GET', '/contacts/requests', actor='b')['items'])

    def test_reverse_request_does_not_implicitly_accept(self):
        rid = self.invite('a', 'b')
        self.assertEqual(rid, self.invite('b', 'a'))
        self.assertFalse(self.api.contact('a', 'b'))

    def test_guardian_can_withdraw_approved_contact(self):
        rid = self.invite()
        self.call('POST', '/contacts/approve', {'target': 'kid'}, 'b')
        self.consent(rid)
        self.assertEqual('approved', self.call('GET', '/guardian/children/kid/contacts')['items'][0]['status'])
        self.consent(rid, approve=False)
        self.denied(403, lambda: self.call('POST', '/messages/b', {'text': 'blocked'}, 'kid'))

    def test_changed_guardian_does_not_inherit_previous_contact_consent(self):
        rid=self.invite()
        self.call('POST','/contacts/approve',{'target':'kid'},'b')
        self.consent(rid)
        self.repo.execute("UPDATE guardian_links SET guardian='c' WHERE child='kid'")
        self.assertFalse(self.api.contact('kid','b'))
        self.denied(403,lambda:self.call('POST','/messages/b',{'text':'blocked'},'kid'))
        self.assertEqual('pending',self.call('GET','/guardian/children/kid/contacts',actor='c')['items'][0]['status'])
        self.consent(rid,actor='c')
        self.assertTrue(self.api.contact('kid','b'))

    def test_unblock_does_not_restore_previous_approval(self):
        self.invite('a', 'b')
        self.call('POST', '/contacts/approve', {'target': 'a'}, 'b')
        self.call('POST', '/blocks', {'target': 'b'})
        self.call('DELETE', '/blocks/b')
        self.assertFalse(self.api.contact('a', 'b'))
        self.denied(403, lambda: self.call('POST', '/messages/b', {'text': 'blocked'}))

    def test_notification_failure_rolls_back_message(self):
        self.invite('a', 'b')
        self.call('POST', '/contacts/approve', {'target': 'a'}, 'b')
        with patch.object(self.api, 'notification', side_effect=sqlite3.OperationalError('simulated disk failure')):
            with self.assertRaises(sqlite3.OperationalError):
                self.call('POST', '/messages/b', {'text': 'must roll back'})
        self.assertEqual([], self.repo.rows('SELECT * FROM messages'))

    def test_partial_profile_update_preserves_preferences_and_requires_explicit_nickname(self):
        self.call('PATCH','/me',{'bio':'new bio'})
        profile=self.call('GET','/me')
        self.assertEqual(1,profile['messages'])
        self.assertEqual(0,profile['private'])
        self.assertEqual('a',profile['name'])
        self.repo.execute("UPDATE guardian_links SET nickname_selected=0 WHERE child='kid'")
        self.call('PATCH','/me',{'bio':'hello'},'kid')
        self.assertTrue(self.call('GET','/me',actor='kid')['needsNickname'])
        self.denied(403,lambda:self.call('GET','/posts',actor='kid'))

    def test_nested_transaction_does_not_commit_outer_failure(self):
        with self.assertRaises(RuntimeError):
            with self.repo.transaction():
                self.repo.execute("UPDATE users SET name='changed' WHERE id='a'")
                with self.repo.transaction():
                    self.repo.execute("UPDATE users SET name='changed' WHERE id='b'")
                raise RuntimeError('fail')
        self.assertEqual('a', self.repo.one("SELECT name FROM users WHERE id='a'")['name'])
        self.assertEqual('b', self.repo.one("SELECT name FROM users WHERE id='b'")['name'])

    def test_idempotent_creation_and_fingerprint_conflict(self):
        key = 'operation_test_123456'
        first = self.call('POST', '/posts', {'text': 'one'}, key=key)
        second = self.call('POST', '/posts', {'text': 'one'}, key=key)
        self.assertEqual(first, second)
        self.assertEqual(1, len(self.repo.rows('SELECT * FROM posts')))
        self.denied(409, lambda: self.call('POST', '/posts', {'text': 'two'}, key=key))
        other = self.call('POST', '/posts', {'text': 'one'}, 'b', key)
        self.assertNotEqual(first, other)

    def test_idempotent_replay_still_checks_current_permissions(self):
        key = 'operation_test_123456'
        self.call('POST', '/posts', {'text': 'one'}, 'kid', key)
        self.call('PATCH', '/guardian/children/kid', {'state': 'paused'})
        self.denied(403, lambda: self.call('POST', '/posts', {'text': 'one'}, 'kid', key))

    def test_legacy_auth_routes_are_disabled_outside_development(self):
        self.api.development = False
        for path in ('/auth/register', '/auth/login', '/auth/refresh', '/auth/verify', '/auth/recover', '/auth/reset'):
            self.denied(404, lambda: self.call('POST', path, {}))

    def test_truncated_image_and_wrong_mime_are_rejected(self):
        for content, mime in ((b'\x89PNG\r\n\x1a\nimage', 'image/png'), (png_bytes(), 'image/jpeg')):
            self.denied(400, lambda: self.call('POST', '/media', {'mime': mime, 'data': base64.b64encode(content).decode()}))
        self.assertEqual([], self.repo.rows('SELECT * FROM media'))

    def test_image_metadata_is_removed_and_quota_enforced(self):
        out = io.BytesIO()
        image = Image.new('RGB', (4, 4), 'blue')
        exif = Image.Exif(); exif[270] = 'private location'
        image.save(out, format='JPEG', exif=exif)
        mid = self.call('POST', '/media', {'mime': 'image/jpeg', 'data': base64.b64encode(out.getvalue()).decode()})['id']
        stored = self.repo.one('SELECT data FROM media WHERE id=?', (mid,))['data']
        with Image.open(io.BytesIO(stored)) as saved:
            self.assertFalse(saved.getexif())
        self.api.media_quota = len(stored)
        self.denied(413, lambda: self.call('POST', '/media', {'mime': 'image/png', 'data': base64.b64encode(png_bytes()).decode()}))

    def test_deletion_survives_firebase_outage_and_blocks_reregistration(self):
        class Provider:
            offline = True
            def verify(self, bearer):
                return {'uid': 'firebase-a', 'email': 'a@example.com', 'email_verified': True, 'auth_time': time.time()}
            def delete(self, uid):
                if self.offline: raise ApiError(503, 'offline')
        provider = Provider()
        self.api.firebase = provider
        self.repo.execute('INSERT INTO firebase_identities VALUES(?,?)', ('firebase-a', 'a'))
        self.call('DELETE', '/me')
        self.assertIsNone(self.repo.one("SELECT id FROM users WHERE id='a'"))
        self.assertIsNone(self.repo.one('SELECT completed FROM identity_deletions')['completed'])
        self.denied(401, lambda: self.call('POST', '/auth/firebase', {'name': 'retry', 'birth': '1990-01-01'}))
        provider.offline = False
        self.repo.execute('UPDATE identity_deletions SET next_attempt=0')
        self.api.process_identity_deletions()
        self.assertIsNotNone(self.repo.one('SELECT completed FROM identity_deletions')['completed'])

    def test_restart_migration_keeps_pending_requests_and_media(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'data.sqlite3'
            repo = Repository(path)
            for uid in ('one', 'two'):
                repo.execute('INSERT INTO users(id,email,password,name,birth) VALUES(?,?,?,?,?)',
                    (uid,uid+'@example.com','unused',uid,'1990-01-01'))
            repo.execute("INSERT INTO contacts VALUES('one','two',0)")
            repo.execute('INSERT INTO media VALUES(?,?,?,?)', ('photo','one','image/png',png_bytes()))
            repo.db.close()
            for _ in range(2):
                repo = Repository(path)
                try:
                    self.assertEqual(1,len(repo.rows('SELECT * FROM contact_requests')))
                    self.assertEqual(0,repo.one('SELECT accepted FROM contact_requests')['accepted'])
                    self.assertEqual(png_bytes(),repo.one('SELECT data FROM media')['data'])
                    self.assertEqual(1,repo.db.execute('PRAGMA user_version').fetchone()[0])
                finally:
                    repo.db.close()

    def test_migration_revokes_legacy_minor_connections_without_consent(self):
        with tempfile.TemporaryDirectory() as directory:
            path=Path(directory)/'data.sqlite3'
            repo=Repository(path)
            for uid,birth in [('adult','1990-01-01'),('kid','2015-01-01')]:
                repo.execute('INSERT INTO users(id,email,password,name,birth) VALUES(?,?,?,?,?)',
                    (uid,uid+'@example.com','unused',uid,birth))
            repo.execute("INSERT INTO contacts VALUES('adult','kid',1)")
            repo.execute("INSERT INTO contacts VALUES('kid','adult',1)")
            repo.db.close()
            repo=Repository(path)
            try: self.assertEqual([],repo.rows('SELECT * FROM contacts'))
            finally: repo.db.close()

    def test_backup_includes_wal_and_refuses_overwrite(self):
        from backup import backup
        with tempfile.TemporaryDirectory() as directory:
            source, output = Path(directory)/'source.sqlite3', Path(directory)/'copy.sqlite3'
            repo = Repository(source)
            try:
                repo.execute('INSERT INTO users(id,email,password,name,birth) VALUES(?,?,?,?,?)',
                    ('one','one@example.com','unused','one','1990-01-01'))
                backup(source,output)
                connection=sqlite3.connect(output)
                try:
                    self.assertEqual('one',connection.execute('SELECT id FROM users').fetchone()[0])
                finally:
                    connection.close()
                with self.assertRaises(ValueError): backup(source,output)
            finally:
                repo.db.close()

    def test_cleanup_preserves_unattached_recent_upload(self):
        from maintenance import purge
        mid=self.call('POST','/media',{'mime':'image/png','data':base64.b64encode(png_bytes()).decode()})['id']
        purge(self.repo)
        self.assertIsNotNone(self.repo.one('SELECT id FROM media WHERE id=?',(mid,)))
        self.repo.execute('UPDATE media_created SET created=0 WHERE media=?',(mid,))
        purge(self.repo)
        self.assertIsNone(self.repo.one('SELECT id FROM media WHERE id=?',(mid,)))

    def test_repeated_concurrent_operation_has_one_effect(self):
        from concurrent.futures import ThreadPoolExecutor
        with ThreadPoolExecutor(max_workers=2) as pool:
            futures=[pool.submit(self.call,'POST','/posts',{'text':'same'},'a','concurrent_123456789') for _ in range(2)]
            results=[f.result() for f in futures]
        self.assertEqual(results[0],results[1])
        self.assertEqual(1,len(self.repo.rows('SELECT * FROM posts')))
