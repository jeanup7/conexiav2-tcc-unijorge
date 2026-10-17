# Conexia Segura

**Documento consolidado do produto:** [MVP Conexia - proposta, fluxos, arquitetura e roadmap](docs/mvp/MVP_CONEXIA.md). Versão 2.0, atualizada em 16/10/2026. [Pasta de documentação e PDF acadêmico](docs/mvp/README.md).

Interface Flutter/Material 3, Firebase Authentication, API REST Python e persistência SQLite de conteúdo e imagens. O projeto contém prévia visual em memória e uma carga sintética persistente para QA, com contas de demonstração separadas dos perfis sem login.

**Estado: MVP funcional em desenvolvimento local para web.** Revisão de 16/10/2026: 101 testes Python e 49 Flutter aprovados, análise estática sem problemas. Build web verificado em 15/10/2026. Inclui jornada familiar, consentimento de contatos, acompanhamento transparente, normalização de mídia e administração autenticada local. Implantação pública, QA móvel e confirmação ponta a ponta em dois e-mails reais permanecem pendentes. Seções históricas abaixo podem descrever etapas anteriores; o documento do MVP consolida o estado atual.

**Correções da auditoria:** consulte [primeiro lote de melhorias](docs/MELHORIAS_LOTE_1_2026-10-08.md) para alterações, testes e limites. Reinicie API e Flutter juntos para usar os novos contratos. Novos contatos envolvendo menores ficam pendentes até existir consentimento pelo responsável; contatos previamente aprovados ainda precisam de revisão.

## Execução local

Na pasta `C:\Users\Pc\Downloads\teste\teste_app`:

```powershell
python -m pip install -r backend/requirements.txt
.\backend\start_firebase.cmd
```

O iniciador configura o Firebase Admin usando a credencial privada fora do projeto. O login da CLI Firebase não substitui essa configuração. Caso a credencial esteja em outro local, passe o caminho como argumento ao `start_firebase.cmd`.

Em outro terminal, após resolver o bloqueio do SDK Flutter pelo administrador do Windows:

```powershell
flutter pub get
dart format lib test
flutter analyze
flutter test
flutter run -d chrome --web-port 5300 --dart-define=API_URL=http://127.0.0.1:8080
```

A API escuta apenas `127.0.0.1:8080`. Não altere para exposição pública. CORS permite apenas `http://localhost:5300` e `http://127.0.0.1:5300`, configuráveis em `ALLOWED_ORIGINS` (origens exatas separadas por vírgula). A configuração `API_URL` não contém segredo. O cliente rejeita HTTP externo.

Para validar o servidor:

```powershell
python -m unittest discover -s backend -v
```

SQLite é criado automaticamente em `backend/conexia.sqlite3`, excluído do Git. `DATABASE_PATH` permite mudar o arquivo no servidor. Use armazenamento criptografado, permissões de sistema operacional e backup controlado em um ambiente real. Nenhuma senha é persistida em texto; a autenticação usa scrypt com salt independente, tokens opacos aleatórios e somente hashes de tokens no banco.

## Testar sem dados fictícios

1. Crie uma conta adulta real de teste usando e-mail controlado por você e senha com 12 a 128 caracteres.
2. Na confirmação, use o código explicitamente identificado como de desenvolvimento. Neste modo não existe envio de e-mail, e o código não prova titularidade real do endereço.
3. Entre e publique texto ou até 10 fotos por postagem. Verifique edição, exclusão, curtida, comentários e stories de 24 horas.
4. Para testar duas contas adultas: uma pode permitir perfil público nas preferências; a outra pesquisa seu apelido e solicita contato. A primeira aprova em Privacidade > Pedidos de contato. Ambas precisam ativar mensagens de contatos aprovados.
5. Teste denúncia e bloqueio. O bloqueio é aplicado pela API nas duas direções.
6. Contas de menores ficam restritas até existir verificação independente do responsável. Não há atalho no aplicativo para conceder aprovação. Não use dados de uma criança real para testes.

Não há detecção facial nem câmera implementadas. A seleção de fotos é voluntária, pela galeria, para conteúdo social. Web mantém sessão apenas na memória; no dispositivo, o refresh token usa armazenamento seguro nativo. Recarregar a página web exige novo login.

## Operação local

Denúncias são persistidas, mas atendimento depende de operadores reais. No host protegido do backend:

```powershell
python backend/moderate.py list
python backend/moderate.py dismiss --report ID
python backend/moderate.py remove --report ID
```

A remoção aplica-se a alvos de publicação/comentário. Denúncias sobre pessoas/conversas exigem investigação operacional; não há análise automática. Esta ferramenta depende de acesso ao host/banco e não é um painel administrativo de produção.

Com a API parada, execute a manutenção para remover stories expirados e mídias órfãs:

```powershell
python backend/maintenance.py
```

A API já impede leitura após a expiração. A exclusão física depende desta manutenção. Não execute durante uploads, pois imagens ainda não associadas a publicações são consideradas órfãs. A política local de retenção de auditoria de 30 dias é uma configuração técnica inicial que precisa de validação.

## Documentação

- `docs/DIAGNOSTICO_E_ETAPAS.md`: diagnóstico, alterações por etapa e evidências.
- `docs/API.md`: contratos de requisição/resposta e permissões.
- `docs/SEGURANCA_E_PRIVACIDADE.md`: biometria, proteção de menores, avaliação jurídica e pendências.

