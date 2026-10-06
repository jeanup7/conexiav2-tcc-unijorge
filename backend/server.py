import json
import os
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
        try:
            length=int(self.headers.get('Content-Length','0'))
            if length<0 or length>7100000: raise ApiError(413,'Arquivo muito grande')
            self.connection.settimeout(15)
            body=json.loads(self.rfile.read(length)) if length else {}
            if not isinstance(body,dict): raise ApiError(400,'JSON inválido')
            url=urlsplit(self.path)
            if self.command=='GET': body={k:v[-1] for k,v in parse_qs(url.query).items()}
            result=self.server.service.dispatch(self.command,url.path,body,self.headers.get('Authorization','').removeprefix('Bearer '),self.client_address[0])
            self.respond(200,result)
        except ApiError as e: self.respond(e.status,{'error':{'message':e.message}})
        except (ValueError,json.JSONDecodeError): self.respond(400,{'error':{'message':'Requisição inválida'}})
        except Exception: self.respond(500,{'error':{'message':'Falha interna'}})
    def respond(self,status,result):
        raw=json.dumps(result,ensure_ascii=False).encode()
        self.send_response(status)
        origin=self.headers.get('Origin','')
        if origin and origin in self.server.origins:
            self.send_header('Access-Control-Allow-Origin',origin)
            self.send_header('Vary','Origin')
            self.send_header('Access-Control-Allow-Headers','Authorization,Content-Type')
            self.send_header('Access-Control-Allow-Methods','GET,POST,PATCH,DELETE,OPTIONS')
        self.send_header('Content-Type','application/json; charset=utf-8')
        self.send_header('Cache-Control','no-store')
        self.send_header('X-Content-Type-Options','nosniff')
        self.send_header('Content-Length',str(len(raw)))
        self.end_headers()
        if status!=204: self.wfile.write(raw)

if __name__=='__main__':
    development=os.environ.get('CONEXIA_DEV')=='1'
    if not development:
        raise SystemExit('Email delivery and guardian provider are not configured. Use CONEXIA_DEV=1 for local development only.')
    root=Path(__file__).resolve().parent
    server=ThreadingHTTPServer(('127.0.0.1',int(os.environ.get('PORT','8080'))),Handler)
    server.service=Service(Repository(os.environ.get('DATABASE_PATH',str(root/'conexia.sqlite3'))),development)
    server.origins=set(os.environ.get('ALLOWED_ORIGINS','http://localhost:5300,http://127.0.0.1:5300').split(','))
    print('Conexia local API on http://127.0.0.1:8080; no seeded accounts; development verification codes enabled.',flush=True)
    try: server.serve_forever()
    except KeyboardInterrupt: server.server_close()
