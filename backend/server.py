import json
import os
import logging
import socket
import sqlite3
import uuid
from threading import Event, Thread
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit, parse_qs
from service import Service, Repository, ApiError

class Handler(BaseHTTPRequestHandler):
    server_version = 'Conexia'
    def log_message(self, *args): pass  # No identifiers, tokens, bodies or query strings in logs.
    def do_OPTIONS(self): self.respond(204,{})
    def do_GET(self): self.handle_api()
    def do_POST(self): self.handle_api()
    def do_PATCH(self): self.handle_api()
    def do_DELETE(self): self.handle_api()
    def handle_api(self):
        self.request_id=uuid.uuid4().hex
        try:
            if self.headers.get('Transfer-Encoding') or len(self.headers.get_all('Content-Length',[]))>1:
                raise ApiError(400,'Enquadramento da requisição inválido')
            length=int(self.headers.get('Content-Length','0'))
            if length<0 or length>7100000: raise ApiError(413,'Arquivo muito grande')
            origin=self.headers.get('Origin','')
            if origin and origin not in self.server.origins: raise ApiError(403,'Origem não permitida')
            if length and self.headers.get_content_type()!='application/json': raise ApiError(415,'Envie dados em JSON')
            if self.command=='GET' and length: raise ApiError(400,'GET não aceita corpo')
            self.connection.settimeout(15)
            raw=self.rfile.read(length)
            if len(raw)!=length: raise ApiError(400,'Corpo incompleto')
            def invalid_constant(value): raise ValueError('Non-finite JSON')
            def unique_keys(pairs):
                result={}
                for key,value in pairs:
                    if key in result: raise ValueError('Duplicate JSON key')
                    result[key]=value
                return result
            body=json.loads(raw,parse_constant=invalid_constant,object_pairs_hook=unique_keys) if length else {}
            if not isinstance(body,dict): raise ApiError(400,'JSON inválido')
            url=urlsplit(self.path)
            if len(self.path)>4096: raise ApiError(414,'Endereço muito longo')
            if self.command=='GET':
                query=parse_qs(url.query,max_num_fields=20)
                if any(len(v)!=1 for v in query.values()): raise ApiError(400,'Parâmetro duplicado')
                body={k:v[0] for k,v in query.items()}
            authorization=self.headers.get('Authorization','')
            if len(self.headers.get_all('Authorization',[]))>1 or (authorization and not authorization.startswith('Bearer ')):
                raise ApiError(401,'Autenticação inválida')
            if len(self.headers.get_all('Idempotency-Key',[]))>1: raise ApiError(400,'Identificador duplicado')
            key=self.headers.get('Idempotency-Key')
            result=self.server.service.dispatch(self.command,url.path,body,authorization.removeprefix('Bearer '),self.client_address[0],key)
            self.respond(200,result)
        except ApiError as e: self.respond(e.status,{'error':{'message':e.message,'code':e.code}})
        except (ValueError,json.JSONDecodeError,RecursionError): self.respond(400,{'error':{'message':'Requisição inválida'}})
        except (socket.timeout,TimeoutError): self.respond(408,{'error':{'message':'Tempo de envio excedido'}})
        except (BrokenPipeError,ConnectionResetError): return
        except sqlite3.OperationalError as error:
            if getattr(error,'sqlite_errorcode',0)&255 in (sqlite3.SQLITE_BUSY,sqlite3.SQLITE_LOCKED):
                self.respond(503,{'error':{'message':'O banco está ocupado. Tente novamente em instantes.'}})
            else:
                logging.error('storage_failure request=%s',self.request_id)
                self.respond(500,{'error':{'message':'Não foi possível concluir a operação de dados.','requestId':self.request_id}})
        except Exception as error:
            # Correlate operational failures without tokens, bodies or exception text.
            logging.error('api_failure request=%s type=%s',self.request_id,type(error).__name__)
            self.respond(500,{'error':{'message':'Falha interna','requestId':self.request_id}})
    def respond(self,status,result):
        raw=json.dumps(result,ensure_ascii=False).encode()
        self.send_response(status)
        origin=self.headers.get('Origin','')
        if origin and origin in self.server.origins:
            self.send_header('Access-Control-Allow-Origin',origin)
            self.send_header('Vary','Origin')
            self.send_header('Access-Control-Allow-Headers','Authorization,Content-Type,Idempotency-Key')
            self.send_header('Access-Control-Allow-Methods','GET,POST,PATCH,DELETE,OPTIONS')
        self.send_header('Content-Type','application/json; charset=utf-8')
        self.send_header('Cache-Control','no-store')
        self.send_header('X-Content-Type-Options','nosniff')
        self.send_header('X-Request-ID',getattr(self,'request_id',uuid.uuid4().hex))
        self.send_header('Referrer-Policy','no-referrer')
        self.send_header('Content-Length',str(0 if status==204 else len(raw)))
        self.end_headers()
        if status!=204:
            try: self.wfile.write(raw)
            except (BrokenPipeError,ConnectionResetError): pass

if __name__=='__main__':
    development=os.environ.get('CONEXIA_DEV')=='1'
    if not development:
        raise SystemExit('Email delivery and guardian provider are not configured. Use CONEXIA_DEV=1 for local development only.')
    root=Path(__file__).resolve().parent
    if not os.environ.get('FIREBASE_PROJECT_ID') and os.environ.get('CONEXIA_LEGACY_AUTH')!='1':
        raise SystemExit('O aplicativo usa Firebase. Inicie pela pasta do projeto com .\\backend\\start_firebase.cmd. Para testes exclusivos da API legada, defina CONEXIA_LEGACY_AUTH=1 explicitamente.')
    firebase=None
    if os.environ.get('FIREBASE_PROJECT_ID'):
        from firebase_identity import FirebaseIdentity
        try: firebase=FirebaseIdentity(os.environ['FIREBASE_PROJECT_ID'])
        except Exception:
            raise SystemExit('Configure GOOGLE_APPLICATION_CREDENTIALS com o arquivo privado da conta de serviço Firebase e instale backend/requirements.txt.')
    server=ThreadingHTTPServer(('127.0.0.1',int(os.environ.get('PORT','8080'))),Handler)
    server.service=Service(Repository(os.environ.get('DATABASE_PATH',str(root/'conexia.sqlite3'))),development,firebase=firebase)
    server.origins={v.strip() for v in os.environ.get('ALLOWED_ORIGINS','http://localhost:5300,http://127.0.0.1:5300').split(',') if v.strip()}
    stop=Event()
    def retry_deletions():
        while not stop.is_set():
            try: server.service.process_identity_deletions()
            except Exception: logging.error('identity_deletion_worker_failed')
            stop.wait(30)
    worker=Thread(target=retry_deletions,daemon=True)
    worker.start()
    print(f'Conexia local API on http://127.0.0.1:{server.server_port}; Firebase Admin {"enabled" if firebase else "disabled (explicit legacy API mode)"}.',flush=True)
    try: server.serve_forever()
    except KeyboardInterrupt: pass
    finally:
        stop.set(); worker.join(timeout=20)
        server.server_close()
