# Firebase Authentication — Conexia

Projeto configurado pelo FlutterFire: `conexiabeta2`. O aplicativo inicia Firebase e usa E-mail/senha no cadastro, login, recuperação e confirmação. A API REST/SQLite continua responsável por perfis, permissões e conteúdo social. Não há migração para Firestore.

## Console

Em Authentication > Método de login, habilite E-mail/senha. Em Templates, configure os textos dos e-mails. Se usar localhost como domínio de continuação/autenticação, confira Authentication > Configurações > Domínios autorizados e adicione localhost para desenvolvimento quando necessário. Os links padrão do Firebase são usados nesta integração, sem Dynamic Links.

## Credencial do backend

O login `firebase login` configura a CLI; ele não é a credencial da API Python. Em Configurações do projeto > Contas de serviço > Firebase Admin SDK, gere uma chave privada da conta de serviço. Guarde o JSON fora do repositório e informe apenas seu caminho em GOOGLE_APPLICATION_CREDENTIALS. Não envie o conteúdo para o chat nem para o GitHub. Em implantação futura, prefira credenciais fornecidas pela infraestrutura (Application Default Credentials), sem arquivo de chave distribuído.

No PowerShell da API, substitua o nome do JSON pelo arquivo baixado:

```powershell
cd C:\Users\Pc\Downloads\teste\teste_app
python -m pip install -r backend/requirements.txt
$env:CONEXIA_DEV="1"
$env:FIREBASE_PROJECT_ID="conexiabeta2"
$env:GOOGLE_APPLICATION_CREDENTIALS="C:\Users\Pc\Downloads\NOME-DO-ARQUIVO.json"
python backend/server.py
```

Em outro terminal:

```powershell
flutter pub get
flutter run -d chrome --web-port 5300 --dart-define=API_URL=http://127.0.0.1:8080
```

Encerre a execução Flutter antiga antes de iniciar, pois foram adicionados plugins. A API também precisa ser reiniciada com as variáveis acima. O requisito CONEXIA_DEV permanece: o servidor HTTP local e a verificação do responsável ainda não são infraestrutura de produção.

## Fluxo

1. Cadastro cria a identidade no Firebase e associa seu UID a um perfil local. A senha Firebase nunca é enviada à API Conexia.
2. Na tela de confirmação, toque em Enviar / reenviar confirmação. Erros de envio são exibidos; não há mensagem falsa de e-mail enviado.
3. Abra o link recebido e volte à tela para tocar em Já confirmei. O aplicativo recarrega o usuário e renova o ID token antes de consultar a API.
4. A API usa Firebase Admin para validar assinatura, projeto, validade e revogação do token. O campo verified vem da claim assinada email_verified, nunca do corpo enviado pelo aplicativo.
5. Menores continuam restritos até aprovação independente do responsável; o e-mail confirmado não concede aprovação.
6. Recuperação envia um link Firebase; a nova senha é definida na página hospedada pelo Firebase. Depois, volte ao login.

O SDK Firebase gerencia a persistência da sessão no dispositivo/navegador; isso substitui a política antiga de sessão web somente em memória para a autenticação Firebase. A prévia continua em memória e não chama a API.

## Contas anteriores

Contas locais existentes no SQLite não são automaticamente mescladas por e-mail. Use outro e-mail de teste para o novo fluxo Firebase até implementarmos uma migração com prova de titularidade. Cadastro interrompido depois da criação no Firebase pode ser retomado usando o mesmo e-mail e senha no formulário; o UID vinculado mantém idade e dados originais.

## API

`POST /auth/firebase`, com Bearer ID_TOKEN, recebe name, birth e guardianEmail (se menor) apenas ao primeiro vínculo. Retorna user no formato existente. Repetir a chamada não muda idade nem aprovações.

As outras rotas aceitam o ID token Firebase e resolvem o perfil pelo UID. Tokens locais e rotas locais anteriores permanecem para compatibilidade/testes. Logout revoga tokens Firebase da identidade; exclusão requer autenticação recente (até cinco minutos), exclui a identidade Firebase e remove o perfil local em cascata. Isso não implementa exclusão offline.

