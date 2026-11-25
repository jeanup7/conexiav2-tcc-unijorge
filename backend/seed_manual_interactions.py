"""Reproducible conversations, mutual contacts and likes for the 15 QA profiles."""
import json
import os
from pathlib import Path
import random
import sqlite3
import time
from create_manual_test_accounts import NAMESPACE, PEOPLE
from seed_manual_posts import PREFIX as POST_PREFIX
from repository import Repository
from service import Service

BATCH=NAMESPACE+'-interactions-v1'
# Each conversation has its own coherent topic; alternating turns, six exchanges.
DIALOGUES=[
 ['Você conseguiu terminar o livro do clube?','Terminei ontem! Anotei duas partes para comentar.','A mudança do personagem no final me pegou de surpresa.','Também achei. No começo ele parecia tão decidido.','Vamos conversar sobre isso no sábado?','Pode ser depois das dez.','Vou levar meu caderno com as anotações.','Boa, vou separar os trechos que marquei.','Sem spoilers para quem ainda não terminou, combinado?','Combinado. Primeiro perguntamos em que capítulo estão.','Então deixo o encontro marcado para dez e meia.','Fechado! Até sábado.'],
 ['Queria experimentar aquela atividade de contar histórias com imagens.','Funciona bem começar com uma pergunta simples.','Algo como o que aconteceu antes dessa cena?','Isso! Depois cada pessoa inventa uma continuação.','Quanto tempo você costuma dar?','Uns cinco minutos para pensar e mais cinco para compartilhar.','Posso deixar desenhar em vez de escrever?','Claro, ajuda quem prefere se expressar visualmente.','Vou testar com um grupo pequeno primeiro.','Depois me conta quais perguntas renderam mais.','Vou anotar as respostas sem colocar nomes.','Ótimo, assim você acompanha a atividade com cuidado.'],
 ['Estou tentando fotografar melhor com o celular. Alguma dica?','Começa limpando a lente e observando de onde vem a luz.','Minhas fotos ficam muito claras perto da janela.','Toca na parte mais clara e reduz um pouco a exposição.','Vou experimentar hoje à tarde.','Faz a mesma foto com três ajustes diferentes.','Gostei da ideia de comparar depois.','É mais fácil perceber a diferença lado a lado.','Testei aqui e já ficou melhor!','Boa! Qual ajuste funcionou?','O intermediário preservou os detalhes.','Então guarda como referência para a próxima.'],
 ['Você tem uma receita simples para o café da tarde?','Tenho uma de bolo de banana que faço bastante.','Precisa de batedeira?','Não, dá para misturar com um garfo.','Melhor ainda, a minha está guardada longe.','Usa bananas bem maduras para dar sabor.','Vou separar os ingredientes antes de começar.','Ajuda muito. E confere se o fermento está na validade.','Era justamente isso que eu esquecia de olhar.','Já aconteceu comigo também.','Depois te conto se ficou bom.','Combinado, quero saber como saiu!'],
 ['Como foi a volta aos passeios de bicicleta?','Foi tranquila, escolhi um caminho curto.','Estou pensando em voltar também.','Vale começar sem preocupação com distância.','Você saiu em que horário?','Bem cedo, para evitar o calor mais forte.','Vou revisar a bicicleta antes.','Boa ideia, principalmente freios e pneus.','Prefiro um lugar com ciclovia nessa primeira vez.','Também acho mais confortável para retomar.','Vou planejar um percurso pequeno.','Depois conta como foi o passeio.'],
 ['Quero começar uma horta pequena. O que você plantou?','Comecei com temperos em dois vasos.','Meu espaço recebe sol só pela manhã.','Então observa bem esse horário antes de escolher as plantas.','Posso anotar quantas horas pega sol?','Pode, isso ajuda a explicar as condições na loja.','Vou reaproveitar uns recipientes.','Lembra de conferir a drenagem deles.','Boa, eu não tinha pensado nisso.','E coloca etiquetas para lembrar o que plantou.','Vou fazer um diário com fotos semanais.','Adorei! Dá para acompanhar as mudanças com calma.'],
 ['Vi seu comentário sobre estudar expressões no desenho.','Estou tentando simplificar os rostos.','Você começa pelos olhos?','Geralmente começo pela inclinação da cabeça.','Nunca tinha pensado nesse detalhe.','Muda bastante a sensação mesmo sem desenhar a boca.','Vou tentar três poses no meu caderno.','Faz primeiro só as formas grandes.','Depois posso te mostrar os rascunhos?','Pode sim, gosto de trocar ideias sobre o processo.','Vou guardar as versões, até as que não derem certo.','Essas também ajudam a perceber a evolução.'],
 ['Como vocês escolheram a história para ler em família?','Cada pessoa sugeriu uma e fizemos um sorteio.','Achei justo. Sempre fico na dúvida do que escolher.','Na semana seguinte usamos outra sugestão.','Vocês leem tudo de uma vez?','Não, paramos quando o pessoal fica cansado.','Gostei de não transformar em obrigação.','Isso, a ideia é aproveitar juntos.','Vou tentar no domingo.','Depois pergunta qual parte cada um mais gostou.','Já separei duas opções curtas.','Ótimo começo! Depois me conta a escolhida.'],
 ['Conseguiu resolver o erro naquele formulário?','Sim, eu estava usando o nome errado de um campo.','Como você percebeu?','Comparei o que enviava com o que o servidor esperava.','Vou começar a fazer essa conferência também.','Ajuda olhar os nomes antes de mudar um monte de código.','Agora você vai testar campos vazios?','Exatamente, e também um e-mail inválido.','Não esquece de testar duas tentativas seguidas.','Boa lembrança, vou incluir.','Depois quero ver como ficou a mensagem de erro.','Te mostro quando terminar os ajustes.'],
 ['Você encontrou um jeito melhor de organizar as fotos?','Separei por mês e deixei uma pasta só para favoritas.','Eu estava criando pastas demais.','Aconteceu comigo. Depois eu não encontrava nada.','Vou começar pelas fotos desta semana.','Boa, organizar tudo de uma vez cansa.','Você apaga as repetidas na hora?','Primeiro comparo, às vezes uma tem um detalhe melhor.','Faz sentido guardar a melhor versão.','E conferir o backup antes de remover qualquer coisa.','Vou fazer uma cópia primeiro.','Aí fica mais tranquilo para organizar.'],
 ['Tem alguma indicação de filme para o fim de semana?','Você quer algo leve ou uma história para discutir depois?','Uma história que renda conversa.','Então podemos escolher um mistério sem ser muito pesado.','Gosto quando dá para tentar adivinhar o final.','Eu também, mas sempre mudo de palpite.','Vamos fazer uma lista com três opções?','Faço a minha hoje à noite.','Depois escolhemos uma que ninguém viu.','Fechado, e sem pesquisar o final antes.','Pode deixar, vou fugir dos comentários.','Assim a surpresa fica para a sessão.'],
 ['Você está montando uma playlist nova?','Sim, quero variar as músicas que escuto no domingo.','Posso sugerir umas instrumentais?','Pode, gosto de colocar enquanto leio.','Vou separar as mais tranquilas.','Obrigado! Depois faço uma lista para caminhar.','Nessa pode ter um ritmo mais animado.','Exatamente, mas sem ficar trocando de faixa toda hora.','Você organiza por atividade?','Estou começando, fica mais fácil escolher.','Vou testar esse jeito também.','Depois a gente compara as descobertas.'],
 ['Como ficou o diário de observação das plantas?','Já tem uma semana de registros.','Você mediu todos os dias?','Não, fiz fotos e anotei quando reguei.','Bom para lembrar o que mudou.','Sim, percebi que um vaso seca bem mais rápido.','Eles ficam no mesmo lugar?','Um pega mais vento perto da janela.','Pode ser uma pista para investigar.','Vou observar sem mudar tudo de uma vez.','Assim dá para comparar melhor.','Isso, na próxima semana te conto.'],
 ['Quero tentar uma animação curta. Por onde começo?','Uma bola quicando é um exercício bom.','Quantos desenhos preciso fazer?','Começa com poucos e ajusta depois de ver o movimento.','Eu ia tentar uma cena inteira logo.','Dá vontade, mas o exercício pequeno ajuda bastante.','Vou separar vinte minutos por dia.','Ótimo, guarda uma versão de cada tentativa.','Assim vejo se ficou mais natural.','Isso, principalmente no momento em que toca o chão.','Vou prestar atenção nessa parte.','Depois me mostra como ficou!'],
 ['Qual jogo cooperativo vocês experimentaram?','Um em que todos resolvem um desafio juntos.','Gostei de ninguém sair antes do fim.','Também achei, todo mundo continua participando.','As regras demoraram para explicar?','Fizemos uma rodada de demonstração primeiro.','Bem melhor que ler tudo de uma vez.','Sim, aprendemos algumas coisas jogando.','Vou procurar um com partidas curtas.','É bom para testar se o grupo gosta.','Depois a gente pode combinar uma tarde.','Combinado, eu levo o que tenho aqui.'],
 ['Conseguiu observar o céu ontem?','Consegui por alguns minutos antes de ficar nublado.','Você usa algum mapa para se orientar?','Uso um guia simples e tento encontrar uma região por vez.','Eu fico perdido tentando achar tudo.','Eu também ficava, por isso diminuí a meta.','Vou começar só reconhecendo a direção.','Já ajuda bastante, sem pressa.','Tem que esperar um dia com menos nuvens.','Sim, ontem não deu para ver muita coisa.','Mesmo assim deve ter sido uma pausa boa.','Foi, fiquei um tempo longe do celular.'],
 ['Como você faz suas anotações de biologia?','Tento transformar cada tópico em uma pergunta.','E responde sem olhar o material?','Primeiro sim, depois confiro o que faltou.','Gostei, parece melhor que só reler.','Para mim ajuda a perceber as dúvidas.','Vou testar com um assunto curto.','Escolhe um que você acabou de estudar.','Depois posso trocar perguntas com você?','Claro, perguntas diferentes ajudam muito.','Vou preparar cinco para começar.','Fechado, eu preparo cinco também.'],
 ['A brincadeira com as nuvens deu certo?','Deu! Cada um enxergava uma coisa diferente.','Quero tentar num passeio em família.','Dá para fazer sem levar material nenhum.','Quanto tempo vocês ficaram?','Só alguns minutos, depois continuamos andando.','Bom para encaixar sem planejar demais.','Sim, as melhores ideias apareceram na hora.','Vou deixar espaço no passeio para isso.','Depois pergunta qual foi a forma mais engraçada.','Já imagino as respostas.','Aqui uma nuvem virou um dragão com mochila!'],
 ['Você conseguiu praticar os acordes hoje?','Consegui trocar dois sem parar tanto.','Já é um progresso! Quanto tempo treinou?','Uns quinze minutos, bem devagar.','Acho difícil não querer acelerar.','Eu também, mas erro menos quando diminuo.','Você repete um trecho pequeno?','Sim, só depois junto com o restante.','Vou usar essa ideia no meu estudo também.','Funciona para dividir um desafio grande.','Amanhã quero tentar de novo com calma.','Depois me conta como foi.'],
 ['O sensor funcionou em todas as tentativas?','Ainda não, falhou quando mudei a posição.','Você anotou a distância em cada teste?','Comecei a anotar depois da terceira tentativa.','Talvez ajude repetir nas mesmas condições.','Vou montar uma tabelinha para comparar.','Muda só uma coisa de cada vez.','Boa, antes eu mudava posição e iluminação juntas.','Aí fica difícil saber o que resolveu.','Exatamente, vou repetir com mais cuidado.','Quando funcionar, guarda também o resultado que falhou.','Pode deixar, vai ajudar a explicar o processo.'],
]

