# Conexia Segura

Evolução do projeto Flutter existente: interface Material 3, API REST local e persistência SQLite real, sem contas ou publicações pré-carregadas. O repositório mantém os projetos nativos existentes e os nomes das sete rotas originais.

**Estado: desenvolvimento.** O usuário resolveu as dependências no terminal local e executou a prévia no Chrome, conforme capturas compartilhadas. O lockfile foi atualizado pelo Flutter. Análise e testes Flutter completos ainda não foram confirmados; o ambiente do agente falha com `resolved_executable_name`. Os 20 testes de backend passaram. Não publicar para menores antes de concluir as integrações e validações descritas abaixo.

## Execução local

Na pasta `C:\Users\Pc\Downloads\teste\teste_app`:

```powershell
$env:CONEXIA_DEV='1'
python backend/server.py
```

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
3. Entre e publique texto ou uma foto. Verifique edição, exclusão, curtida, comentários e stories de 24 horas.
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

Pendências: liberar e validar Flutter, resolver/pinar pacotes no lockfile, entrega de e-mail, verificação de idade e responsável, painel autenticado do responsável, vídeos, mensagens com imagens, WebSocket/push, foto de perfil, pesquisa de conteúdo, pipeline de mídia sem metadados, operação de moderação e infraestrutura de produção. Essas funcionalidades não foram substituídas por confirmações falsas de sucesso.

## Prévia visual local

Em builds debug no localhost, o botão **Ver prévia do feed** aparece no login e na tela de verificações pendentes. A prévia reutiliza a tela do feed com pessoas/posts fictícios, curtidas, comentários, stories e publicações de texto em memória. Não consulta nem altera o backend e não modifica a aprovação da conta. Dados da prévia são descartados ao sair. Esse acesso visual não está disponível no build release.

Após mudar o código com `flutter run` ativo, use `R` no terminal para hot restart e clique em **Ver prévia do feed**. `test/feed_preview_test.dart` verifica acesso sem conta e ausência de chamadas à API; sua execução ainda depende do terminal local, pois o ambiente do agente falha com `resolved_executable_name`.

### Feed com fotos — atualização visual

As quatro imagens fornecidas foram copiadas sem edição para `assets/feed/` e registradas em `pubspec.yaml`. A prévia agora exibe quatro posts e stories com avatares das imagens, legenda, curtidas, comentários e botão de salvar nesta sessão. O componente compartilhado `SocialPostCard` também moderniza o feed conectado à API. Duplo toque nas fotos da prévia permite curtir; salvar é apenas em memória e está identificado na interface. Stories mostram as imagens em tela escura.

Novos módulos: `models/preview_content.dart`, `widgets/social/story_avatar.dart` e `widgets/social/social_post_card.dart`. Nenhuma nova dependência. Teste existente da prévia ajustado às quatro postagens. `git diff --check` e checagem textual de delimitadores passaram; `flutter analyze` continua falhando no ambiente do agente com `resolved_executable_name`. Renderização final ainda requer teste no terminal local do usuário.

Por haver assets novos, encerre `flutter run` com `q`, execute `flutter pub get` e inicie novamente com `flutter run -d chrome --web-port 5300 --dart-define=API_URL=http://127.0.0.1:8080`.
