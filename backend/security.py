import secrets
import hashlib
import hmac
from datetime import date

class ApiError(Exception):
    def __init__(self, status, message):
        self.status, self.message = status, message
        super().__init__(message)


def token(): return secrets.token_urlsafe(32)
def digest(value): return hashlib.sha256(value.encode()).hexdigest()
def password_hash(password):
    salt = secrets.token_bytes(16)
    key = hashlib.scrypt(password.encode(), salt=salt, n=16384, r=8, p=1)
    return salt.hex() + ':' + key.hex()
def password_matches(password, encoded):
    salt, key = encoded.split(':')
    actual = hashlib.scrypt(password.encode(), salt=bytes.fromhex(salt), n=16384, r=8, p=1)
    return hmac.compare_digest(actual.hex(), key)
def text(data, key, minimum=1, maximum=2000):
    value = data.get(key)
    if not isinstance(value, str) or not minimum <= len(value.strip()) <= maximum:
        raise ApiError(400, 'Campo inválido: ' + key)
    return value.strip()
def email(data, key='email'):
    value = text(data, key, 3, 254).lower()
    if value.count('@') != 1 or '.' not in value.split('@')[1] or any(c.isspace() for c in value):
        raise ApiError(400, 'E-mail inválido')
    return value

def age(birth):
    try: born = date.fromisoformat(birth)
    except (ValueError, TypeError): raise ApiError(400, 'Data de nascimento inválida')
    today = date.today()
    years = today.year-born.year-((today.month,today.day)<(born.month,born.day))
    if years < 0 or years > 120: raise ApiError(400, 'Data de nascimento inválida')
    return years

def password(data):
    value=data.get('password')
    if not isinstance(value,str) or not 12 <= len(value) <= 128:
        raise ApiError(400,'A senha deve ter de 12 a 128 caracteres')
    return value
