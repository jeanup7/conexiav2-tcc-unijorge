# Conexia — relatório de interface e segurança

Data: 26 de outubro de 2026. Projeto: Conexia, MVP acadêmico de Ciência da Computação / Unijorge.

Autores do projeto: Jean dos Santos Fonseca, Deivison Oliveira Costa e Matheus Zeferino Dias.

## 1. Escopo e resultado desta revisão

Esta etapa concluiu as quatro solicitações de interface — tema claro/escuro, Recortes, perfil e navegação inferior — e corrigiu lacunas concretas na autorização e no tratamento de denúncias. Acrescentou triagem humana por categoria, evidência textual delimitada, apoio familiar opcional e suspensão/reativação administrativa com histórico.

O código foi alterado no projeto local. Esta etapa não publicou uma versão na internet, não realizou push para o GitHub, não criou usuários nem redefiniu senhas. As credenciais externas do Firebase não foram incluídas na documentação. As alterações anteriores do projeto foram preservadas.

O relatório distingue recursos novos, mecanismos já existentes e pendências. O resultado permanece um MVP local: passar testes não equivale a uma auditoria independente nem a estar pronto para operar uma rede social pública para menores.

## 2. Arquitetura utilizada

- **Interface:** Flutter e Material 3, com fontes locais Lato, componentes compartilhados e cores semânticas.
- **Navegação:** Navigator para telas e modais; IndexedStack mantém o estado das abas. No aplicativo autenticado, abas são visitadas sob demanda e TickerMode desativa animações fora de foco.
- **Estado:** AppState/ChangeNotifier e AppScope para sessão; SocialRepository para dados sociais e notificações de atualização; PreviewStore para demonstração exclusivamente local.
- **API:** serviços Python, repositório SQLite, autenticação Firebase verificada no servidor e autenticação legada restrita ao desenvolvimento.
- **Dados:** tabelas de usuários, vínculos familiares, consentimentos de contato, publicações, mídias, mensagens, denúncias e auditoria. Fotografias são persistidas em BLOBs no SQLite; o cliente busca mídias por endpoints autenticados.

Não foi necessário trocar o gerenciador de estado, recriar o banco ou migrar o aplicativo para outra arquitetura.

## 3. Interface: problemas e correções

### 3.1 Tema claro e escuro reais

**Antes:** a preferência de preto e branco aplicava um filtro sobre a árvore de widgets e dessaturava fotografias.

**Agora:** MaterialApp recebe theme, darkTheme e ThemeMode. A preferência usa o armazenamento local seguro, com chave própria `conexia.darkMode`; a antiga preferência de dessaturação não ativa o novo modo automaticamente. Não existe ColorFiltered aplicado globalmente.

As cores derivam de ColorScheme e de ConexiaPalette: background, surface, text, muted, primary, line e superfícies auxiliares. Fundos, cartões, formulários, avisos, bolhas de conversa, indicadores e avatares vazios acompanham o tema. Fotografias mantêm suas cores. O visualizador de Recortes conserva fundo escuro para favorecer a leitura de mídia.

A troca de tema mantém a árvore de navegação e os rascunhos. A escrita da preferência é serializada para evitar que toques rápidos salvem um valor antigo. Se o armazenamento falhar, a aparência continua aplicada na sessão e a interface informa a falha de persistência.

A alternância fica no ícone **Aparência**, no cabeçalho da prévia e da área autenticada.

### 3.2 Recortes

A nomenclatura visível foi padronizada para **Recortes**, incluindo criação, visualização, avisos de expiração, administração e descrição do acompanhamento familiar. Os nomes internos StoryViewer, `/stories` e campos antigos da API foram mantidos para preservar compatibilidade técnica; não são rótulos exibidos às pessoas.

No visualizador:

- indicadores superiores finos, com identificação acessível de posição;
- controles anterior/próximo e fechamento;
- SafeArea protege o conteúdo dos elementos do sistema;
- legenda branca sobre degradê escuro;
- legenda longa pode rolar dentro de uma altura limitada pelo espaço real disponível;
- conteúdo expirado recebe mensagem própria;
- fotografias usam ajuste proporcional;
- transições respeitam a preferência por reduzir animações.

Os indicadores representam a posição entre Recortes. Não foi implementada reprodução automática por tempo. A validade de 24 horas permanece definida pelo servidor.

### 3.3 Perfil

