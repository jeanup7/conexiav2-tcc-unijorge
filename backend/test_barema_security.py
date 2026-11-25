"""Executable permission matrix and data lifecycle checks for the MVP."""
import os
import time
import unittest
from unittest.mock import patch
from repository import Repository
from service import Service
from security import ApiError
from firebase_identity import validate_emulator_environment
from maintenance import purge
import test_school


class PermissionMatrixTests(unittest.TestCase):
    setUp=test_school.SchoolTests.setUp
    call=test_school.SchoolTests.call
    denied=test_school.SchoolTests.denied
    invite=test_school.SchoolTests.invite
    activate=test_school.SchoolTests.activate
    def test_tutor_selector_never_exposes_private_directory(self):
        self.assertEqual([],self.call('GET','/school/tutor-candidates')['items'])
        for a,b in [('parent','tutor'),('tutor','parent'),('parent','child'),('child','parent')]:
            self.r.execute('INSERT INTO contacts VALUES(?,?,1)',(a,b))
        # Inserted adult contacts suffice; minor contacts still require consent.
        self.assertEqual([{'id':'tutor','name':'tutor'}],self.call('GET','/school/tutor-candidates')['items'])
        self.r.execute("INSERT INTO blocks VALUES('tutor','parent')")
        self.assertEqual([],self.call('GET','/school/tutor-candidates')['items'])
        self.denied(403,lambda:self.call('GET','/school/tutor-candidates',who='child'))

    def test_repeated_privacy_save_preserves_history_start(self):
        self.activate('history')
        before=self.r.one("SELECT updated FROM school_privacy WHERE child='child'")['updated']
        self.call('PATCH','/school/children/child/privacy',{'mode':'shared'})
        self.assertEqual(before,self.r.one("SELECT updated FROM school_privacy WHERE child='child'")['updated'])

    def test_roles_do_not_grant_implicit_access_to_other_families(self):
        self.activate()
        matrix=[
            ('GET','/admin/summary',{},'tutor',403),
            ('GET','/guardian/children/child/activity',{},'tutor',404),
            ('GET','/school/children/child/audit',{},'tutor',404),
            ('DELETE','/school/children/child/tutors/missing',{},'stranger',404),
            ('PATCH','/school/children/child/privacy',{'mode':'shared'},'child',404),
            ('POST','/school/children/child/tutors',{'tutorId':'tutor','consent':True,'consentVersion':'school-v1'},'child',404),
        ]
        for method,path,data,who,status in matrix:
            with self.subTest(who=who,path=path):
                self.denied(status,lambda:self.call(method,path,data,who))


class LifecycleTests(unittest.TestCase):
    def setUp(self):
        self.r=Repository(':memory:')
        self.addCleanup(self.r.db.close)
        self.r.execute("INSERT INTO users(id,email,password,name,birth,verified) VALUES('u','u@example.com','unused','User','1990-01-01',1)")

    def test_expiry_orphan_grace_and_cloud_delete_queue(self):
        now=time.time()
        for mid in ['avatar','gallery','orphan','recent','expired']:
            self.r.execute('INSERT INTO media VALUES(?,?,?,?)',(mid,'u','image/png',b'image'))
            self.r.execute('UPDATE media_created SET created=? WHERE media=?',(now-(10 if mid=='recent' else 90000),mid))
        self.r.execute("INSERT INTO profile_media VALUES('u','avatar')")
        self.r.execute("INSERT INTO posts VALUES('p','u','gallery',NULL,0,1,NULL)")
        self.r.execute("INSERT INTO post_media VALUES('p','gallery',0)")
        self.r.execute("INSERT INTO posts VALUES('s','u','expired','expired',1,1,1)")
        self.r.execute("INSERT INTO media_objects VALUES('orphan','bucket','key','1',5,'sha')")
        self.r.execute("INSERT INTO identity_deletions VALUES('failed',1,5,1,NULL)")
        self.r.execute("INSERT INTO identity_deletions VALUES('done',1,1,1,1)")
        Service(self.r,development=True).maintain()
        self.assertEqual({'avatar','gallery','recent'},{row['id'] for row in self.r.rows('SELECT id FROM media')})
        self.assertEqual(1,len(self.r.rows('SELECT * FROM media_deletions')))
        self.assertIsNotNone(self.r.one("SELECT * FROM identity_deletions WHERE uid='failed'"))
        self.assertIsNone(self.r.one("SELECT * FROM identity_deletions WHERE uid='done'"))
        self.assertEqual([],self.r.rows('PRAGMA foreign_key_check'))

    def test_failure_rolls_back_all_retention_changes(self):
        self.r.execute("INSERT INTO posts VALUES('s','u','expired',NULL,1,1,1)")
        self.r.execute("CREATE TRIGGER fail_cleanup BEFORE DELETE ON audit BEGIN SELECT RAISE(ABORT,'test failure'); END")
        self.r.execute("INSERT INTO audit VALUES('a','test','anonymous',1)")
        with self.assertRaises(Exception):purge(self.r)
        self.assertIsNotNone(self.r.one("SELECT id FROM posts WHERE id='s'"))


class EmulatorIsolationTests(unittest.TestCase):
    def test_only_a_local_auth_emulator_can_delete_qa_identities(self):
        class LocalIdentity:
            emulated=True
            deleted=[]
            def delete(self,uid):self.deleted.append(uid)
        r=Repository(':memory:')
        self.addCleanup(r.db.close)
        identity=LocalIdentity()
        with self.assertRaises(ValueError):Service(r,development=True,firebase=identity)
        service=Service(r,development=True,firebase=identity,integration_test=True)
        r.execute("INSERT INTO identity_deletions(uid,created) VALUES('local-demo-uid',1)")
        service.process_identity_deletions()
        self.assertEqual(['local-demo-uid'],identity.deleted)
        self.assertIsNotNone(r.one('SELECT completed FROM identity_deletions')['completed'])

    def test_unsigned_emulator_tokens_require_explicit_isolation(self):
        base={'FIREBASE_AUTH_EMULATOR_HOST':'127.0.0.1:9099','CONEXIA_DEV':'1','CONEXIA_INTEGRATION_TEST':'1'}
        with patch.dict(os.environ,base,clear=True):
            self.assertTrue(validate_emulator_environment('demo-conexia-barema'))
            with self.assertRaises(ValueError):validate_emulator_environment('conexiabeta2')
        for changes in [
            {'CONEXIA_DEV':'0'}, {'CONEXIA_INTEGRATION_TEST':'0'},
            {'GOOGLE_APPLICATION_CREDENTIALS':'private.json'}, {'CONEXIA_MEDIA_BUCKET':'real-bucket'},
            {'FIREBASE_AUTH_EMULATOR_HOST':'example.com:9099'},
            {'FIREBASE_AUTH_EMULATOR_HOST':'127.0.0.1:9099/path'},
            {'FIREBASE_AUTH_EMULATOR_HOST':'127.0.0.1:bad'},
        ]:
            with self.subTest(changes=changes),patch.dict(os.environ,dict(base,**changes),clear=True):
                with self.assertRaises(ValueError):validate_emulator_environment('demo-conexia-barema')

if __name__=='__main__':unittest.main()
