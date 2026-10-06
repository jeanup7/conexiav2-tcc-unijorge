# API REST — Conexia Segura

Base local: `http://127.0.0.1:8080`. JSON UTF-8. Rotas privadas exigem `Authorization: Bearer ACCESS_TOKEN`. Não enviar tokens em query strings. Respostas de sucesso retornam HTTP 200, inclusive criação. Erros: `{"error":{"message":"mensagem legível"}}`. Status 400 validação, 401 sessão, 403 autorização/conta restrita, 404 recurso invisível/inexistente, 409 conflito de cadastro, 413 corpo excessivo, 429 limite, 500 falha interna.

## Autenticação

| Método / rota | Entrada | Resposta |
|---|---|---|
| GET /health | — | status, storage, development |
| POST /auth/register | name (1–60), email, password (12–128), birth (`AAAA-MM-DD`); guardianEmail para menores | message; developmentToken somente no modo local |
| POST /auth/verify | token | message; token de uso único, validade de 1 hora |
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
| GET /contacts | — | items: id, name, approved |
| POST /contacts | target | pedido pendente; nunca aprovação automática |
| GET /contacts/requests | — | pedidos recebidos |
| POST /contacts/approve | target (remetente do pedido) | adultos aprovam pedido recebido; menores dependem do responsável |
| GET /posts?cursor=timestamp&limit=15 | cursor exclusivo; limite 1–30 | items e nextCursor |
| POST /posts | text (1–2000), media opcional | id |
| PATCH /posts/:id | text | somente autor |
| DELETE /posts/:id | — | somente autor; remove comentários e curtidas |
| POST /posts/:id/like | — | alterna curtida; recurso precisa ser visível |
| GET /posts/:id/comments | — | items: id, name, text; exclui autores bloqueados |
| POST /posts/:id/comments | text (1–500) | id |
| GET /stories | paginação como feed | somente stories visíveis e não expirados |
| POST /stories | text, media opcional | id; expira em 24 horas |
| POST /media | mime e data (base64) | id; JPEG/PNG/WebP, até 5 MB, verifica assinatura |
| GET /media/:id | — | mime e data (base64); autor ou publicação visível vinculada |
| GET /conversations | — | perfis das conversas não bloqueadas |
| GET /messages/:perfil | — | items: id, sender, recipient, text, created, read; exige contato aprovado; marca leitura |
| POST /messages/:perfil | text (1–1000) | id, status=sent; ambos devem permitir mensagens |

Publicação: id, user, text, media, story, created, expires, author, likes, liked. Datas de eventos são epoch em segundos. O cursor é `created` do último item e deve ser enviado apenas quando nextCursor não for nulo. Perfis privados só podem ser vistos pelo próprio autor ou contatos aprovados; bloqueios prevalecem. Stories usam as mesmas regras. Compartilhar o identificador não concede acesso ao conteúdo.

Mensagens usam polling a cada 8 segundos no Flutter, apenas com a conversa ativa. Não existe confirmação de entrega ao dispositivo, somente envio persistido e leitura. Vídeos, mensagens com imagens, WebSocket, busca textual de posts e push não possuem endpoints nesta versão.

## Troca de banco e implantação

`Repository` (`backend/repository.py`) concentra a conexão, esquema e execução parametrizada. `Service` contém regras e não acessa um arquivo de banco diretamente. Migrar para PostgreSQL exige novo adapter, migrações e adaptação das operações SQL específicas do SQLite; não exige refazer telas ou contratos HTTP. Os serviços ainda usam SQL e não constituem um ORM completamente independente do banco.

O servidor `http.server` é de desenvolvimento. Para implantação: framework/servidor apropriado, TLS, limites no gateway e por conta, transações e migrations, pool de conexões, email delivery, provedores validados, autenticação administrativa, processamento/armazenamento de mídia, testes de carga e observabilidade sem dados sensíveis. `CONEXIA_DEV` precisa continuar restrito a ambiente local.