O componente compartilhado ProfileHeading organiza avatar, apelido, privacidade, biografia e estatística de publicações. Números recebem maior peso tipográfico; rótulos usam peso regular.

A prévia calcula o total local. Para perfis reais, o contador representa publicações já carregadas; quando há outra página, exibe `+` e o rótulo “publicações carregadas”. Isso evita apresentar um total fictício. O contador é reiniciado ao trocar o perfil consultado.

O estado vazio do próprio perfil usa o componente FirstPublication, com ícone, texto orientador e CTA **Criar primeira publicação**, ligado ao editor. Perfis vazios de outras pessoas não oferecem criação em nome delas.

### 3.4 Navegação

A pílula Explorar e o seletor de destinos foram removidos. A barra inferior tem quatro destinos simétricos: **Feed, Pesquisa, Mensagens e Perfil**. Criar publicação passa a um FAB circular, separado e acima da barra.

A prévia não mantém mais uma aba de criação invisível. O editor abre como rota e retorna a publicação criada. O aplicativo autenticado continua usando a atualização do SocialRepository para refletir alterações.

No cabeçalho autenticado, família, privacidade e administração foram agrupadas no menu Conta e segurança para reduzir aperto em telas estreitas. Aparência e notificações continuam com atalhos próprios.

## 4. Referências de segurança e adaptação ao Conexia

Foram consultadas fontes públicas oficiais da Meta, em 26/10/2026:

