"""Download pinned ONNX artifacts and validate upstream SHA-256 digests."""
import argparse
import hashlib
import json
from pathlib import Path
import urllib.request

REV='fd04cddf04982f6acc1ac76fb1a31b44c9285596'
SOURCES={
 'age':('https://huggingface.co/onnx-community/fairface_age_image_detection-ONNX/resolve/'+REV+'/onnx/model_quantized.onnx','42633bffee3cb91118f90cc97311270a4f94fa9f8eb7023e277ce045b2b91223'),
 'pad':('https://github.com/yakhyo/face-anti-spoofing/releases/download/weights/MiniFASNetV2.onnx','b32929adc2d9c34b9486f8c4c7bc97c1b69bc0ea9befefc380e4faae4e463907'),
 'detector':('https://media.githubusercontent.com/media/opencv/opencv_zoo/48b10fa505aeb51fbd127fc60a5c660040e823b7/models/face_detection_yunet/face_detection_yunet_2023mar.onnx','8f2383e4dd3cfbb4553ea8718107fc0423210dc964f9f4280604804ed2552fa4'),
}
def install(directory):
    directory=Path(directory).resolve();directory.mkdir(parents=True,exist_ok=True)
    models={}
    for name,(url,expected) in SOURCES.items():
        path=directory/(name+'.onnx')
        if not path.exists() or hashlib.sha256(path.read_bytes()).hexdigest()!=expected:
            request=urllib.request.Request(url,headers={'User-Agent':'Conexia-TCC-research'})
            with urllib.request.urlopen(request,timeout=120) as response:
                content=response.read(150*1024*1024+1)
            if hashlib.sha256(content).hexdigest()!=expected:raise ValueError('Checksum mismatch: '+name)
            temporary=directory/(name+'.download')
            temporary.write_bytes(content);temporary.replace(path)
        models[name]={'url':url,'sha256':expected}
        print(name+': checksum OK',flush=True)
    (directory/'manifest.json').write_text(json.dumps({'experimental':True,'models':models},indent=2),encoding='utf-8')
if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--directory',required=True)
    install(parser.parse_args().directory)
