"""Stable keyset cursors; numeric cursors remain accepted for older clients."""
import base64
import json
import math
from security import ApiError


def encode_cursor(created, identifier):
    raw=json.dumps([created,identifier],separators=(',',':')).encode()
    return 'v1.'+base64.urlsafe_b64encode(raw).decode().rstrip('=')


def decode_cursor(value, default):
    if value is None:return default,''
    try:
        if isinstance(value,bool):raise ValueError()
        if isinstance(value,str) and value.startswith('v1.'):
            if len(value)>1024:raise ValueError()
            encoded=value[3:]
            parts=json.loads(base64.b64decode(encoded+'='*(-len(encoded)%4),altchars=b'-_',validate=True))
            if not isinstance(parts,list) or len(parts)!=2:raise ValueError()
            created,identifier=parts
            if isinstance(created,bool) or not isinstance(created,(int,float)):raise ValueError()
            if not isinstance(identifier,str) or not 1<=len(identifier)<=200:raise ValueError()
        else:
            created,identifier=float(value),''
        if not math.isfinite(created):raise ValueError()
        return created,identifier
    except (ValueError,TypeError,OverflowError):
        raise ApiError(400,'Paginação inválida')