1. [Instagram Teen Accounts](https://about.fb.com/news/2024/09/instagram-teen-accounts/): privacidade por padrão, proteção contra contatos indesejados e supervisão apropriada à idade.
2. [Configurações mais restritas de mensagens para adolescentes no Instagram e Facebook](https://about.fb.com/news/2024/01/introducing-stricter-message-settings-for-teens-on-instagram-and-facebook/): limitar contatos e exigir participação dos responsáveis em mudanças de proteção.
3. [Políticas de segurança da Meta](https://www.meta.com/safety/topics/safety-basics/policies/): proteção infantil e tratamento de assédio, ódio e exploração.

A adaptação abaixo é uma decisão de projeto do Conexia, não uma reprodução integral das políticas ou dos mecanismos internos dessas plataformas. Não há integração de moderação com a Meta nem certificação por ela.

| Princípio de referência | Aplicação no Conexia | Situação |
| --- | --- | --- |
| Privacidade de menores | Perfil privado obrigatório; acesso depende de vínculo e contato autorizado | Já existia; endurecido nesta revisão |
| Controle de contatos | Consentimento do responsável para cada menor envolvido; desconhecidos não iniciam chat | Já existente e coberto pela suíte |
| Denunciar e bloquear | Bloqueio rompe conexão; denúncia de conteúdo e mensagem específica | Denúncias ampliadas nesta revisão |
| Proteção contra abuso | Categorias claras e prioridades para revisão humana | Novo nesta revisão |
| Participação familiar | Pedido de apoio opcional com aviso genérico | Novo nesta revisão |
| Responsabilização | Remoção humana, suspensão e histórico de decisões | Ampliado nesta revisão |
| Conteúdo sensível e bem-estar | Classificação automática, limites de tempo e horário silencioso | Não implementados |

### 4.1 Privacidade que resiste a dados antigos

O endpoint de alteração de perfil já proibia tornar um menor público. Foi adicionada proteção na própria autorização de leitura: mesmo que um cadastro importado ou antigo contenha `private=0`, a idade continua exigindo contato aprovado. A representação pública também informa perfil privado para menores.

Isso protege perfil, feed e mídias que usam a autorização central, sem depender somente do valor enviado pelo aplicativo.

### 4.2 Denúncias autorizadas e categorizadas

Antes, o servidor aceitava um identificador arbitrário como alvo. Agora resolve o recurso e verifica a autorização:

- publicação ou comentário: a pessoa precisa poder acessar a publicação;
- mensagem: somente remetente ou destinatário podem relatar;
- perfil: precisa ser visível ou haver relação verificável de bloqueio feito pelo denunciante/histórico de mensagens;
- relato geral: continua disponível sem alvo específico;
- alvo inexistente ou conteúdo privado inacessível: retorna 404.

As categorias são bullying, contato indesejado, informação pessoal, conteúdo inadequado, ódio, ameaça, proteção infantil, golpe e outro. O servidor valida a categoria; não confia em prioridade enviada pelo cliente.

Ameaça e proteção infantil entram com prioridade 3. Outros riscos relevantes usam prioridade 2, e conteúdo inadequado/outro usam prioridade 1. A fila mostra pendentes primeiro e, depois, prioridade e antiguidade. Prioridade não significa culpa nem remoção automática.

Relatos pendentes do mesmo autor, alvo e categoria retornam o protocolo existente. O limite já existente de dez novas denúncias por hora por conta continua aplicado. Esse controle é em memória e ainda precisa ser distribuído/persistido para produção.

### 4.3 Evidência delimitada e confidencialidade

A tabela nova report_context guarda categoria, prioridade, tipo do alvo e uma cópia do texto específico relatado. Não copia a conversa inteira nem imagens. Essa evidência textual continua disponível para análise se o autor apagar a publicação ou mensagem. Denúncias históricas sem contexto novo continuam aparecendo com valores de compatibilidade.

O conteúdo da denúncia não é notificado ao acusado. A fila administrativa não apresenta a identidade do denunciante. A pessoa consulta apenas seus próprios relatos e exporta apenas seu próprio contexto. A evidência acompanha a denúncia e é excluída por cascata se a conta denunciante for excluída. Ainda falta estabelecer uma política operacional de retenção para denúncias mantidas por mais tempo.

No chat, pressionar uma mensagem abre **Denunciar esta mensagem**. O relato fica vinculado ao identificador daquela mensagem. Participantes ainda podem relatá-la após bloquear a conexão, sem reabrir o chat por API nem permitir acesso de terceiros.

### 4.4 Apoio familiar opcional

Para um menor, o formulário oferece **Pedir apoio ao meu responsável**. A opção começa desmarcada. Quando selecionada, o responsável ativo e não suspenso recebe somente um aviso genérico para conversar com acolhimento. A mensagem privada, o motivo e os detalhes do relato não são enviados nessa notificação.

O apoio opcional evita transformar todo relato em exposição automática de conversas. A supervisão familiar que já existe no projeto permanece separada dessa notificação.

### 4.5 Moderação de contas

A administração local ganhou **Suspender conta** e **Reativar conta**, com confirmação e motivo obrigatório de 3 a 300 caracteres. A API exige administrador adulto, verificado e ativo. Uma conta comum não consegue promover a si própria ou aplicar decisões administrativas.

O endpoint é `PATCH /admin/users/{id}`. O administrador não pode suspender a própria conta nem outra conta administrativa por esse fluxo; isso exige intervenção do operador do servidor.

A situação atual fica em account_status. A tabela nova account_moderation preserva cada decisão, o administrador, o alvo, o motivo e o horário. O usuário pode exportar seu histórico de decisões sem receber o identificador interno do moderador.

A suspensão é verificada no servidor em requisições existentes, inclusive com uma sessão já emitida. Não apaga a conta nem os dados. Consulta da própria conta, exportação, exclusão e recursos de proteção continuam permitidos. A interface atualiza permissões ao retornar ao app e periodicamente; não existe canal push para encerrar imediatamente uma tela aberta.

Na remoção de uma publicação/comentário, o autor recebe um aviso genérico e o denunciante recebe atualização do protocolo. A identidade de quem denunciou não é revelada. Remoção de mensagens e perfis não foi automatizada pela fila.

### 4.6 Regras acessíveis no aplicativo

Privacidade e segurança recebeu **Regras de convivência e proteção**, com orientações sobre respeito, dados pessoais, vínculos de menores, bloqueio, denúncia de mensagens e limites do atendimento do MVP. A interface não promete detecção automática de conteúdo nem atendimento contínuo.

## 5. Proteções já existentes que continuam em uso

Estas não foram recriadas nesta etapa:

- validação de token Firebase no servidor, incluindo revogação;
- confirmação dos e-mails do menor e do responsável, vínculo ativo e apelido antes do feed;
- autorização central de acesso a perfis, posts e mídias;
- contatos com aceitação do destinatário e consentimentos familiares exigidos;
- mensagens somente entre contatos aprovados e com a função habilitada;
- bloqueio bilateral de acesso e desconexão de contatos;
- senhas legadas com scrypt e tokens de sessão armazenados como hash;
- validação do conteúdo real de imagens, limites de tamanho/pixels e remoção de metadados EXIF/GPS;
- SQL parametrizado, transações e chaves estrangeiras;
- origem permitida, limites de requisição e respostas sem cache para dados privados;
- limpeza de sessão e rotas privadas ao sair ou perder permissão;
- exclusão de identidade Firebase com trabalho persistido para repetição em caso de falha.

## 6. Arquivos desta etapa

### Tema e componentes compartilhados

- lib/main.dart — ligação de MaterialApp à preferência global e aos dois temas.
- lib/theme/appearance.dart — preferência persistente de modo escuro e controle de aparência.
- lib/theme/app_theme.dart — temas, cores e FAB.
- lib/theme/design_tokens.dart — paleta semântica.
- lib/widgets/common.dart — cores e feedbacks compatíveis com tema.
- lib/widgets/design_system.dart — marca, cartões, avisos e carregamento.
- lib/widgets/social/profile_heading.dart — cabeçalho e CTA de primeiro post.
- lib/widgets/social/profile_avatar.dart — avatar vazio adaptável ao tema.
- lib/widgets/social/conexia_compass.dart — barra inferior compartilhada.
- lib/widgets/social/social_post_card.dart — superfícies e textos semânticos.
- lib/widgets/social/feed_skeleton.dart — cores de carregamento.
- lib/widgets/social/post_gallery.dart — indicadores adaptáveis ao tema.
- lib/widgets/social/story_avatar.dart — rótulos de Recortes.

### Telas

- lib/screens/inicio_screen.dart — navegação, FAB e menu de conta.
- lib/screens/login_screen.dart — adaptação de cores.
- lib/screens/painel_responsavel_screen.dart — adaptação de cores.
- lib/screens/perfil_infantil_screen.dart — cabeçalho e resumo de publicações.
- lib/screens/social/feed_preview_screen.dart — tema, quatro abas e editor por rota.
- lib/screens/social/feed_screen.dart — resumo de posts, estado vazio e visualizador de Recortes.
- lib/screens/social/user_profile_screen.dart — cabeçalho, contagem e estado vazio.
- lib/screens/social/composer_screen.dart — rótulos de Recortes.
- lib/screens/social/messages_screen.dart — bolhas adaptáveis e denúncia de mensagem.
- lib/screens/family_activity_screen.dart — terminologia de Recortes.
- lib/screens/denuncia_screen.dart — categorias, envio protegido e apoio opcional.
- lib/screens/admin_screen.dart — prioridade e moderação de contas.
- lib/screens/seguranca_screen.dart — regras de convivência.

### Servidor e dados

- backend/safety.py — autorização, deduplicação, categoria, evidência e apoio.
- backend/service.py — integração, privacidade de menores e exportação.
- backend/repository.py — criação aditiva de report_context e account_moderation, com índices.
- backend/administration.py — fila priorizada, suspensão/reativação e notificações.

### Validação

- backend/test_safety_policy.py — sete testes novos de regras de segurança.
- backend/test_administration.py — atualização da verificação das notificações de remoção.
- test/navigation_refresh_test.dart — navegação e preservação de rascunho ao trocar tema.
- test/premium_ui_test.dart — temas, capturas, Recortes, CTA e acessibilidade de layout.
- test/safety_ui_test.dart — categoria enviada e confirmação de suspensão.
- test/feed_preview_test.dart, test/audit_improvements_test.dart e test/stability_test.dart — atualização dos fluxos e rótulos alterados.

Outros arquivos que já estavam modificados no repositório antes desta revisão podem aparecer em git status. Eles não representam necessariamente alterações produzidas nesta etapa.

## 7. Verificação

| Verificação | Resultado |
| --- | --- |
| `python -m unittest discover -s backend` | 114 testes aprovados |
| `flutter test` | 58 testes aprovados |
| `flutter analyze` | Nenhum problema encontrado |
| `flutter build web --no-wasm-dry-run` | Compilação concluída em build/web |
| `git diff --check` | Sem erros de espaços/conflitos |

A compilação web emitiu um aviso não bloqueante sobre a fonte CupertinoIcons, sem impedir a geração. A interface atual utiliza Material/Lucide; a apresentação em iOS ainda deve ser verificada antes de uma entrega nessa plataforma. Os registros completos estão na subpasta [validacao](validacao/).

Foram inspecionadas capturas do feed claro, feed escuro, perfil vazio e Recortes com texto ampliado. Os testes de interface incluem largura de 320 pixels, ampliação de texto de 1,8 vez, retorno do editor, preservação de estado e API simulada. Os testes do servidor usam banco isolado em memória; não enviam denúncias reais nem alteram contas Firebase existentes.

As verificações não substituem testes manuais em aparelhos Android/iOS, auditoria de acessibilidade com usuários ou avaliação de carga. Não foi realizado teste de invasão independente nem teste de ponta a ponta contra uma conta Firebase real nesta etapa.

## 8. Como aplicar e testar localmente

Reinicie o back-end para carregar o código e criar as tabelas aditivas. Não exclua o arquivo SQLite. Faça uma cópia de segurança operacional antes de qualquer implantação; a inicialização não remove dados existentes para essas tabelas.

No PowerShell do projeto:

```powershell
cd C:\Users\Pc\Downloads\teste\teste_app
.\backend\start_firebase.cmd
```

Em outro terminal:

```powershell
cd C:\Users\Pc\Downloads\teste\teste_app
flutter run -d chrome --web-port 5300 --dart-define=API_URL=http://127.0.0.1:8080
```

Se já estiver rodando Flutter no terminal, use `R` para reiniciar o app. O back-end também precisa ser reiniciado separadamente.

Roteiro manual:

1. Alterne Aparência, navegue e confirme que as fotos conservam suas cores.
2. Abra um Recorte, avance, volte e teste uma legenda longa.
3. Abra um perfil vazio próprio e use Criar primeira publicação.
4. Navegue pelas quatro abas e publique pelo FAB.
5. Denuncie um conteúdo acessível; confira o protocolo em Minhas denúncias.
6. Pressione uma mensagem para relatar apenas aquela mensagem.
7. Em conta de menor, teste o pedido opcional de apoio ao responsável.
8. Na administração, confira a ordem da fila e suspenda uma conta de teste com motivo.
9. Na conta suspensa, confira bloqueio das operações sociais e disponibilidade de exportação/exclusão.
10. Reative a conta e confira o histórico exportado.

## 9. Pendências para uma implantação pública

| Prioridade | Pendência | Motivo |
| --- | --- | --- |
| Alta | Hospedagem com TLS, servidor apropriado, segredos protegidos e backups testados | O ponto de entrada atual é local e exige modo de desenvolvimento |
| Alta | Administração de produção, provisionamento de papéis e autenticação reforçada | A administração continua deliberadamente limitada ao modo local |
| Alta | Equipe/processo de revisão, prazos, encaminhamento de emergências e recurso contra decisões | A fila é técnica; não constitui atendimento contínuo |
| Alta | Avaliar provedor de moderação de mídia/texto e bloquear exposição antes de revisão quando necessário | Nenhuma detecção automática de nudez, violência ou exploração foi adicionada |
| Alta | Definir política de idade, comprovação de responsável, consentimento e retenção com responsáveis pelo produto | Data de nascimento e vínculo no banco não constituem comprovação independente |
| Alta | Retenção/eliminação de evidências e restauração de backup com regras de acesso | Evidências podem conter informação sensível e precisam de ciclo de vida operacional |
| Média | Limites de uso e notificações silenciosas | Referências de bem-estar digital não estão implementadas |
| Média | Rate limit compartilhado, observabilidade sem dados sensíveis e testes de carga | Contadores em memória e servidor local não atendem operação distribuída |
| Média | Testes reais de integração Firebase, Android/iOS e leitor de tela | A suíte desta etapa usa isolamento e simulação de API |
| Média | Separar escola/coordenador, autorização institucional e telas de tutor | O fluxo escolar anterior possui API, mas não um produto institucional completo |

O Conexia mantém proteção mais restrita para menores de 18 anos dentro do escopo do projeto. Isso não significa adotar automaticamente a elegibilidade etária do Instagram/Facebook nem comprovar adequação legal para crianças. As regras de um ambiente escolar precisam ser definidas e validadas pelo produto antes da implantação.

## 10. Evidências visuais

Feed claro: [abrir imagem](feed.png). Feed escuro: [abrir imagem](feed_dark.png).

Perfil no modo escuro: [abrir imagem](profile_dark.png). Recorte com fonte ampliada: [abrir imagem](recorte.png).

As capturas mostram dados fictícios da prévia e não expõem credenciais nem conversas de usuários reais.
