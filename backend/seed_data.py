"""Reproducible, development-only QA dataset using the application's real schema.

No Firebase accounts, emails or passwords are created. Existing demo logins can
be connected explicitly; every other row belongs to the selected seed namespace.
"""
import argparse
import base64
from dataclasses import dataclass
from datetime import datetime, timezone
import hashlib
import io
import json
import math
import os
from pathlib import Path
import random
import re
import secrets
import sqlite3
import time
from urllib.parse import quote
from PIL import Image, ImageDraw, ImageFont

from backup import backup
from images import normalize
from repository import Repository
from security import age, digest, password_hash

ROOT = Path(__file__).resolve().parent
MEDIA_ROOT = ROOT / 'fixtures' / 'seed_media'
FIRST = ['Ana','Bruno','Camila','Daniel','Elisa','Felipe','Gabriela','Hugo','Isabela','João','Lara','Miguel','Nina','Otávio','Pedro','Rafaela','Sofia','Tiago','Valentina','Yuri','Beatriz','Caio','Davi','Helena','Igor','Júlia','Lucas','Marina','Noah','Vitor']
LAST = ['Almeida','Barbosa','Costa','Dias','Esteves','Ferreira','Gomes','Henrique','Lima','Macedo','Nogueira','Oliveira','Pereira','Queiroz','Ribeiro','Santos','Teixeira','Vieira','Andrade','Batista','Correia','Duarte','Freitas','Moura','Rocha']
TOPICS = {
    'anime': ['trabalho em equipe nos Jovens Titãs','criatividade do Ben 10','amizade em One Piece','personagens que aprendem com os erros','uma coleção de mangás','aventuras sem spoilers'],
    'games': ['um jogo cooperativo','um mapa construído com amigos','um desafio de lógica','um jogo de tabuleiro','uma fase criada em equipe','uma aventura de exploração'],
    'sports': ['uma volta de skate','um treino de equilíbrio','uma partida no intervalo','uma caminhada no parque','um circuito de bicicleta','uma jogada de vôlei'],
    'music': ['uma playlist para desenhar','ritmos brasileiros','um ensaio de violão','uma composição em grupo','sons da natureza','um instrumento feito com recicláveis'],
    'education': ['um clube de leitura','uma experiência de ciências','um problema de matemática','um livro sobre o oceano','uma feira de conhecimentos','uma descoberta de programação'],
    'art': ['um personagem autoral','um chaveiro criativo','um estudo de cores','um desenho coletivo','um mural da escola','uma fotografia de detalhes'],
    'other': ['uma ideia para o recreio','uma visita ao jardim','um momento de descanso','uma conversa em família','um passeio de fim de semana','um gesto de gentileza'],
}
OPENINGS = ['Hoje compartilhei','Nosso grupo experimentou','Separei um tempo para','A descoberta da semana foi','Trouxe uma ideia sobre','No projeto da turma exploramos','Uma pausa para falar sobre','Voltei para mostrar','Aprendi algo novo com','Que tal conhecer']
QUESTIONS = ['Que detalhe você mais gostou?','Como você faria diferente?','Alguém quer participar da próxima atividade?','Qual seria o próximo passo?','Que outra ideia combina com isso?','Vale conversar sobre isso em casa também.','Gostei de ouvir opiniões diferentes.','O mais legal foi construir isso em equipe.']
COMMENTS = ['Gostei da ideia de {topic}. Vou testar com meu grupo!', 'A parte sobre {topic} ficou bem explicada.', 'Podemos levar {topic} para o próximo encontro?', 'Também estou aprendendo sobre {topic}. Obrigado por compartilhar!', 'O resultado de {topic} mostra como praticar faz diferença.', 'Esse cuidado com {topic} deixou o projeto melhor.']
CHATS = [
    ['Você conseguiu terminar {topic}?','Consegui! A parte mais difícil foi organizar as ideias.','Quer comparar os resultados amanhã no clube?','Sim. Podemos mostrar para o grupo e ouvir sugestões.'],
    ['Vi sua publicação sobre {topic}. Ficou muito legal!','Obrigado! Fiz com calma e aprendi bastante.','Qual material você usou?','Usei o que já tinha disponível. Depois mostro o processo.'],
    ['Vamos combinar uma atividade sobre {topic}?','Boa ideia. Prefiro fazer no espaço da escola.','Podemos pedir ajuda para o tutor durante o intervalo.','Combinado, vou anotar as perguntas antes.'],
    ['Hoje fiquei com dúvida sobre {topic}.','Eu também tive essa dúvida no começo.','Você pode me explicar o primeiro passo?','Claro! Vamos começar com um exemplo simples.'],
    ['Marquei {topic} para conversar em família.','Vi a marcação. O que chamou sua atenção?','Gostei da ideia, mas queria ouvir outra opinião.','Vamos conversar com calma depois das atividades.'],
]


