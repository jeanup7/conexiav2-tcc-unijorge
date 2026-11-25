"""Offline comparison, using a consented, pseudonymized and subject-disjoint CSV.
No face images, paths or exact birthdays are copied to the output.
"""
import argparse
import csv
import json
from pathlib import Path
from time import perf_counter
from vision_models import AGE_LABELS, VisionModels

def rate(n,d):return None if not d else round(n/d,6)

def summarize(rows):
    valid=[r for r in rows if r['processed']]
    live=[r for r in valid if r['presentation']=='live']
    attacks=[r for r in valid if r['presentation']!='live']
    labelled=[r for r in live if r['expectedAgeBand']]
    return {'samples':len(rows),'processed':len(valid),'processingFailureRate':rate(len(rows)-len(valid),len(rows)),
        'processedLiveSamples':len(live),'processedAttackSamples':len(attacks),
        'ageBandAccuracyOnLabelledLive':rate(sum(r['ageBand']==r['expectedAgeBand'] for r in labelled),len(labelled)),
        'ageLabelledLiveSamples':len(labelled),
        'padAPCEROnProcessedAttacks':rate(sum(r['padScore']>=.8 for r in attacks),len(attacks)),
        'padBPCEROnProcessedLive':rate(sum(r['padScore']<.8 for r in live),len(live)),
        'ageOnlyBaselineAttackAcceptance':rate(sum(r['ageOnlySignal'] for r in attacks),len(attacks)),
        'combinedExperimentalAttackAcceptance':rate(sum(r['combinedSignal'] for r in attacks),len(attacks)),
        'combinedExperimentalLiveCoverage':rate(sum(r['combinedSignal'] for r in live),len(live)),
        'meanInferenceMs':rate(sum(r['latencyMs'] for r in valid),len(valid))}

def evaluate(manifest,model_directory,output):
    manifest=Path(manifest).resolve()
    with manifest.open(encoding='utf-8-sig',newline='') as handle:records=list(csv.DictReader(handle))
    if not records:raise ValueError('The dataset is empty')
    split_by_subject={};seen=set()
    for row in records:
        if row.get('consent')!='yes' or row.get('presentation') not in ('live','print','screen','replay') or row.get('split') not in ('validation','test'):
            raise ValueError('Use consent=yes, validation/test split and labelled presentations')
        subject=row.get('subject','')
        if not subject or len(subject)>64 or any(c not in 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-' for c in subject):raise ValueError('Use pseudonymous subject IDs')
        if subject in split_by_subject and split_by_subject[subject]!=row['split']:raise ValueError('Subject leakage between validation and test')
        split_by_subject[subject]=row['split']
        if row.get('age_band') and row['age_band'] not in AGE_LABELS:raise ValueError('Unknown age band')
        image=(manifest.parent/row['image']).resolve()
        if not image.is_relative_to(manifest.parent) or image in seen:raise ValueError('Use unique local dataset images inside the manifest directory')
        seen.add(image)
    model=VisionModels(model_directory)
    import numpy as np
    results=[]
    for row in records:
        item={'subject':row['subject'],'split':row['split'],'presentation':row['presentation'],'expectedAgeBand':row.get('age_band') or None,'processed':False}
        start=perf_counter()
        try:
            content=(manifest.parent/row['image']).read_bytes()
            if len(content)>650000:raise ValueError('Capture too large')
            from images import normalize
            import base64
            _,content=normalize({'mime':'image/jpeg','data':base64.b64encode(content).decode()})
            with model.lock:pred=model.frame(content)
            index=int(np.argmax(pred['age']));label=AGE_LABELS[index];score=float(pred['age'][index])
            item.update(processed=True,ageBand=label,ageScore=score,padScore=pred['pad'],ageOnlySignal=bool(score>=.7 and label!='10-19'),combinedSignal=bool(pred['pad']>=.8 and score>=.7 and label!='10-19'),latencyMs=round((perf_counter()-start)*1000,3))
        except Exception:item['error']='processing_failure'
        results.append(item)
    report={'experimental':True,'notPopulationValidation':True,'models':model.manifest,'thresholds':{'pad':.8,'ageScore':.7},
            'baseline':'Same age confidence/band rules as combined mode, without PAD.',
            'limitations':'Static-frame comparison does not validate motion challenge, camera integrity, identity continuity or resistance to video injection. Thresholds are not calibrated.',
            'summary':summarize(results),'bySplit':{s:summarize([r for r in results if r['split']==s]) for s in ('validation','test')},'rows':results}
    Path(output).write_text(json.dumps(report,indent=2,allow_nan=False),encoding='utf-8')
    return report

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--manifest',required=True);p.add_argument('--models',required=True);p.add_argument('--output',required=True)
    a=p.parse_args();report=evaluate(a.manifest,a.models,a.output)
    print(json.dumps(report['summary'],indent=2))
