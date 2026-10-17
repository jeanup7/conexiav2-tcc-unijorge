"""Regression scenarios from the 08/10 audit; only isolated in-memory data."""
import time
import unittest
from unittest.mock import patch
from repository import Repository
from service import Service
from security import ApiError, digest


class AuditRegressionTests(unittest.TestCase):
    def setUp(self):
        self.repo = Repository(':memory:')
        self.api = Service(self.repo, development=True)
        for uid, birth in [('a','1990-01-01'),('b','1990-01-01'),('kid','2015-01-01')]:
            self.repo.execute('INSERT INTO users(id,email,password,name,birth,verified,private,messages) VALUES(?,?,?,?,?,1,0,1)',
                              (uid,uid+'@example.com','unused',uid,birth))
            self.repo.execute('INSERT INTO sessions VALUES(?,?,?,?,?)',
                              (digest(uid),digest(uid+'-refresh'),uid,time.time()+1000,time.time()+10000))
        self.repo.execute("UPDATE users SET private=1 WHERE id='kid'")
        self.repo.execute("INSERT INTO guardian_links VALUES('kid','a','Private name',1,'active',?)",(time.time(),))
    def tearDown(self): self.repo.db.close()
    def call(self,method,path,data=None,actor='a'):
        return self.api.dispatch(method,path,data or {},actor)
    def rejected(self,status,fn):
        with self.assertRaises(ApiError) as caught: fn()
        self.assertEqual(status,caught.exception.status)
    def connect(self):
        self.call('POST','/contacts',{'target':'b'})
        self.call('POST','/contacts/approve',{'target':'a'},'b')
    def seed_posts(self,count,created=100.0):
        with self.repo.db:
            self.repo.db.executemany('INSERT INTO posts VALUES(?,?,?,?,?,?,?)',
                                    [(f'post-{i:05}','a',str(i),None,0,created,None) for i in range(count)])
    def seed_messages(self,count):
        with self.repo.db:
            self.repo.db.executemany('INSERT INTO messages VALUES(?,?,?,?,?,?)',
                                    [(f'm{i:03}','b','a',str(i),float(i//3),0) for i in range(count)])
    def test_adult_cannot_approve_request_from_minor(self):
        self.call('POST','/contacts',{'target':'b'},'kid')
        result=self.call('POST','/contacts/approve',{'target':'kid'},'b')
        self.assertEqual('awaiting_guardian',result['status'])
        self.assertEqual(0,self.repo.one("SELECT approved FROM contacts WHERE user='kid' AND target='b'")['approved'])
        self.assertIsNone(self.repo.one("SELECT * FROM contacts WHERE user='b' AND target='kid'"))
    def test_minor_cannot_approve_adult_request(self):
        self.call('POST','/contacts',{'target':'kid'})
        result=self.call('POST','/contacts/approve',{'target':'a'},'kid')
        self.assertEqual('awaiting_guardian',result['status'])
        self.assertFalse(self.api.contact('a','kid'))
    def test_received_minor_request_is_identified_for_ui(self):
        self.call('POST','/contacts',{'target':'b'},'kid')
        item=self.call('GET','/contacts/requests',actor='b')['items'][0]
        self.assertTrue(item['requiresGuardian']);self.assertNotIn('birth',item)
    def test_duplicate_contact_request_does_not_repeat_notification(self):
        self.call('POST','/contacts',{'target':'b'})
        self.call('POST','/contacts',{'target':'b'})
        self.assertEqual(1,self.repo.one("SELECT count(*) n FROM notifications WHERE user='b'")['n'])
    def test_equal_timestamps_paginate_every_post_once(self):
        self.seed_posts(5)
        cursor=None; ids=[]
        for _ in range(5):
            page=self.call('GET','/posts',{'limit':2,**({'cursor':cursor} if cursor else {})})
            ids.extend(v['id'] for v in page['items']);cursor=page['nextCursor']
            if cursor is None:break
        self.assertEqual(5,len(ids));self.assertEqual(5,len(set(ids)))
    def test_feed_rejects_nonfinite_and_invalid_cursor(self):
        for cursor in ['nan','inf','-inf','bad','v1.invalid']:
            self.rejected(400,lambda:self.call('GET','/posts',{'cursor':cursor}))
    def test_search_does_not_limit_before_visibility(self):
        with self.repo.db:
            self.repo.db.executemany('INSERT INTO users(id,email,password,name,birth,verified,private) VALUES(?,?,?,?,?,1,1)',
                                    [(f'private{i:03}',f'p{i}@example.com','unused','Match','1990-01-01') for i in range(70)])
            self.repo.db.execute("INSERT INTO users(id,email,password,name,birth,verified,private) VALUES('z-public','public@example.com','unused','Match','1990-01-01',1,0)")
        self.assertEqual(['z-public'],[u['id'] for u in self.call('GET','/profiles',{'q':'Match'})['items']])
    def test_story_cannot_be_registered_as_feed_exposure(self):
        story=self.call('POST','/stories',{'text':'Story'})['id']
        self.rejected(400,lambda:self.call('POST',f'/posts/{story}/view',{'visibleMs':2000},'kid'))
        self.assertEqual([],self.repo.rows('SELECT * FROM feed_views'))
    def test_long_login_window_survives_short_window_cleanup(self):
        with patch('service.time.time',return_value=1000):
            for _ in range(8):self.api.limit(('login','mail'),8,900)
        with patch('service.time.time',return_value=1061):
            self.api.limit(('ip','same'),180,60)
            self.rejected(429,lambda:self.api.limit(('login','mail'),8,900))
        with patch('service.time.time',return_value=1901):self.api.limit(('login','mail'),8,900)
    def test_messages_show_latest_and_page_all_history_without_implicit_read(self):
        self.connect();self.seed_messages(205)
        latest=self.call('GET','/messages/b')
        self.assertEqual('m204',latest['items'][-1]['id'])
        self.assertEqual(200,len(latest['items']))
        self.assertEqual(0,self.repo.one('SELECT count(*) n FROM messages WHERE read=1')['n'])
        older=self.call('GET','/messages/b',{'cursor':latest['nextCursor']})
        all_ids=[v['id'] for v in older['items']+latest['items']]
        self.assertEqual(205,len(set(all_ids)))
    def test_read_receipt_is_explicit_owned_and_atomic(self):
        self.connect();self.seed_messages(3)
        self.call('POST','/messages/b/read',{'ids':['m001']})
        self.assertEqual(['m001'],[r['id'] for r in self.repo.rows('SELECT id FROM messages WHERE read=1')])
        self.rejected(400,lambda:self.call('POST','/messages/b/read',{'ids':['m000','unknown']}))
        self.assertEqual(0,self.repo.one("SELECT read FROM messages WHERE id='m000'")['read'])
        self.rejected(400,lambda:self.call('POST','/messages/a/read',{'ids':['m000']},'b'))
    def test_feed_queries_do_not_scale_with_entire_history(self):
        self.seed_posts(5000)
        queries=[];self.repo.db.set_trace_callback(queries.append)
        page=self.call('GET','/posts',{'limit':15})
        self.assertEqual(15,len(page['items']))
        self.assertLess(len(queries),200)
    def test_feed_visibility_survives_batching(self):
        with self.repo.db:
            self.repo.db.execute("UPDATE users SET private=1 WHERE id='b'")
            self.repo.db.executemany('INSERT INTO posts VALUES(?,?,?,?,?,?,?)',
                                    [(f'private-{i}','b','Private',None,0,500.0,None) for i in range(100)])
        self.seed_posts(3)
        self.assertEqual(3,len(self.call('GET','/posts')['items']))
        self.connect()
        self.assertEqual(15,len(self.call('GET','/posts')['items']))
        self.call('POST','/blocks',{'target':'b'})
        self.assertEqual(3,len(self.call('GET','/posts')['items']))
    def test_explicit_like_is_idempotent_and_reports_server_count(self):
        self.seed_posts(1)
        route='/posts/post-00000/like'
        self.assertEqual(1,self.call('POST',route,{'liked':True})['likes'])
        self.assertEqual(1,self.call('POST',route,{'liked':True})['likes'])
        self.assertEqual(0,self.call('POST',route,{'liked':False})['likes'])
        self.rejected(400,lambda:self.call('POST',route,{'liked':'true'}))


if __name__=='__main__':unittest.main()