@dataclass(frozen=True)
class SeedConfig:
    users: int = 120
    posts: int = 2400
    stories: int = 360
    messages: int = 18000
    namespace: str = 'qa-demo-v1'
    random_seed: int = 20261015

    def validate(self):
        if not re.fullmatch(r'qa-[a-z0-9-]{2,35}', self.namespace):
            raise ValueError('O namespace deve começar com qa- e conter apenas letras minúsculas, números e hífens.')
        for key, low, high in [('users',24,1000),('posts',20,50000),('stories',4,10000),('messages',20,200000)]:
            if not low <= getattr(self,key) <= high: raise ValueError(f'{key}: use de {low} a {high}.')


def placeholder(name, index, avatar=False):
    """Deterministic local fallback; no external tracking or failed image URLs."""
    size = 192 if avatar else 720
    palette = [(225,235,255),(225,246,237),(249,234,219),(239,228,250),(221,241,245),(248,228,234)]
    image=Image.new('RGB',(size,size),palette[index % len(palette)])
    draw=ImageDraw.Draw(image)
    accent=(65+index%55,80+index*3%70,140+index*7%90)
    draw.ellipse((size*.6,-size*.16,size*1.25,size*.48),fill=tuple(min(255,v+18) for v in palette[index%6]))
    draw.rounded_rectangle((size*.08,size*.12,size*.91,size*.9),radius=int(size*.09),outline=accent,width=2)
    font_path=ROOT.parent/'assets/fonts/Lato-Bold.ttf'
    font=ImageFont.truetype(str(font_path),int(size*(.31 if avatar else .048)))
    if avatar:
        text=''.join(word[0] for word in name.split()[:2])
        draw.text((size/2,size/2),text,font=font,fill=accent,anchor='mm')
    else:
        title_font=ImageFont.truetype(str(font_path),32)
        words=name.split(); lines=[]; line=''
        for word in words:
            candidate=(line+' '+word).strip()
            if draw.textlength(candidate,font=title_font)>size*.68:
                lines.append(line); line=word
            else: line=candidate
        lines.append(line)
        draw.text((size*.14,size*.2),'CONEXIA • COMUNIDADE CRIATIVA',font=ImageFont.truetype(str(font_path),20),fill=accent)
        for row,line in enumerate(lines[:6]): draw.text((size*.14,size*.4+row*45),line,font=title_font,fill=(28,41,64))
        draw.text((size*.14,size*.8),f'Encontro {index+1:04d} · dados fictícios',font=ImageFont.truetype(str(font_path),20),fill=accent)
    output=io.BytesIO(); image.save(output,'JPEG',quality=84)
    return output.getvalue()