def main():
    if os.environ.get('CONEXIA_DEV')!='1': raise SystemExit('Use CONEXIA_DEV=1.')
    path=Path(os.environ.get('DATABASE_PATH',str(Path(__file__).parent/'conexia.sqlite3')))
    if not path.is_file(): raise SystemExit('Banco existente não encontrado.')
    with sqlite3.connect(path) as db:
        if db.execute('SELECT 1 FROM seed_runs WHERE namespace=?',(BATCH,)).fetchone():
            print('Lote já aplicado; nenhuma interação duplicada.'); return
    backup=Path.home()/'Documents/Conexia-backups'/f'qa15-interactions-{time.time_ns()}.sqlite3'
    backup.parent.mkdir(parents=True,exist_ok=True)
    with sqlite3.connect(path) as src, sqlite3.connect(backup) as dst: src.backup(dst)
    repo=Repository(str(path)); api=Service(repo,development=True)
    users=[repo.one('SELECT * FROM users WHERE id=?',(f'{NAMESPACE}-{i:02}',)) for i in range(1,16)]
    for u,person in zip(users,PEOPLE):
        if not u or u['email']!=person[1]+'.qa15@example.com': raise ValueError('Conta QA ausente ou divergente.')
        api.active(u)
        if not u['messages']: raise ValueError('Mensagens desativadas: preserve a preferência e revise o cenário.')
    # Three empty inboxes; never delete preexisting messages to force this state.
    for u in users[12:]:
        if repo.one('SELECT 1 FROM messages WHERE sender=? OR recipient=?',(u['id'],u['id'])):
            raise ValueError('Uma conta reservada para tela vazia já tem mensagens; nada foi removido.')
    chats=[(0,i) for i in range(1,9)]+[(1,i) for i in range(2,8)]+[(2,8),(3,9),(4,10),(5,11),(6,10),(7,11)]
    assert len(chats)==len(DIALOGUES)==20 and all(len(d)>=10 for d in DIALOGUES)
    rng=random.Random(20261019)
    pairs=set(chats)
    for a in range(15):
        for b in range(a+1,15):
            if rng.random()<0.23: pairs.add((a,b))
    # Ensure even the empty-inbox profiles have at least one connection.
    for i in range(12,15): pairs.add((rng.randrange(12),i))
    now=time.time(); inserted_likes=0
    with repo.transaction():
        if repo.one('SELECT 1 FROM seed_runs WHERE namespace=?',(BATCH,)): return
        for a,b in sorted(pairs):
            ua,ub=users[a],users[b]
            if api.blocked(ua['id'],ub['id']): raise ValueError('Conexão bloqueada; nenhuma preferência será sobrescrita.')
            result=api.contacts.create(ua,ub['id'])
            if result['status']!='approved': api.contacts.accept(ub,ua['id'])
        for k,((a,b),dialogue) in enumerate(zip(chats,DIALOGUES)):
            stamp=now-(k+1)*9*3600
            for n,line in enumerate(dialogue):
                stamp+=rng.randint(35,240) if n!=6 else rng.randint(1800,7200)
                sender,recipient=(a,b) if n%2==0 else (b,a)
                # Some trailing incoming messages remain unread.
                read=int(not(k%3==0 and n>=9))
                repo.db.execute('INSERT INTO messages VALUES(?,?,?,?,?,?)',(f'{BATCH}-chat{k:02}-msg{n:02}',users[sender]['id'],users[recipient]['id'],line,stamp,read))
        posts=repo.rows('SELECT id,user FROM posts WHERE id LIKE ? ORDER BY id',(POST_PREFIX+'-%',))
        if len(posts)!=60: raise ValueError('Esperadas as 60 publicações do lote anterior.')
        for k,p in enumerate(posts):
            candidates=[u for u in users if u['id']!=p['user'] and api._can_post(u,p['id'])]
            count=0 if k%13==0 else min(len(candidates),rng.randint(1,12))
            for u in rng.sample(candidates,count):
                result=repo.db.execute('INSERT OR IGNORE INTO likes VALUES(?,?)',(u['id'],p['id']))
                inserted_likes+=result.rowcount
        manifest={'conversations':20,'messages':240,'connection_pairs':len(pairs),'likes_added':inserted_likes,'empty_inbox_users':[u['id'] for u in users[12:]],'chat_pairs':[[users[a]['id'],users[b]['id']] for a,b in chats]}
        repo.db.execute('INSERT INTO seed_runs VALUES(?,?,?)',(BATCH,now,json.dumps(manifest)))
        assert not repo.rows('PRAGMA foreign_key_check')
    repo.db.close()
    print(json.dumps(manifest,ensure_ascii=True))

if __name__=='__main__': main()
