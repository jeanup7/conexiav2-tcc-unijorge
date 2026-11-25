"""Add 3–5 varied posts to each manual QA account, atomically and idempotently."""
import base64
import hashlib
from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import sqlite3
import time
import urllib.request
from create_manual_test_accounts import NAMESPACE, PEOPLE
from images import normalize
from repository import Repository

# Captions belong to fictional profiles. Pictures are illustrative placeholders.
CAPTIONS = [
 ['Terminei um livro que me fez voltar várias páginas só para reler os trechos favoritos. Vocês também fazem isso?', 'Uma pausa para olhar o mundo com mais calma. Separei esta imagem para meu mural de inspiração.', 'Meta da semana: trocar alguns minutos de tela por um capítulo antes de dormir.'],
 ['Finalmente entendi aquele erro no meu projeto: eu estava lendo a variável errada. Pequenas vitórias contam!', 'Minha referência visual de hoje. Gosto de guardar imagens que me fazem pensar em novas ideias.', 'Quem topa um futebol no fim de semana? Desta vez prometo chegar antes do aquecimento.', 'Montando um painel de referências para a próxima interface. Que sensação essa imagem passa para vocês?'],
 ['Na aula de hoje, cada pessoa explicou uma ideia usando um desenho. Surgiram interpretações que eu nunca teria imaginado.', 'Referência para uma atividade: observar a imagem e inventar uma história em três frases.', 'Qual quadrinho vocês indicariam para alguém que quer começar a ler?', 'Escolhi esta imagem para exercitar descrições: o desafio é escrever sem usar a palavra bonito.', 'Uma boa pergunta dos alunos vale mais que um slide cheio de respostas prontas.'],
 ['Fiz meu primeiro formulário funcionar! Agora falta aprender a mostrar mensagens de erro que realmente ajudem.', 'Colecionando referências de luz e composição para fotografar melhor com o celular.', 'Descoberta do dia: fazer uma pausa resolveu mais que ficar encarando o código por uma hora.'],
 ['O bolo não cresceu como eu esperava, mas o café da tarde estava garantido. Na próxima vou medir tudo direitinho.', 'Uma referência de cor para experimentar no próximo desenho. Gostei do clima dessa imagem.', 'Assistimos a um filme e ficamos discutindo o final por mais tempo que os créditos. Adoro quando isso acontece.', 'Mais uma imagem no meu caderno de ideias. Quero testar uma composição diferente neste fim de semana.'],
 ['Voltei a pedalar depois de um tempo parado. Fui devagar, aproveitei o caminho e já quero repetir.', 'Imagem para lembrar que diminuir o ritmo também faz parte do passeio.', 'Qual música não pode faltar numa playlist de domingo? Estou renovando a minha.', 'Uma referência para o próximo roteiro de fotos. Às vezes o detalhe vale mais que a vista inteira.', 'Li sobre como as bicicletas se equilibram e fiquei com mais perguntas do que respostas. Ciência tem dessas!'],
 ['As sementes começaram a brotar! Anotar a evolução todo dia transformou um vasinho em uma pequena investigação.', 'Imagem escolhida para nossa roda de observação. Quantos detalhes vocês perceberam primeiro?', 'Quero montar uma troca de livros: cada pessoa deixa uma recomendação dentro da capa.'],
 ['Testei desenhar a mesma expressão de cinco jeitos. O mais simples acabou sendo o que melhor funcionou.', 'Referência visual para estudar contraste. Vou tentar reproduzir só com dois tons.', 'Animação dá trabalho: mexer poucos milímetros muda completamente a sensação de movimento.', 'Guardando esta composição para um estudo de enquadramento. Hoje a ideia é observar antes de desenhar.'],
 ['Hoje escolhemos uma história juntos e cada um inventou um final. Nenhum ficou parecido com o original.', 'Inspiração para uma atividade em família: escolher três palavras que combinem com a imagem.', 'Uma coisa que funcionou aqui: combinar o horário de parar antes de começar a jogar.', 'Nosso próximo desafio criativo vai começar com esta referência. Vale colagem, desenho ou uma história.', 'Estou procurando jogos de mesa cooperativos. Alguém tem uma indicação para jogar em família?'],
 ['Perdi a partida, mas descobri uma estratégia nova. Acho que vou precisar de uma revanche para testar.', 'Uma imagem para descansar os olhos entre uma rodada e outra. Pausa também entra na estratégia.', 'Tentei reconhecer constelações ontem. Encontrei poucas, mas gostei de ficar um tempo olhando o céu.'],
 ['Levei meu caderno para observar o entorno e terminei com perguntas sobre plantas que vejo todos os dias.', 'Referência para praticar observação: olhar por um minuto e depois listar o que ficou na memória.', 'Estudar com alguém que faz perguntas diferentes ajuda muito. Hoje revisamos o conteúdo sem abrir os slides.', 'Uma imagem para meu mural de curiosidades. Quero transformar as observações em perguntas para pesquisar.'],
 ['Nosso passeio de domingo virou uma competição de quem encontrava mais formas diferentes nas nuvens.', 'Referência para planejar uma tarde longe da correria. O importante vai ser aproveitar a companhia.', 'Aprendi uma brincadeira nova com meu filho. É bom lembrar que ensinar e aprender acontecem dos dois lados.', 'Escolhemos esta imagem como ponto de partida para inventar uma aventura em família.', 'Dez minutos de bola no quintal renderam mais risadas que o placar inteiro.'],
 ['Aprendi os primeiros acordes de uma música que gosto. Ainda estou bem devagar, mas já reconheço a melodia.', 'Imagem para combinar com uma playlist tranquila. Que música vocês escolheriam?', 'Troquei recomendações de livros com uma amiga e minha lista de leitura só aumentou.'],
 ['O protótipo finalmente respondeu ao sensor! Agora vou repetir o teste para entender quando ele falha.', 'Uma referência visual para pensar no painel do nosso projeto. Quero algo simples de entender.', 'Treinei arremessos hoje. Contar as tentativas me ajudou mais do que lembrar só dos acertos.', 'Imagem escolhida para uma dinâmica: como transformar uma inspiração em algo que a gente consiga construir?'],
 ['Redesenhei um trabalho antigo e percebi o quanto mudou meu jeito de escolher cores. Vale guardar os rascunhos.', 'Referência para meu estudo de hoje. Vou começar pelas formas maiores e deixar os detalhes para depois.', 'Uma colega me ensinou um atalho e economizou uma tarde inteira. Compartilhar conhecimento faz diferença.', 'Mais uma imagem para exercitar paletas. Quero tentar uma versão com apenas três cores.', 'Meu desafio da semana é explicar uma ideia difícil com um desenho simples. Aceito sugestões de temas!'],
]
CATEGORIES=['other','education','education','art','art','sports','education','art','education','games','education','sports','education','education','art']
PREFIX=NAMESPACE+'-social-v1'

