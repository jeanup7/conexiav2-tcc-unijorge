# Acompanhamento familiar

O responsável acessa Minha família > Acompanhar feed. O menor acessa o aviso no feed ou Meu responsável > O que meu responsável vê. Ambos consultam o mesmo resumo, histórico e marcações para conversa. As consultas exigem o vínculo atual; outro adulto não pode consultar o histórico nem as imagens.

## Registro e limites

Apenas publicações do feed real de um menor vinculado são registradas. A prévia, stories e mensagens privadas não são acompanhados. O aplicativo registra quando pelo menos metade do cartão permanece visível por 2 segundos contínuos, com a tela ativa e em primeiro plano. Abrir outra tela ou sair do aplicativo reinicia essa contagem. A API valida autorização e tempo informado, mas não consegue comprovar atenção ou leitura; não é uma ferramenta de auditoria contra clientes adulterados. Falhas de conexão podem deixar lacunas no histórico.

Há um registro por menor, publicação e dia UTC. Repetições atualizam o último horário. O resumo mostra os últimos 7 ou 30 dias; o histórico mostra os 50 registros mais recentes do período. Os registros são persistidos em SQLite e removidos após 30 dias durante a consulta ou manutenção (`python backend/maintenance.py`, com a API parada). O dispositivo pode mostrar horários locais.

O autor seleciona a categoria ao criar a publicação. Publicações antigas aparecem como Outros. Não há classificação automática, diagnóstico ou inferência sobre o menor.

## Conteúdo e conversas

O histórico referencia a publicação atual, sem guardar cópias de fotos ou legendas. Excluir a publicação, bloquear o menor ou mudar permissões impede a consulta do conteúdo. Categorias e horários continuam até o fim da retenção. A rota de imagens do acompanhamento exige uma visualização recente ou uma marcação para conversar e a visibilidade atual para o menor; não dá ao responsável acesso geral ao perfil do autor.

O menor pode marcar um post visível com Vamos conversar?. O responsável pode marcar um post compartilhado no histórico ou já marcado pelo menor. Marcações abertas são deduplicadas. Ambos podem marcar Conversamos ou reabrir. Há uma notificação dentro do app para o outro perfil, sem envio externo nem compartilhamento de mensagens privadas. As marcações não expiram com o histórico; mostram as 50 mais recentes e são removidas junto com as contas. O período de 7/30 dias não filtra conversas.

## API

- POST /posts/:id/view — {visibleMs: 2000}
- GET /family/activity?days=7 — transparência para o menor
- GET /guardian/children/:child/activity?days=7 — painel do responsável
- POST /family/discussions — {post: id}, pelo menor
- POST /guardian/children/:child/discussions — {post: id}, pelo responsável
- PATCH /family/discussions/:id — {state: open|resolved}, pelos dois
- GET /family/activity/posts/:post/media/:media — imagem no contexto do menor
- GET /guardian/children/:child/activity/posts/:post/media/:media — imagem no contexto familiar

As fotos continuam como BLOBs na tabela media, conforme o armazenamento existente. O banco recebe as novas tabelas com CREATE TABLE IF NOT EXISTS, sem recriar as contas.
