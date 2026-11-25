"""Local, CPU-only research inference. No identity recognition or face templates.

PAD crop/preprocessing follows yakhyo/face-anti-spoofing (Apache-2.0).
See vision/NOTICE.md for original authors, licenses and model limitations.
"""
import hashlib
import json
import math
from pathlib import Path
from threading import Lock

AGE_LABELS=('0-2','3-9','10-19','20-29','30-39','40-49','50-59','60-69','more than 70')

def decision(age_band, probability, pad_score, motion):
    if not all(math.isfinite(v) and 0<=v<=1 for v in (probability,pad_score)):
        return 'inconclusive'
    if pad_score<0.8:return 'presentation_risk'
    if not motion or probability<0.7 or age_band=='10-19':return 'inconclusive'
    return 'experimental_signals_only'

class VisionModels:
    def __init__(self, directory):
        import cv2
        import numpy as np
        import onnxruntime as ort
        self.cv,self.np=cv2,np
        self.directory=Path(directory).resolve()
        self.manifest=json.loads((self.directory/'manifest.json').read_text(encoding='utf-8'))
        from install_vision_models import SOURCES
        if set(self.manifest['models'])!=set(SOURCES):raise ValueError('Unknown model bundle')
        for name, metadata in self.manifest['models'].items():
            content=(self.directory/(name+'.onnx')).read_bytes()
            if hashlib.sha256(content).hexdigest()!=SOURCES[name][1] or metadata['sha256']!=SOURCES[name][1]:
                raise ValueError('Model checksum mismatch: '+name)
        options=ort.SessionOptions()
        options.intra_op_num_threads=2
        options.inter_op_num_threads=1
        self.age=ort.InferenceSession(str(self.directory/'age.onnx'),sess_options=options,providers=['CPUExecutionProvider'])
        self.pad=ort.InferenceSession(str(self.directory/'pad.onnx'),sess_options=options,providers=['CPUExecutionProvider'])
        self.detector=cv2.FaceDetectorYN_create(str(self.directory/'detector.onnx'),'',(320,320),score_threshold=.9)
        self.lock=Lock()

    @staticmethod
    def softmax(np, value):
        value=value-np.max(value)
        exp=np.exp(value)
        return exp/exp.sum()

    def frame(self, content):
        cv,np=self.cv,self.np
        image=cv.imdecode(np.frombuffer(content,dtype=np.uint8),cv.IMREAD_COLOR)
        if image is None:raise ValueError('invalid_image')
        h,w=image.shape[:2]
        if min(h,w)<240 or max(h,w)>1280:raise ValueError('resolution')
        gray=cv.cvtColor(image,cv.COLOR_BGR2GRAY)
        if gray.mean()<35 or gray.mean()>225 or cv.Laplacian(gray,cv.CV_64F).var()<30:
            raise ValueError('image_quality')
        self.detector.setInputSize((w,h))
        _,faces=self.detector.detect(image)
        if faces is None or len(faces)!=1:raise ValueError('single_face_required')
        face=faces[0]
        x,y,bw,bh=map(float,face[:4])
        if min(bw,bh)<64 or x<0 or y<0 or x+bw>w or y+bh>h:raise ValueError('face_framing')
        # Preserve surrounding texture: MiniFASNetV2 uses a 2.7x BGR crop,
        # raw [0,255] values (not RGB or division by 255).
        scale=min((h-1)/bh,(w-1)/bw,2.7)
        cx,cy=x+bw/2,y+bh/2
        xa,ya=max(0,int(cx-bw*scale/2)),max(0,int(cy-bh*scale/2))
        xb,yb=min(w-1,int(cx+bw*scale/2)),min(h-1,int(cy+bh*scale/2))
        crop=cv.resize(image[ya:yb+1,xa:xb+1],(80,80))
        tensor=crop.astype(np.float32).transpose(2,0,1)[None]
        pad=self.softmax(np,self.pad.run(None,{self.pad.get_inputs()[0].name:tensor})[0][0])
        # ViT original preprocessing: RGB, bilinear 224x224, (x/255-.5)/.5.
        from PIL import Image
        rgb=cv.cvtColor(image[int(y):int(y+bh),int(x):int(x+bw)],cv.COLOR_BGR2RGB)
        face_image=Image.fromarray(rgb).resize((224,224),Image.Resampling.BILINEAR)
        pixels=(np.asarray(face_image,dtype=np.float32)/255-.5)/.5
        age=self.softmax(np,self.age.run(None,{self.age.get_inputs()[0].name:pixels.transpose(2,0,1)[None]})[0][0])
        if len(age)!=9 or len(pad)!=3 or not np.isfinite(age).all() or not np.isfinite(pad).all():
            raise ValueError('model_output')
        # Nose/eye geometry is only a motion heuristic, not a liveness proof.
        eye_mid=(float(face[4])+float(face[6]))/2
        yaw=(float(face[8])-eye_mid)/max(abs(float(face[4])-float(face[6])),1)
        return {'age':age,'pad':float(pad[1]),'yaw':yaw}

    def analyze(self, contents, challenge):
        np=self.np
        # Detector has mutable input dimensions; bounded model concurrency.
        if not self.lock.acquire(blocking=False):raise RuntimeError('busy')
        try:
            frames=[self.frame(content) for content in contents]
            age=np.mean([f['age'] for f in frames],axis=0)
            index=int(np.argmax(age))
            yaw=[f['yaw'] for f in frames]
            delta=[yaw[1]-yaw[0],yaw[2]-yaw[0]]
            motion=(abs(yaw[0])<.25 and delta[0]*delta[1]<0 and min(map(abs,delta))>.12)
            # Require the requested order relative to captured image coordinates.
            motion=motion and ((delta[0]<0)==(challenge[1]=='left'))
            pad=min(f['pad'] for f in frames)
            score=float(age[index])
            return {'ageBand':AGE_LABELS[index],'ageScore':round(score,4),
                    'padScore':round(pad,4),'motionObserved':bool(motion),
                    'result':decision(AGE_LABELS[index],score,pad,motion),
                    'experimental':True,'grantsAccess':False,
                    'versions':{k:v['sha256'] for k,v in self.manifest['models'].items()}}
        finally:self.lock.release()