def main():
    if os.environ.get('CONEXIA_DEV')!='1':
        raise SystemExit('Execute somente com CONEXIA_DEV=1 no ambiente de teste.')
    path=Path(os.environ.get('DATABASE_PATH',str(Path(__file__).parent/'conexia.sqlite3')))
    if not path.is_file():
        raise SystemExit('Banco existente não encontrado.')
    with sqlite3.connect(path) as db:
        for i,person in enumerate(PEOPLE,1):
            row=db.execute('SELECT email FROM users WHERE id=?',(f'{NAMESPACE}-{i:02}',)).fetchone()
            if row!=(person[1]+'.qa15@example.com',):
                raise SystemExit('Crie primeiro as 15 contas de teste esperadas.')
        if db.execute('SELECT 1 FROM seed_runs WHERE namespace=?',(PREFIX,)).fetchone():
            print('Lote já aplicado: nenhuma publicação duplicada.'); return
    assert len(CAPTIONS)==15 and [len(c) for c in CAPTIONS]==[3,4,5]*5
    assert len({t for group in CAPTIONS for t in group})==60
    now=time.time()
    posts=[]
    for i,group in enumerate(CAPTIONS,1):
        for j,caption in enumerate(group):
            pid=f'{PREFIX}-{i:02}-{j+1}'
            posts.append(dict(id=pid,user=f'{NAMESPACE}-{i:02}',text=caption,category=CATEGORIES[i-1],created=now-((j*41+i*7)*3600+i*137),photo_url=f'https://picsum.photos/seed/conexiaqa{i:02}post{j+1}/960/720' if j%2 else None))
    def download(p):
        req=urllib.request.Request(p['photo_url'],headers={'User-Agent':'ConexiaDevelopmentFixtures/1.0'})
        for attempt in range(3):
            try:
                with urllib.request.urlopen(req,timeout=40) as response:
                    raw=response.read(5*1024*1024+1)
                return p['id'],normalize({'mime':'image/jpeg','data':base64.b64encode(raw).decode()})
            except Exception:
                if attempt==2: raise
    with ThreadPoolExecutor(max_workers=5) as pool:
        media=dict(pool.map(download,[p for p in posts if p['photo_url']]))
    seen=set()
    for post in posts:
        if not post['photo_url']: continue
        original=post['photo_url']
        for attempt in range(10):
            fingerprint=hashlib.sha256(media[post['id']][1]).hexdigest()
            if fingerprint not in seen:
                seen.add(fingerprint); break
            post['photo_url']=original.replace('/960/720',f'variant{attempt}/960/720')
            _,media[post['id']]=download(post)
        else: raise RuntimeError('Não foi possível obter imagens distintas.')
    backup=Path.home()/'Documents/Conexia-backups'/f'qa15-posts-{time.time_ns()}.sqlite3'
    backup.parent.mkdir(parents=True,exist_ok=True)
    with sqlite3.connect(path) as source, sqlite3.connect(backup) as dest:
        source.backup(dest)
    repo=Repository(str(path))
    with repo.transaction():
        if repo.one('SELECT 1 FROM seed_runs WHERE namespace=?',(PREFIX,)):
            print('Lote já aplicado por outra execução.'); return
        for p in posts:
            mid=p['id']+'-photo' if p['photo_url'] else None
            if mid:
                mime,data=media[p['id']]
                repo.db.execute('INSERT INTO media VALUES(?,?,?,?)',(mid,p['user'],mime,data))
            repo.db.execute('INSERT INTO posts VALUES(?,?,?,?,0,?,NULL)',(p['id'],p['user'],p['text'],mid,p['created']))
            if mid: repo.db.execute('INSERT INTO post_media VALUES(?,?,0)',(p['id'],mid))
            repo.db.execute('INSERT INTO post_categories VALUES(?,?)',(p['id'],p['category']))
        repo.db.execute('INSERT INTO seed_runs VALUES(?,?,?)',(PREFIX,now,json.dumps({'posts':posts,'text_only':35,'with_photo':25},ensure_ascii=False)))
        assert not repo.rows('PRAGMA foreign_key_check')
        for i,group in enumerate(CAPTIONS,1):
            assert repo.one('SELECT COUNT(*) n FROM posts WHERE user=? AND id LIKE ?',(f'{NAMESPACE}-{i:02}',PREFIX+'-%'))['n']==len(group)
    repo.db.close()
    print('Criadas 60 publicações: 35 só texto e 25 com fotos. Distribuição: 3/4/5 por perfil. Backup: '+str(backup))

if __name__=='__main__': main()
