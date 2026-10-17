import hashlib
import json
import unittest
from repository import Repository
from seed_data import Seeder, SeedConfig
from service import Service
from security import ApiError


class SeedDataTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.repo=Repository(':memory:')
        cls.config=SeedConfig(users=24,posts=40,stories=12,messages=120,namespace='qa-validation')
        cls.seeder=Seeder(cls.repo,cls.config,now=1780000000)
        cls.manifest=cls.seeder.run()
        cls.service=Service(cls.repo,development=True)

    @classmethod
    def tearDownClass(cls):cls.repo.db.close()

    def test_volume_media_and_unique_captions(self):
        self.assertEqual(24,self.manifest['counts']['users'])
        self.assertEqual(40,self.manifest['counts']['posts'])
        self.assertEqual(12,self.manifest['counts']['stories'])
        self.assertEqual(120,self.manifest['counts']['messages'])
        self.assertEqual(52,self.repo.one('SELECT count(DISTINCT text) n FROM posts')['n'])
        avatars=self.repo.rows('SELECT m.data FROM profile_media p JOIN media m ON m.id=p.media')
        self.assertEqual(24,len({hashlib.sha256(row['data']).hexdigest() for row in avatars}))

    def test_all_attachments_are_used_in_avatar_and_post(self):
        for index,expected in enumerate(self.seeder.normalized):
            avatar=self.repo.one('SELECT m.data FROM profile_media p JOIN media m ON m.id=p.media WHERE p.user=?', (self.seeder.identifier('user',index),))
            post=self.repo.one('SELECT m.data FROM posts p JOIN media m ON m.id=p.media WHERE p.id=?',(self.seeder.identifier('post',index),))
            self.assertEqual(expected,avatar['data'])
            self.assertEqual(expected,post['data'])
        self.assertFalse(self.repo.db.execute('PRAGMA foreign_key_check').fetchall())

    def test_contacts_follow_guardian_and_block_rules(self):
        for source,target,_ in self.seeder.edges:
            self.assertTrue(self.service.contact(source,target))
            self.assertTrue(self.service.contact(target,source))
            self.assertFalse(self.service.blocked(source,target))
        self.assertTrue(self.repo.one("SELECT 1 FROM contact_requests WHERE status='pending'"))
        self.assertTrue(self.repo.one('SELECT 1 FROM blocks'))
        self.assertTrue(self.repo.one("SELECT 1 FROM guardian_links WHERE state='paused'")) if self.config.users>=36 else None

    def test_chats_are_bidirectional_private_and_chronological(self):
        pairs={tuple(sorted((m['sender'],m['recipient']))) for m in self.repo.rows('SELECT * FROM messages')}
        for a,b in pairs:
            messages=self.repo.rows('SELECT * FROM messages WHERE (sender=? AND recipient=?) OR (sender=? AND recipient=?) ORDER BY created',(a,b,b,a))
            self.assertEqual({a,b},{m['sender'] for m in messages})
            self.assertTrue(self.service.contact(a,b))
            self.assertLessEqual(max(m['created'] for m in messages),self.seeder.now)
            self.assertGreater(len({m['text'] for m in messages}),3)
        self.assertTrue(self.repo.one('SELECT 1 FROM messages WHERE read=0'))
        self.assertTrue(self.repo.one('SELECT 1 FROM messages WHERE read=1'))

    def test_stories_and_family_times_match_reality(self):
        self.assertTrue(self.repo.one('SELECT 1 FROM posts WHERE story=1 AND expires>?',(self.seeder.now,)))
        self.assertTrue(self.repo.one('SELECT 1 FROM posts WHERE story=1 AND expires<=?',(self.seeder.now,)))
        invalid=self.repo.one('SELECT 1 FROM feed_views v JOIN posts p ON p.id=v.post WHERE v.first_seen<p.created OR v.last_seen<? OR v.last_seen>?',(0,self.seeder.now))
        self.assertIsNone(invalid)

    def test_repeat_is_noop_and_reset_preserves_unrelated_data(self):
        repo=Repository(':memory:')
        self.addCleanup(repo.db.close)
        repo.execute("INSERT INTO users(id,email,password,name,birth,verified) VALUES('real','real@example.org','unused','Preservar','1990-01-01',1)")
        first=Seeder(repo,self.config,now=1780000000).run()
        second=Seeder(repo,self.config,now=1780001000).run()
        self.assertEqual(first,second)
        refreshed=Seeder(repo,self.config,now=1780001000).run(reset=True)
        self.assertEqual(first['counts'],refreshed['counts'])
        self.assertEqual('Preservar',repo.one("SELECT name FROM users WHERE id='real'")['name'])

    def test_suspended_users_cannot_publish_or_view_private_data(self):
        user=self.repo.one("SELECT u.* FROM users u JOIN account_status s ON s.user=u.id WHERE s.status='suspended'")
        session=self.service.session(user)
        with self.assertRaises(ApiError) as caught:
            self.service.dispatch('GET','/posts',{},session['accessToken'])
        self.assertEqual(403,caught.exception.status)
        self.assertEqual('suspended',self.service.dispatch('GET','/me',{},session['accessToken'])['accountStatus'])

    def test_admin_metrics_and_filtered_users_match_database(self):
        actor=self.repo.one('SELECT u.* FROM users u JOIN administrators a ON a.user=u.id')
        session=self.service.session(actor)
        summary=self.service.dispatch('GET','/admin/summary',{},session['accessToken'])
        self.assertEqual(24,summary['users'])
        self.assertEqual(40,summary['posts'])
        self.assertEqual(120,summary['messages'])
        self.assertEqual(12,summary['activeStories']+summary['expiredStories'])
        rows=self.service.dispatch('GET','/admin/users',{'status':'suspended'},session['accessToken'])['items']
        self.assertEqual(summary['suspendedUsers'],len(rows))
        self.assertTrue(all(row['status']=='suspended' for row in rows))
        self.assertTrue(all('password' not in row for row in rows))
