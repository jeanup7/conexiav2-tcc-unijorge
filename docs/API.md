# API REST — Conexia Segura

Base local: `http://127.0.0.1:8080`. JSON UTF-8. Rotas privadas exigem `Authorization: Bearer ACCESS_TOKEN`. Não enviar tokens em query strings. Respostas de sucesso retornam HTTP 200, inclusive criação. Erros: `{"error":{"message":"mensagem legível"}}`. Status 400 validação, 401 sessão, 403 autorização/conta restrita, 404 recurso invisível/inexistente, 409 conflito de cadastro, 413 corpo excessivo, 429 limite, 500 falha interna.

## Autenticação

| Método / rota | Entrada | Resposta |
|---|---|---|
| GET /health | — | status, storage, development |
| POST /auth/register | name (1–60), email, password (12–128), birth (`AAAA-MM-DD`); guardianEmail para menores | message; developmentToken somente no modo local |
| POST /auth/verify | token | message; token de uso único, validade de 1 hora |
| POST /auth/firebase | Bearer ID token Firebase; name, birth, guardianEmail ao primeiro vínculo | user; validação server-side, UID associado ao perfil |
| POST /auth/login | email, password | accessToken, refreshToken, user |
| POST /auth/recover | email | mensagem genérica; developmentToken somente local, quando houver conta |
| POST /auth/reset | token, password nova | message; revoga todas as sessões |
| POST /auth/refresh | refreshToken | nova sessão; revoga acesso e refresh anteriores |
| POST /auth/logout | bearer | ok; revoga a sessão atual |

Access token: 15 minutos. Refresh: 7 dias com rotação, armazenado apenas como hash no banco. Limites locais: 180 requisições/IP/minuto; 30 tentativas em rotas `/auth/` por IP/minuto; 8 tentativas de login por endereço de e-mail em 15 minutos; 15 mensagens por remetente/minuto. Limites em memória são apenas para processo único e reiniciam com o servidor.

`user`: id, name, email, bio, private (0/1), messages (0/1), verified (0/1), approved (0/1), needsGuardian (boolean). Não retorna senha, birth nem guardianEmail. Perfil externo retorna apenas id, name, bio, private.

## Conta, direitos e segurança

| Método / rota | Entrada | Comportamento |
|---|---|---|
| GET /me | — | conta própria |
| PATCH /me | name, bio (até 180), private e messages (booleanos) | salva perfil; menores não podem tornar perfil público |
| DELETE /me | password | confirmação e exclusão em cascata |
| GET /me/export | — | profile, posts, comments, reports, blocks, messages; JSON sem credenciais |
| GET /guardian/status | — | required, approved, providerConfigured=false |
| POST /guardian/request | — | registra evento; não concede aprovação |
| GET /reports | — | items: apenas denúncias do solicitante |
| POST /reports | target, reason (3–1000) | id, status=pending, message |
| GET /blocks | — | items: id e name |
| POST /blocks | target (id) | bloqueio bidirecional de visibilidade/interação |
| DELETE /blocks/:id | — | remove somente bloqueio criado pelo solicitante |
| GET /notifications | — | items: id, text, created; até 50 |

Estas rotas podem ser utilizadas por conta com verificações pendentes, exceto login que ainda exige credenciais. Elas não liberam recursos sociais.

## Recursos sociais — exigem e-mail verificado e aprovação independente para menores

