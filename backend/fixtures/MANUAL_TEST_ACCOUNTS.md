# Contas para testes manuais

`create_manual_test_accounts.py` provisiona exatamente 15 contas fictícias adultas
ativas no Firebase `conexiabeta2` e no SQLite usado pela API. Não concede acesso
administrativo. Os e-mails `example.com` não recebem mensagens: a verificação
é simulada exclusivamente nestas contas de QA.

Cada perfil possui nome, biografia, data de nascimento adulta e foto ilustrativa
Random User. A URL fica no Firebase e no arquivo de acessos; os pixels validados
são armazenados como BLOB no SQLite, conforme a arquitetura do aplicativo.

Requisitos: dependências do backend, credencial Firebase Admin e variáveis
`CONEXIA_DEV=1`, `FIREBASE_PROJECT_ID=conexiabeta2`,
`GOOGLE_APPLICATION_CREDENTIALS` e `QA_PASSWORD` (mínimo 12 caracteres).
Opcionalmente, `DATABASE_PATH` aponta para o mesmo banco utilizado pela API.
Execute na raiz: `python backend/create_manual_test_accounts.py`.

O script preserva contas existentes, recusa conflitos de identidade e reutiliza
os mesmos 15 UIDs em reexecuções. Não redefine senhas existentes. Um backup SQLite
é salvo em `~/Documents/Conexia-backups` antes da execução. Os acessos são salvos
fora do repositório em `~/Downloads/Conexia-15-acessos-teste.json`; preserve esse
arquivo para reexecuções. Não publique o arquivo de acessos nem credenciais Admin.

Esse lote não converte os perfis sintéticos do seed anterior. Não cria posts,
contatos ou mensagens automaticamente: permite testar essas ações manualmente.

## Publicações das contas manuais

Com `CONEXIA_DEV=1`, execute `python backend/seed_manual_posts.py` na raiz.
São 60 posts (3, 4 ou 5 por perfil): 35 somente texto e 25 com fotos
ilustrativas do Lorem Picsum, sem repetição de pixels ou legendas neste lote.
As datas são distribuídas pelos dias anteriores à primeira execução.
O script faz backup SQLite, valida imagens, grava o lote em uma transação e
registra as URLs em `seed_runs.manifest`. Reexecuções não duplicam os posts.
Contas, senhas e publicações anteriores são preservadas.

## Conversas, conexões e curtidas

Execute `python backend/seed_manual_interactions.py` com `CONEXIA_DEV=1` após os
lotes de contas e posts. O lote gera 20 chats com 12 mensagens alternadas cada
(240 mensagens), datas anteriores à execução, intervalos variados e mensagens
lidas/não lidas. Cada chat tem um tema próprio. Ana tem 8 conversas; Lucas, 7.
Isabela Cristina Duarte, Thiago Matheus Barbosa e Vitoria Reis Monteiro ficam
sem chats para testar telas vazias. Se já tiverem mensagens, o script interrompe
sem apagá-las.

São criadas 36 conexões recíprocas usando a regra de solicitação e aceite do
aplicativo (não há seguidores unilaterais neste modelo). A aleatoriedade usa
semente fixa para reprodução. Os chats só envolvem contatos aprovados. O lote
inicial acrescentou 378 curtidas nos 60 posts, com distribuição desigual e
alguns posts sem curtidas. Sem autocurtidas neste lote.

Há backup prévio, transação única, validação das contas e preservação de
bloqueios/preferências. O registro em `seed_runs` impede duplicação ao executar
novamente. As contas de teste mantêm suas senhas e permissões anteriores.

## Famílias fictícias com login Firebase

`backend/create_family_test_accounts.py` cria 3 identidades de menores no Firebase
conexiabeta2 e as vincula pelo serviço real `/guardian/children`, usando tokens
Firebase válidos de cada responsável e menor. Requer `CONEXIA_DEV=1`,
`FIREBASE_PROJECT_ID=conexiabeta2`, `GOOGLE_APPLICATION_CREDENTIALS`, `QA_PASSWORD`
e o arquivo externo de acessos das 15 contas. Use apenas no ambiente de QA.

- Sofia Martins Rocha (SofiArte, nascimento 2016-02-10): Juliana Martins Rocha.
- Leonardo Araujo Batista (LeoExplora, nascimento 2013-04-18): Fernanda Araujo Batista.
- Beatriz Rodrigues Alves (BiaCriativa, nascimento 2010-06-22): Diego Rodrigues Alves.

São pessoas fictícias, com identidades autenticáveis. Os e-mails example.com não
recebem mensagens: a confirmação é simulada via Admin somente para este lote.
O consentimento dos responsáveis e os registros de atividade também são dados
sintéticos para testes; não comprovam confirmação ou utilização por pessoas reais.
As fotos são ilustrações já fornecidas ao projeto. Menores ficam privados, com
apelido escolhido no fluxo de perfil. Responsáveis existentes são preservados.

O cenário inclui 9 posts, 6 chats com 12 mensagens cada, 9 curtidas, 9 comentários,
3 registros de atividade por menor e 1 tópico familiar por vínculo. Contatos entre
menores passam por aceite e aprovação independente dos dois responsáveis. O painel
familiar não concede acesso às conversas privadas do menor com outras pessoas.

Acessos: `~/Downloads/Conexia-acessos-familias-teste.json`, fora do repositório.
Backup prévio em `~/Documents/Conexia-backups`. O marcador em `seed_runs` evita
recriar o lote após sucesso. Firebase e SQLite não formam uma transação única:
se houver interrupção, preserve o arquivo de acessos e reexecute com a mesma senha.
