import json
import secrets
import threading
import unittest
from pathlib import Path
from urllib.request import Request, urlopen
from urllib.error import HTTPError
from http.server import ThreadingHTTPServer
from server import Handler
from service import Service
from repository import Repository

class HttpIntegration(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory=Path(__file__).resolve().parent / ('.test-'+secrets.token_hex(8))
        cls.directory.mkdir()
        assert cls.directory.resolve().is_relative_to(Path(__file__).resolve().parent)
        cls.db=Repository(str(cls.directory/'test.sqlite3'))
        cls.server=ThreadingHTTPServer(('127.0.0.1',0),Handler)
        cls.server.service=Service(cls.db,development=True)
        cls.server.origins={'http://localhost:5300'}
        cls.thread=threading.Thread(target=cls.server.serve_forever,daemon=True)
        cls.thread.start()
        cls.url='http://127.0.0.1:'+str(cls.server.server_port)
    def request(self,path,method='GET',body=None,bearer=None):
        headers={'Content-Type':'application/json','Origin':'http://localhost:5300'}
        if bearer: headers['Authorization']='Bearer '+bearer
        req=Request(self.url+path,data=json.dumps(body).encode() if body is not None else None,headers=headers,method=method)
        try:
            with urlopen(req,timeout=5) as response: return response.status,json.loads(response.read()),response.headers
        except HTTPError as e:
            result=(e.code,json.loads(e.read()),e.headers)
            e.close()
            return result
    def test_real_http_register_verify_login_publish_and_restart_persistence(self):
        body={'name':'HTTP','email':'http@example.com','birth':'2000-01-01','password':'test password at least twelve'}
        status,result,headers=self.request('/auth/register','POST',body)
        self.assertEqual(200,status)
        self.assertEqual('http://localhost:5300',headers['Access-Control-Allow-Origin'])
        self.request('/auth/verify','POST',{'token':result['developmentToken']})
        _,session,_=self.request('/auth/login','POST',body)
        bearer=session['accessToken']
        _,post,_=self.request('/posts','POST',{'text':'Persisted via HTTP'},bearer)
        _,feed,_=self.request('/posts',bearer=bearer)
        self.assertEqual(post['id'],feed['items'][0]['id'])
        fresh=Repository(str(self.directory/'test.sqlite3'))
        self.assertEqual('Persisted via HTTP',fresh.one('SELECT * FROM posts WHERE id=?',(post['id'],))['text'])
        fresh.db.close()
        self.assertEqual(401,self.request('/posts')[0])
    def test_health_and_malformed_body(self):
        self.assertEqual('sqlite',self.request('/health')[1]['storage'])
        req=Request(self.url+'/auth/login',data=b'invalid-json',method='POST')
        with self.assertRaises(HTTPError) as cm: urlopen(req,timeout=5)
        self.assertEqual(400,cm.exception.code)
        cm.exception.close()
    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown(); cls.server.server_close(); cls.thread.join()
        cls.db.db.close()
        (cls.directory/'test.sqlite3').unlink()
        cls.directory.rmdir()

if __name__=='__main__': unittest.main()