class Seeder:
    def __init__(self, repo, config, now=None):
        config.validate()
        self.r,self.c=repo,config
        self.now=time.time() if now is None else now
        self.rng=random.Random(config.random_seed)
        self.prefix=config.namespace+'-'
        self.people=[]; self.users={}; self.links={}; self.posts=[]; self.edges=[]; self.media=[]
        self.catalog=json.loads((MEDIA_ROOT/'catalog.json').read_text(encoding='utf-8'))
        self.normalized=[]
        for item in self.catalog:
            content=(MEDIA_ROOT/item['file']).read_bytes()
            self.normalized.append(normalize({'mime':'image/jpeg','data':base64.b64encode(content).decode()})[1])
        self.counters={}

    def identifier(self, kind, index=None):
        if index is None:
            index=self.counters.get(kind,0);self.counters[kind]=index+1
        return f'{self.prefix}{kind}-{index:07d}'

    def insert(self, table, values):
        self.r.db.execute(f'INSERT INTO {table} VALUES({",".join("?" for _ in values)})',values)

    def clear(self):
        if not self.r.one('SELECT 1 FROM seed_runs WHERE namespace=?',(self.c.namespace,)):
            if self.r.one('SELECT 1 FROM users WHERE id LIKE ?',(self.prefix+'%',)):
                raise ValueError('Há IDs conflitantes sem registro de propriedade do seed. Nenhum dado foi apagado.')
            return
        # These rows may belong to an existing demo login; IDs identify their seed owner.
        for table in ('feed_views','family_discussions','notifications','audit','reports','contact_requests','posts','messages','comments'):
            self.r.db.execute(f'DELETE FROM {table} WHERE id LIKE ?',(self.prefix+'%',))
        self.r.db.execute('DELETE FROM users WHERE id LIKE ?',(self.prefix+'user-%',))
        self.r.db.execute('DELETE FROM seed_runs WHERE namespace=?',(self.c.namespace,))

    def make_users(self, attach_demo):
        n=self.c.users; children=n//4; adults=n-children; guardians=math.ceil(children/2)
        combinations=[f'{a} {b}' for a in FIRST for b in LAST]
        self.rng.shuffle(combinations)
        unreachable=password_hash(secrets.token_urlsafe(32))
        for index in range(n):
            uid=self.identifier('user',index)
            name=combinations[index%len(combinations)]+(f' {index//len(combinations)+1}' if index>=len(combinations) else '')
            category=list(TOPICS)[index%7]
            role='minor' if index>=adults else 'guardian' if index<guardians else 'administrator' if index==guardians else 'adult'
            birth=f'{2010+index%8 if role=="minor" else 1980+index%25}-0{1+index%9}-{1+index%25:02d}'
            verified=index<7 or index%13!=0
            suspended=index>=7 and index%17==0
            private=role=='minor' or index%4==0
            bio=f'Gosto de {TOPICS[category][index%6]}. Compartilho descobertas e aprendo em grupo. Perfil fictício de QA.'
            self.r.db.execute('INSERT INTO users(id,email,password,name,birth,verified,private,messages,bio) VALUES(?,?,?,?,?,?,?,?,?)',
                (uid,f'{self.c.namespace}.{index:04d}@example.com',unreachable,name,birth,int(verified),int(private),1,bio))
            if suspended:self.insert('account_status',(uid,'suspended','Cenário fictício: pausa para revisão de conduta.',self.now-86400*(index%5)))
            if role=='administrator':self.insert('administrators',(uid,))
            person=dict(id=uid,name=name,role=role,verified=verified,suspended=suspended,private=private,category=category,index=index,birth=birth)
            self.people.append(person);self.users[uid]=person
            content=self.normalized[index] if index<len(self.normalized) else placeholder(name,index,True)
            mid=self.add_media(uid,content,'avatar',index,attachment=index if index<len(self.normalized) else None)
            self.insert('profile_media',(uid,mid))
        for offset,child in enumerate(self.people[adults:]):
            parent=self.people[(offset//2)%guardians]
            state='paused' if offset%9==8 else 'active'
            nickname=0 if offset%11==10 else 1
            self.insert('guardian_links',(child['id'],parent['id'],f'Criança fictícia {offset+1:03d}',nickname,state,self.now-86400*45))
            child.update(guardian=parent['id'],linkState=state,nickname=nickname)
            self.links[child['id']]=parent['id']
        self.anchors=[]
        if attach_demo:
            for role in ('admin','teste','responsavel','jovem'):
                uid='conexia-demo-v1-'+role
                row=self.r.one('SELECT * FROM users WHERE id=?',(uid,))
                if not row:continue
                if row['email']!=f'conexia.{role}@example.com':raise ValueError('A conta de demonstração reservada não corresponde ao cadastro esperado.')
                person=dict(id=uid,name=row['name'],role='minor' if age(row['birth'])<18 else 'adult',verified=bool(row['verified']),suspended=False,private=bool(row['private']),category='education',index=n+len(self.anchors),birth=row['birth'])
                if person['role']=='minor':
                    link=self.r.one('SELECT * FROM guardian_links WHERE child=?',(uid,))
                    if not link:continue
                    person.update(guardian=link['guardian'],linkState=link['state'],nickname=link['nickname_selected'])
                    self.links[uid]=link['guardian']
                self.users[uid]=person;self.anchors.append(person)

    def eligible(self, person):
        if person['suspended'] or not person['verified']:return False
        if person['role']=='minor':
            parent=self.users.get(person.get('guardian'))
            return bool(parent and self.eligible(parent) and person['linkState']=='active' and person['nickname'])
        return True

    def add_media(self, owner, content, kind, index, attachment=None, caption=None):
        mid=self.identifier('media-'+kind,index)
        self.insert('media',(mid,owner,'image/jpeg',content))
        self.r.db.execute('UPDATE media_created SET created=? WHERE media=?',(self.now-3600,mid))
        self.media.append(dict(id=mid,owner=owner,url='/media/'+mid,requiresBearer=True,
            source=self.catalog[attachment]['file'] if attachment is not None else 'local-placeholder',
            placeholderUrl=None if attachment is not None else 'https://placehold.co/720x720/EEF0FF/1C2940/png?text='+quote(caption or self.users.get(owner,{}).get('name','Conexia'))))
        return mid

    def connect(self, source, target, approved=True):
        rid=self.identifier('request')
        created=self.now-self.rng.randint(2,29)*86400
        self.insert('contact_requests',(rid,source,target,int(approved),'approved' if approved else 'pending',created,self.now+5*86400))
        for uid in (source,target):
            if uid in self.links:self.insert('contact_consents',(rid,uid,self.links[uid],int(approved)))
        self.r.db.execute('INSERT OR IGNORE INTO contacts VALUES(?,?,?)',(source,target,int(approved)))
        if approved:
            self.r.db.execute('INSERT OR IGNORE INTO contacts VALUES(?,?,1)',(target,source))
            self.edges.append((source,target,created))

    def make_network(self):
        active=[p for p in self.people+self.anchors if self.eligible(p)]
        pairs=set()
        for person in active:
            # Clubs create clusters while a few cross-club links connect the network.
            peers=[p for p in active if p['id']!=person['id']]
            weights=[4 if p['category']==person['category'] else 1 for p in peers]
            chosen={p['id'] for p in self.rng.choices(peers,weights=weights,k=min(12,len(peers)))}
            if person in self.anchors:
                chosen.update(p['id'] for p in active[:18])
            for target in sorted(chosen):
                pair=tuple(sorted((person['id'],target)))
                if target==person['id'] or pair in pairs:continue
                pairs.add(pair);self.connect(person['id'],target,approved=self.rng.random()>.16)
        # A blocked pair has no residual contact or pending consent.
        for source,target,_ in self.edges[::29]:
            self.insert('blocks',(source,target))
            self.r.db.execute('DELETE FROM contacts WHERE (user=? AND target=?) OR (user=? AND target=?)',(source,target,target,source))
            self.r.db.execute("UPDATE contact_requests SET status='cancelled' WHERE id LIKE ? AND ((source=? AND target=?) OR (source=? AND target=?))",(self.prefix+'%',source,target,target,source))
        self.edges=[e for e in self.edges if not self.r.one('SELECT 1 FROM blocks WHERE (user=? AND target=?) OR (user=? AND target=?)',(e[0],e[1],e[1],e[0]))]

    def make_content(self):
        authors=[p for p in self.people if self.eligible(p)]
        for index in range(self.c.posts+self.c.stories):
            story=index>=self.c.posts
            si=index-self.c.posts
            person=authors[index%len(authors)]
            attachment=index if index<len(self.catalog) else None
            category=self.catalog[index]['category'] if attachment is not None else person['category'] if index%4 else self.rng.choice(list(TOPICS))
            topic=self.catalog[index]['label'] if attachment is not None else self.rng.choice(TOPICS[category])
            hours=self.rng.uniform(.05,20) if story and si%3 else self.rng.uniform(27,96) if story else self.rng.uniform(1,30*24)
            # Showcase the seven supplied photos first in the normal feed.
            created=self.now-(index+1)*90 if attachment is not None else self.now-hours*3600
            opening=OPENINGS[index%len(OPENINGS)]
            caption=f'{opening} {topic}. {self.rng.choice(QUESTIONS)}\nDiário criativo {person["name"].split()[0]} · encontro {index+1:04d}. #{category} #comunidade'
            pid=self.identifier('story' if story else 'post',si if story else index)
            images=[]
            if attachment is not None or index%3==0:
                content=self.normalized[attachment] if attachment is not None else placeholder(topic,index)
                images.append(self.add_media(person['id'],content,'post',index,attachment,topic))
                if index%15==0:
                    images.append(self.add_media(person['id'],placeholder('Bastidores de '+topic,index+10000),'gallery',index,caption=topic))
            self.insert('posts',(pid,person['id'],caption,images[0] if images else None,int(story),created,created+86400 if story else None))
            for position,mid in enumerate(images):self.insert('post_media',(pid,mid,position))
            self.insert('post_categories',(pid,category))
            self.posts.append(dict(id=pid,user=person['id'],text=caption,category=category,story=story,created=created,expires=created+86400 if story else None,mediaItems=images,topic=topic))

    def can_see(self, actor, post):
        owner=self.users[post['user']]
        if actor==owner['id']:return True
        if self.r.one('SELECT 1 FROM blocks WHERE (user=? AND target=?) OR (user=? AND target=?)',(actor,owner['id'],owner['id'],actor)):return False
        return not owner['private'] or bool(self.r.one('SELECT 1 FROM contacts WHERE user=? AND target=? AND approved=1',(actor,owner['id'])))

    def interactions(self):
        active=[p for p in self.people+self.anchors if self.eligible(p)]
        normal=[p for p in self.posts if not p['story']]
        for index,post in enumerate(normal):
            participants=[p for p in self.rng.sample(active,min(14,len(active))) if self.can_see(p['id'],post)]
            for person in participants[:3+index%10]:self.r.db.execute('INSERT OR IGNORE INTO likes VALUES(?,?)',(person['id'],post['id']))
            for offset,person in enumerate(participants[:index%4]):
                text=COMMENTS[(index+offset)%len(COMMENTS)].format(topic=post['topic'])+f' — encontro {index+1:04d}'
                self.insert('comments',(self.identifier('comment'),person['id'],post['id'],text,min(self.now-10,post['created']+(offset+1)*600)))
            if index%8==0 and participants:
                status=['pending','pending','dismissed','removed'][index%4 if index%4 else (index//8)%4]
                target=post['id']
                if status=='removed':
                    target=self.identifier('removed-post',index)
                reason=['Possível conteúdo fora da proposta da comunidade.','Pedido de revisão do tom de um comentário.','Imagem precisa de avaliação de contexto.','Suspeita de publicação repetida.'][index//8%4]
                self.insert('reports',(self.identifier('report'),participants[0]['id'],target,reason,self.now-index*23,status))
            for child in [p for p in participants if p['role']=='minor'][:2]:
                seen=min(self.now-15,max(post['created']+60,self.now-(index%28)*86400-1800))
                day=datetime.fromtimestamp(seen,timezone.utc).strftime('%Y-%m-%d')
                self.r.db.execute('INSERT OR IGNORE INTO feed_views VALUES(?,?,?,?,?,?,?,?)',(self.identifier('view'),child['id'],post['id'],post['id'],post['category'],day,seen,min(self.now-1,seen+120)))
                if index%23==0:self.insert('family_discussions',(self.identifier('discussion'),child['id'],self.links[child['id']],post['id'],child['id'],'open' if index%2 else 'resolved',min(self.now-1,seen+150)))
        # Reports about profiles are separate from suspensions, never auto-punishment.
        for index,person in enumerate(self.people[::19]):
            self.insert('reports',(self.identifier('report'),active[index%len(active)]['id'],person['id'],'Perfil fictício sinalizado para análise de contexto.',self.now-300-index*30,'pending'))
        for person in self.anchors+active[:12]:
            for index,text in enumerate(['Uma conexão aguarda sua análise.','Uma publicação foi marcada para conversar em família.','Seu grupo compartilhou novas ideias.']):
                self.insert('notifications',(self.identifier('notification'),person['id'],text,self.now-(index+1)*7200))

    def conversations(self):
        edges=[edge for edge in self.edges if self.eligible(self.users[edge[0]]) and self.eligible(self.users[edge[1]])]
        edges.sort(key=lambda e: (not any(uid.startswith('conexia-demo-v1-') for uid in e[:2]),e[0],e[1]))
        edges=edges[:max(1,self.c.messages//12)]
        for index in range(self.c.messages):
            source,target,connected=edges[index%len(edges)]
            turn=index//len(edges)
            topic=TOPICS[self.users[source]['category']][(index+turn)%6]
            dialogue=CHATS[(index%len(edges))%len(CHATS)]
            text=dialogue[turn%len(dialogue)].format(topic=topic)
            sender,recipient=(source,target) if turn%2==0 else (target,source)
            # Dialogue on each edge is monotonic, always after contact approval.
            edge_index=index%len(edges)
            turns=(self.c.messages-1-edge_index)//len(edges)+1
            interval=(self.now-60-connected-3600)/(turns+1)
            created=connected+3600+(turn+1)*interval
            self.insert('messages',(self.identifier('message',index),sender,recipient,text,created,int(turn<max(0,self.c.messages//len(edges)-3))))

    def run(self, attach_demo=False, reset=False):
        existing=self.r.one('SELECT manifest FROM seed_runs WHERE namespace=?',(self.c.namespace,))
        if existing and not reset:return json.loads(existing['manifest'])
        with self.r.transaction():
            self.clear();self.make_users(attach_demo);self.make_network();self.make_content();self.interactions();self.conversations()
            self.insert('audit',(self.identifier('audit'),'development.seed.created',digest(self.c.namespace),self.now))
            foreign=self.r.db.execute('PRAGMA foreign_key_check').fetchall()
            if foreign:raise ValueError('O seed violou a integridade de referências.')
            counts={table:self.r.one(f'SELECT count(*) n FROM {table} WHERE id LIKE ?',(self.prefix+'%',))['n'] for table in ('users','posts','messages','comments','reports','media','feed_views','family_discussions')}
            counts['approvedConnections']=len(self.edges)
            counts['posts']=self.c.posts
            counts['stories']=self.c.stories
            counts['likes']=self.r.one('SELECT count(*) n FROM likes l JOIN posts p ON p.id=l.post WHERE p.id LIKE ?',(self.prefix+'%',))['n']
            counts['suspendedUsers']=sum(p['suspended'] for p in self.people)
            counts['unverifiedUsers']=sum(not p['verified'] for p in self.people)
            manifest=dict(namespace=self.c.namespace,randomSeed=self.c.random_seed,created=self.now,counts=counts,
                suppliedImages=len(self.catalog),demoAccountsConnected=[p['id'] for p in self.anchors],
                authentication='Existing Firebase demo logins only; generated profiles have no Firebase identity or known password.',
                network='Approved reciprocal contacts, pending requests, blocks and explicit synthetic guardian consents.',
                users=[dict(p,avatar='/media/'+self.identifier('media-avatar',p['index'])) for p in self.people],
                media=self.media,posts=self.posts[:12])
            self.insert('seed_runs',(self.c.namespace,self.now,json.dumps(manifest,ensure_ascii=False)))
        return manifest


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--database',default=str(ROOT/'conexia.sqlite3'))
    parser.add_argument('--users',type=int,default=120);parser.add_argument('--posts',type=int,default=2400)
    parser.add_argument('--stories',type=int,default=360);parser.add_argument('--messages',type=int,default=18000)
    parser.add_argument('--namespace',default='qa-demo-v1');parser.add_argument('--seed',type=int,default=20261015)
    parser.add_argument('--reset',action='store_true',help='Replace only records owned by this seed namespace.')
    parser.add_argument('--connect-demo-accounts',action='store_true')
    parser.add_argument('--output',default=str(ROOT/'fixtures'/'seed_manifest.json'))
    args=parser.parse_args()
    if os.environ.get('CONEXIA_DEV')!='1':raise SystemExit('Este script exige CONEXIA_DEV=1 e destina-se apenas a dados fictícios locais.')
    config=SeedConfig(args.users,args.posts,args.stories,args.messages,args.namespace,args.seed);config.validate()
    path=Path(args.database).resolve()
    if path.exists() and path.stat().st_size:
        destination=Path.home()/'Documents'/'Conexia-backups'/f'before-seed-{int(time.time()*1000)}.sqlite3'
        backup(path,destination)
        print('Backup consistente criado em:',destination)
    repo=Repository(str(path))
    try:manifest=Seeder(repo,config).run(args.connect_demo_accounts,args.reset)
    finally:repo.db.close()
    output=Path(args.output).resolve();output.parent.mkdir(parents=True,exist_ok=True)
    output.write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps({'namespace':config.namespace,'counts':manifest['counts'],'manifest':str(output)},ensure_ascii=False))


if __name__=='__main__':main()
