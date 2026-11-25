"""Optional real-model smoke tests; not an accuracy study on people."""
import os
import unittest

@unittest.skipUnless(os.environ.get('VISION_TEST_MODELS'),'Set VISION_TEST_MODELS for local ONNX smoke tests')
class RuntimeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from vision_models import VisionModels
        cls.model=VisionModels(os.environ['VISION_TEST_MODELS'])
    def test_models_produce_finite_expected_outputs(self):
        import numpy as np
        for session,size,classes in [(self.model.age,224,9),(self.model.pad,80,3)]:
            value=session.run(None,{session.get_inputs()[0].name:np.zeros((1,3,size,size),dtype=np.float32)})[0]
            self.assertEqual((1,classes),value.shape)
            self.assertTrue(np.isfinite(value).all())
    def test_no_face_and_low_quality_are_rejected(self):
        import numpy as np
        cv=self.model.cv
        for image in [np.zeros((320,320,3),dtype=np.uint8),np.random.default_rng(1).integers(0,255,(320,320,3),dtype=np.uint8)]:
            _,encoded=cv.imencode('.jpg',image)
            with self.assertRaises(ValueError):self.model.frame(encoded.tobytes())
    def test_http_capture_lifecycle_uses_real_models_without_saving_images(self):
        import base64,json,threading,urllib.request,urllib.error
        from http.server import ThreadingHTTPServer
        from server import Handler
        from service import Service
        from repository import Repository
        from vision import VERSION
        import numpy as np
        repo=Repository(':memory:')
        server=ThreadingHTTPServer(('127.0.0.1',0),Handler)
        server.service=Service(repo,development=True,vision_models=self.model)
        server.origins=set()
        thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
        bearer=''
        def request(path,data=None):
            raw=json.dumps(data).encode() if data is not None else None
            req=urllib.request.Request(f'http://127.0.0.1:{server.server_port}'+path,data=raw,
                headers={'Content-Type':'application/json',**({'Authorization':'Bearer '+bearer} if bearer else {})})
            with urllib.request.urlopen(req,timeout=30) as response:return json.load(response)
        try:
            person={'email':'vision-smoke@example.test','name':'Synthetic QA','birth':'1990-01-01','password':'local smoke password only'}
            registered=request('/auth/register',person)
            request('/auth/verify',{'token':registered['developmentToken']})
            bearer=request('/auth/login',person)['accessToken']
            self.assertTrue(request('/vision/status')['enabled'])
            session=request('/vision/sessions',{'consent':True,'consentVersion':VERSION})
            repo.execute('UPDATE vision_sessions SET created=created-3 WHERE id=?',(session['id'],))
            frames=[]
            for seed in range(3):
                value=np.random.default_rng(seed).integers(0,255,(320,320,3),dtype=np.uint8)
                _,encoded=self.model.cv.imencode('.jpg',value)
                frames.append(base64.b64encode(encoded).decode())
            result=request('/vision/sessions/'+session['id']+'/capture',{'frames':frames})
            self.assertEqual('inconclusive',result['result']['result'])
            self.assertFalse(result['result']['grantsAccess'])
            self.assertEqual('complete',request('/vision/sessions/'+session['id'])['state'])
            self.assertEqual([],repo.rows('SELECT * FROM media'))
            self.assertEqual(1,request('/me')['verified'])
        finally:
            server.shutdown();thread.join(timeout=3);server.server_close();repo.db.close()