| Método / rota | Entrada | Resposta/regra |
|---|---|---|
| GET /profiles?q=termo | pesquisa até 60 caracteres | items; somente perfis visíveis; não expõe diretório de menores |
| GET /profiles/:id | — | id, name, bio, private; 404 para perfil invisível |
| GET /contacts | — | items: id, name, approved |
| POST /contacts | target | pedido pendente; nunca aprovação automática |
| GET /contacts/requests | — | pedidos pendentes recebidos e enviados; id do outro perfil, requestId, incoming, accepted, requiresGuardian; sem data de nascimento |
| POST /contacts/approve | target (remetente do pedido) | aceita o pedido; status approved somente após consentimento de cada responsável necessário; caso contrário awaiting_guardian |
| DELETE /contacts/requests/:requestId | — | remetente ou destinatário recusa/cancela o pedido pendente |
| DELETE /contacts/:id | — | desfaz conexão nas duas direções e cancela autorizações anteriores |
| GET /guardian/children/:child/contacts | — | responsável vinculado consulta pedidos e conexões do menor |
| PATCH /guardian/children/:child/contacts/:requestId | approved (booleano) | autoriza, recusa ou retira autorização de conexão ativa; exige vínculo do responsável |
| GET /posts?cursor=valor&limit=15 | cursor opaco exclusivo; limite 1–30; user opcional filtra autor visível | items e nextCursor (string ou null) |
| POST /posts | text (1–2000), mediaItems opcional (lista de até 10 IDs únicos próprios); media legado aceito | id |
| PATCH /posts/:id | text | somente autor |
| DELETE /posts/:id | — | somente autor; remove comentários e curtidas |
| POST /posts/:id/like | liked opcional (booleano) | define estado de forma idempotente; sem liked mantém alternância legada; retorna ok, liked e likes |
| GET /posts/:id/comments | — | items: id, name, text; exclui autores bloqueados |
| POST /posts/:id/comments | text (1–500) | id |
| GET /stories | paginação como feed | somente stories visíveis e não expirados |
| POST /stories | text, mediaItems opcional como posts | id; expira em 24 horas |
| POST /media | mime e data (base64) | id; JPEG/PNG/WebP estáticos, até 5 MB, 4096 pixels por lado e 16 milhões de pixels; valida pixels e regrava sem EXIF/localização; cota de 100 MB por conta |
| GET /media/:id | — | mime e data (base64); autor ou publicação visível vinculada |
| GET /conversations | — | perfis das conversas não bloqueadas |
| GET /messages/:perfil | cursor opcional | até 200 mensagens mais recentes, em ordem cronológica; nextCursor permite carregar mensagens anteriores; não marca leitura |
| POST /messages/:perfil/read | ids (1–200 IDs únicos) | marca somente mensagens recebidas desse perfil; rejeita integralmente lista inválida; exige contato aprovado |
| POST /messages/:perfil | text (1–1000) | id, status=sent; ambos devem permitir mensagens |

Publicação: id, user, text, media, mediaItems (IDs na ordem das fotos), story, created, expires, author, likes, liked. `media` continua retornando a primeira imagem para compatibilidade. A tabela adicional `post_media` é criada automaticamente ao reiniciar a API; posts antigos continuam visíveis.

Datas de eventos são epoch em segundos. O cursor opaco combina horário e ID para evitar perdas quando há horários iguais; envie nextCursor sem interpretar seu conteúdo, somente quando não for nulo. Cursores numéricos antigos continuam aceitos na entrada para compatibilidade, mas não oferecem desempate. Perfis privados só podem ser vistos pelo próprio autor ou contatos aprovados; bloqueios prevalecem. Stories usam as mesmas regras. Compartilhar o identificador não concede acesso ao conteúdo.

Mensagens usam polling a cada 8 segundos no Flutter, apenas com a conversa ativa e o aplicativo em primeiro plano. O cliente solicita confirmação de leitura quando a mensagem recebida fica pelo menos metade visível durante dois segundos. Não existe confirmação de entrega ao dispositivo, somente envio persistido e leitura. Vídeos, mensagens com imagens, WebSocket, busca textual de posts e push não possuem endpoints nesta versão.

## Troca de banco e implantação

`Repository` (`backend/repository.py`) concentra a conexão, esquema e execução parametrizada. `Service` contém regras e não acessa um arquivo de banco diretamente. Migrar para PostgreSQL exige novo adapter, migrações e adaptação das operações SQL específicas do SQLite; não exige refazer telas ou contratos HTTP. Os serviços ainda usam SQL e não constituem um ORM completamente independente do banco.

