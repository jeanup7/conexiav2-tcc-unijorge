"""Measured CPU latency on synthetic tensors. Not age/PAD population accuracy."""
import argparse
import json
from pathlib import Path
from statistics import mean,median
from time import perf_counter
from vision_models import VisionModels

def measure(directory,output):
    import numpy as np
    import cv2
    import onnxruntime as ort
    model=VisionModels(directory)
    results={}
    for name,session,size in [('age',model.age,224),('pad',model.pad,80)]:
        tensor=np.zeros((1,3,size,size),dtype=np.float32)
        feed={session.get_inputs()[0].name:tensor}
        session.run(None,feed) # warm-up, excluded
        times=[]
        for _ in range(10):
            start=perf_counter();value=session.run(None,feed)[0];times.append((perf_counter()-start)*1000)
        results[name]={'repeats':10,'outputShape':list(value.shape),'finite':bool(np.isfinite(value).all()),'meanMs':round(mean(times),3),'medianMs':round(median(times),3)}
    report={'kind':'synthetic_tensor_smoke_only','humanSamples':0,'ageAccuracy':None,'APCER':None,'BPCER':None,
            'preprocessingIncluded':False,'provider':'CPUExecutionProvider','threads':2,
            'versions':{'onnxruntime':ort.__version__,'opencv':cv2.__version__,'numpy':np.__version__},
            'models':model.manifest,'measurements':results,
            'notice':'These timings confirm local execution only; they do not validate age, liveness or attack detection on people.'}
    output=Path(output);output.parent.mkdir(parents=True,exist_ok=True)
    output.write_text(json.dumps(report,indent=2),encoding='utf-8')
    print(json.dumps(results,indent=2))
if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--models',required=True);p.add_argument('--output',required=True)
    args=p.parse_args();measure(args.models,args.output)