## Validação

Testes isolados usam um gateway de autenticação e um verificador de identidade simulados, sem criar usuários reais nem enviar e-mails. Testes reais de cadastro, recebimento e confirmação exigem o provedor E-mail/senha ativado, credencial Admin e acesso à caixa de e-mail do usuário.

Fontes oficiais:
- https://firebase.google.com/docs/flutter/setup
- https://firebase.google.com/docs/auth/flutter/manage-users
- https://firebase.google.com/docs/auth/admin/verify-id-tokens
- https://firebase.google.com/docs/admin/setup

## Atalho local configurado

A credencial de conexiabeta2 foi localizada em Downloads e o acesso de leitura ao Firebase Authentication foi confirmado. O JSON permaneceu fora do repositório. No terminal do VS Code, a partir da pasta do projeto, execute:

```powershell
.\backend\start_firebase.cmd
```

O atalho configura as variáveis apenas para o processo da API. Se o arquivo mudar de lugar, passe o caminho como argumento. O atalho contém apenas o nome/caminho do arquivo, sem chave privada. O recebimento real de confirmação ainda precisa ser testado por cadastro e abertura do link na caixa do usuário.

## Fluxo familiar e fotos de perfil

O cadastro principal é de uma pessoa adulta/responsável. Depois de confirmar seu e-mail, ela abre Minha família e cria o perfil do menor (nome para o painel privado, data de nascimento, e-mail próprio e senha). Uma instância secundária do Firebase Auth cria ou autentica o menor sem trocar a sessão do responsável. A senha do menor é enviada ao Firebase, nunca à API Conexia. A API valida os dois tokens e associa o UID do menor à conta autenticada do responsável, mediante autorização explícita.

O Firebase envia o segundo e-mail ao endereço do menor. Se o envio falhar depois do vínculo, o painel informa o erro e o menor pode entrar e reenviar a confirmação. Ao entrar com o próprio e-mail e confirmar o link, o menor escolhe o apelido público. O nome informado pelo responsável fica em guardian_links.child_name e só aparece na consulta autenticada do painel desse responsável.

A API só libera recursos sociais quando o e-mail do menor está confirmado, o responsável adulto confirmou seu e-mail, o vínculo está ativo e o apelido foi escolhido. O campo legado users.approved não concede acesso a menores: a aprovação é calculada pelo vínculo persistido. O responsável pode pausar/reativar apenas os próprios vínculos; exclusão da conta do responsável remove o vínculo e bloqueia o acesso do menor até nova vinculação.

Em Perfil, o usuário adiciona, troca ou remove sua foto. O arquivo é armazenado como BLOB em media.data no SQLite; profile_media aponta para a foto atual. Fotos de postagens também permanecem como BLOB no mesmo banco. A manutenção preserva fotos de perfil referenciadas e a troca remove a anterior quando ela não estiver usada em postagem. Outros usuários só leem a foto se o perfil for visível, respeitando privacidade e bloqueios.

Esse vínculo confirma o controle dos e-mails e a autorização de uma conta autenticada, com idade declarada; não verifica documentalmente parentesco ou idade. Uma integração adicional será necessária se o produto exigir essa comprovação.

Rotas:
- GET /guardian/children: perfis vinculados do responsável verificado.
- POST /guardian/children: childToken, name, birth, consent=true.
- PATCH /guardian/children/:id: state=active ou paused, apenas responsável vinculado.
- GET /guardian/status: situação do próprio vínculo e confirmações.
- POST /me/avatar: media (ID próprio).
- DELETE /me/avatar: remove foto atual.

POST /auth/firebase rejeita novo cadastro direto de menor. Identidades de menores já existentes podem ser vinculadas pelo responsável correspondente, mediante autenticação na conta do menor; não há mesclagem de contas locais sem prova de titularidade. Replicar um vínculo não muda nascimento nem autoriza outro responsável.

A aprovação familiar também confere no Firebase Admin se o e-mail do responsável continua confirmado e a identidade não foi desativada. Essa consulta é reaproveitada apenas dentro da mesma requisição; falhas do provedor bloqueiam a operação com erro, sem liberar acesso.