Pendências: validar Android/iOS, entrega de e-mail, verificação de idade e responsável, painel autenticado do responsável, vídeos, mensagens com imagens, WebSocket/push, foto de perfil, pesquisa de conteúdo, pipeline de mídia sem metadados, operação de moderação e infraestrutura de produção. Essas funcionalidades não foram substituídas por confirmações falsas de sucesso.

## Prévia visual local

Em builds debug no localhost, o botão **Ver prévia do feed** aparece no login e na tela de verificações pendentes. A prévia reutiliza a tela do feed com pessoas/posts fictícios, curtidas, comentários, stories e publicações de texto/fotos em memória. Não consulta nem altera o backend e não modifica a aprovação da conta. Dados da prévia são descartados ao sair. Esse acesso visual não está disponível no build release.

Após mudar o código com `flutter run` ativo, use `R` no terminal para hot restart e clique em **Ver prévia do feed**. `test/feed_preview_test.dart` verifica acesso sem conta e ausência de chamadas à API; agora executado com sucesso no ambiente local.

### Feed com fotos — atualização visual

As quatro imagens fornecidas foram copiadas sem edição para `assets/feed/` e registradas em `pubspec.yaml`. A prévia agora exibe quatro posts e stories com avatares das imagens, legenda, curtidas, comentários e botão de salvar nesta sessão. O componente compartilhado `SocialPostCard` também moderniza o feed conectado à API. Duplo toque nas fotos da prévia permite curtir; salvar é apenas em memória e está identificado na interface. Stories mostram as imagens em tela escura.

Novos módulos: `models/preview_content.dart`, `widgets/social/story_avatar.dart` e `widgets/social/social_post_card.dart`. Nenhuma nova dependência. Teste existente da prévia ajustado às quatro postagens. `git diff --check` e checagem textual de delimitadores passaram; a limitação anterior do SDK foi resolvida. `flutter analyze` agora passa sem problemas.

Por haver assets novos, encerre `flutter run` com `q`, execute `flutter pub get` e inicie novamente com `flutter run -d chrome --web-port 5300 --dart-define=API_URL=http://127.0.0.1:8080`.

### Navegação, perfis e carrosséis

A prévia possui abas Feed, Pesquisa, Criar, Mensagens e Perfil. A pesquisa filtra os perfis fictícios; tocar no avatar/nome de uma postagem abre o perfil e sua grade de publicações. A aba Perfil reúne as próprias postagens da sessão. Mensagens exibe a informação de que conversas reais precisam do aplicativo autenticado.

Criar aceita até 10 fotos da galeria ou os assets de demonstração. Carrosséis têm deslize, setas, contador e indicadores; duplo toque curte a postagem. Publicações, curtidas e comentários são compartilhados entre as telas da prévia e descartados ao sair. Os posts de Luffy e Peter já incluem duas fotos para experimentar.

O feed conectado também aceita galerias: a API recebe `mediaItems`, mantém a ordem em `post_media` e preserva leitura de posts antigos com `media`. Reinicie a API para carregar o esquema adicional sem apagar o banco. No Flutter ativo, use `R` para hot restart e entre novamente na prévia.

Validação desta atualização: análise Flutter sem problemas, testes de navegação/perfil/carrossel e suíte Python incluindo ordem, propriedade, privacidade e manutenção de imagens.

## Firebase Authentication

A autenticação do aplicativo agora usa o projeto `conexiabeta2` configurado pelo FlutterFire. Cadastro/login, link de confirmação e recuperação são integrados ao Firebase; a API segue com SQLite para dados sociais. Execute a API com FIREBASE_PROJECT_ID e GOOGLE_APPLICATION_CREDENTIALS conforme `docs/FIREBASE.md`. O login da CLI não substitui a credencial Admin. Contas locais antigas não são vinculadas automaticamente por e-mail. O recebimento real de e-mail depende da configuração do console e precisa de teste com uma caixa controlada pelo usuário.

## Cadastro do responsável, vínculo e perfil do menor

1. Cadastre o responsável e confirme seu e-mail.
2. Entre em Minha família (ícone de família) e crie/vincule o perfil do menor com e-mail próprio.
3. O menor recebe a confirmação, entra com seu próprio e-mail e senha e toca em Já confirmei.
4. Ele escolhe o apelido e entra no feed. Em Perfil pode adicionar sua foto, salva como BLOB no SQLite junto às fotos das postagens.
5. O painel do responsável mostra pendências e permite pausar/reativar o acesso dos próprios perfis vinculados.

Reinicie a API com backend/start_firebase.cmd para criar as tabelas adicionais sem apagar dados. Faça hot restart no Flutter. As confirmações de e-mail são geridas pelo Firebase; os vínculos, permissões, nomes/apelidos e imagens persistem no SQLite. Detalhes e limites do vínculo estão em docs/FIREBASE.md. Testes atuais: 39 Python e 13 Flutter aprovados; análise sem problemas. A confirmação em duas caixas reais exige teste manual.

Acompanhamento do feed por categorias, histórico e conversas: [fluxo e limites](docs/ACOMPANHAMENTO_FAMILIAR.md).
