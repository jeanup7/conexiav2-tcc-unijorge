"""Server-only Firebase identity verification. Never trust client email/verified flags."""
from security import ApiError
import os
from urllib.parse import urlsplit

def validate_emulator_environment(project_id):
    host=os.environ.get('FIREBASE_AUTH_EMULATOR_HOST')
    if not host:return False
    try:
        parsed=urlsplit('http://'+host)
        valid=(parsed.hostname in ('127.0.0.1','localhost') and parsed.port is not None
               and 0<parsed.port<65536 and not parsed.path and not parsed.query and not parsed.fragment
               and not parsed.username and not parsed.password)
    except ValueError:valid=False
    if not (valid and project_id.startswith('demo-') and os.environ.get('CONEXIA_DEV')=='1'
            and os.environ.get('CONEXIA_INTEGRATION_TEST')=='1' and not os.environ.get('CONEXIA_MEDIA_BUCKET')
            and not os.environ.get('GOOGLE_APPLICATION_CREDENTIALS')):
        raise ValueError('Auth Emulator requires an isolated local demo project without cloud credentials or Storage')
    return True

class FirebaseIdentity:
    def __init__(self, project_id):
        self.emulated=validate_emulator_environment(project_id)
        import firebase_admin
        from firebase_admin import auth
        self.auth = auth
        self.app = firebase_admin.initialize_app(options={'projectId': project_id}, name='conexia-api')
        # Fail at startup if server credentials have not been configured.
        if not self.emulated:self.app.credential.get_credential()

    def verify(self, bearer):
        if not bearer:
            raise ApiError(401, 'Entre novamente.')
        try:
            return self.auth.verify_id_token(bearer, app=self.app, check_revoked=True)
        except (self.auth.InvalidIdTokenError, self.auth.ExpiredIdTokenError,
                self.auth.RevokedIdTokenError, self.auth.UserDisabledError, self.auth.UserNotFoundError, ValueError):
            raise ApiError(401, 'Sessão Firebase inválida ou expirada. Entre novamente.')
        except Exception:
            raise ApiError(503, 'Não foi possível validar a sessão Firebase. Tente novamente.')

    def verified_email(self, uid):
        try:
            user=self.auth.get_user(uid,app=self.app)
            return bool(user.email_verified and not user.disabled)
        except self.auth.UserNotFoundError:
            return False
        except Exception:
            raise ApiError(503,'Não foi possível conferir a confirmação do responsável.')

    def revoke(self, uid):
        try:
            self.auth.revoke_refresh_tokens(uid, app=self.app)
        except Exception:
            raise ApiError(503, 'Não foi possível encerrar a sessão no Firebase.')

    def delete(self, uid):
        try:
            self.auth.delete_user(uid, app=self.app)
        except self.auth.UserNotFoundError:
            pass
        except Exception:
            raise ApiError(503, 'Não foi possível excluir a conta no Firebase.')