O servidor `http.server` é de desenvolvimento e a inicialização pública continua bloqueada. Para implantação ainda é necessário servidor adequado, TLS e gateway, limites compartilhados entre processos, autenticação administrativa de produção, testes de carga, armazenamento com criptografia e política operacional de backups. `CONEXIA_DEV` precisa continuar restrito a ambiente local. O SQLite usa WAL, foreign keys, timeout de bloqueio, transações com savepoints e migração aditiva identificada por user_version. Não use cópia simples do arquivo enquanto WAL estiver ativo: `python backend/backup.py --source caminho/conexia.sqlite3 --output caminho-protegido/backup.sqlite3` usa a API de backup e verifica sua integridade. O backup contém dados pessoais e deve ficar em armazenamento protegido.

## Autenticação Firebase

O cliente atual usa o ID token Firebase como Bearer para as rotas sociais. A API verifica esse token com Firebase Admin e check_revoked=True, resolve o perfil por firebase_identities e atualiza verified pela claim assinada email_verified. Cadastro/login/refresh/confirmação/recuperação locais e tokens de sessão locais só são aceitos com development=True. Nenhuma conta Firebase é mesclada automaticamente por e-mail. Veja FIREBASE.md para configuração e credenciais do servidor.

No cliente Firebase, sair usa signOut do SDK neste dispositivo, sem chamar a revogação global da API. A rota /auth/logout para identidades Firebase continua com seu comportamento de revogação global; não deve ser confundida com sair apenas deste dispositivo. Para sessões locais legadas, o cliente solicita revogação da sessão atual e limpa seus dados mesmo se a API estiver indisponível.

## Atualização do fluxo familiar e avatar

Consulte FIREBASE.md para as rotas /guardian/children e /me/avatar. O contrato público de perfil inclui avatar (ID de mídia ou null). O próprio usuário recebe needsNickname. approved de um menor é calculado por guardian_links e pela confirmação do responsável, sem confiar no campo legado ou em dados enviados pelo cliente. Todas as rotas sociais exigem ambas as confirmações, vínculo ativo e escolha do apelido. O nome interno da criança é retornado apenas ao responsável vinculado, como childName em /guardian/children; autores no feed usam o apelido público.

## Acompanhamento familiar

As rotas de histórico, categorias, imagens no contexto familiar e Vamos conversar? estão descritas em [ACOMPANHAMENTO_FAMILIAR.md](ACOMPANHAMENTO_FAMILIAR.md). POST /posts e /stories aceitam category: anime, games, sports, music, education, art ou other (padrão).

## Integridade e repetição de operações

Criações em `/posts`, `/stories`, `/media`, `/reports`, `/messages/:id` e discussões familiares aceitam `Idempotency-Key` (16–128 caracteres alfanuméricos, `_` ou `-`). A chave é vinculada ao usuário e ao conteúdo da operação. Durante 24 horas, repetir a mesma operação retorna o mesmo resultado; trocar o conteúdo mantendo a chave retorna 409. Recibo e dados são confirmados na mesma transação. O Flutter repete uma vez falhas de conexão nessas criações e preserva a chave em memória para tentativa manual após resposta perdida. Essa proteção não persiste após fechar o aplicativo.

Pedidos de contato expiram em sete dias. Aceitar não substitui o consentimento dos responsáveis. Bloquear ou desfazer a conexão invalida as autorizações anteriores; desbloquear exige novo pedido. Ao atualizar um banco antigo, conexões de menores sem consentimento registrado são removidas e devem ser solicitadas novamente.

`PATCH /me` preserva campos omitidos; somente um apelido enviado explicitamente conclui essa etapa. `DELETE /me` com senha incorreta ou autenticação antiga retorna 401 com `error.code=reauthentication_required`, sem encerrar a sessão do cliente. A exclusão remove os dados locais em transação e registra uma tarefa persistente para excluir a identidade Firebase. Falhas do provedor são repetidas pelo worker com espera progressiva; uma identidade em exclusão não pode recriar o perfil. Execute o worker do servidor para concluir essas tarefas.

A API exige `Content-Type: application/json` quando há corpo, rejeita propriedades JSON duplicadas, valores não finitos e origens fora da lista permitida. `X-Request-ID` correlaciona falhas internas sem registrar conteúdo, identificadores pessoais ou tokens. A manutenção preserva uploads não associados por 24 horas; recibos expirados e pedidos antigos são tratados pela rotina de manutenção.
