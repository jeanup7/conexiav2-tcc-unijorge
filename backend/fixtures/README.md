# Dados fictícios de QA

Execute no PowerShell, na raiz do aplicativo:

```powershell
$env:CONEXIA_DEV = '1'
python backend/seed_data.py --connect-demo-accounts
```

O padrão gera 120 perfis, 2.400 posts, 360 stories e 18.000 mensagens. O resumo e o catálogo de mídia ficam em `backend/fixtures/seed_manifest.json`. Ajuste o volume com `--users`, `--posts`, `--stories` e `--messages`. Use um banco separado com `--database CAMINHO` para ensaios isolados.

O script cria um backup SQLite consistente em `Documents/Conexia-backups` antes de alterar um banco existente. Execute preferencialmente com a API parada. Repetir o comando preserva a carga já registrada. Para recriar somente os registros pertencentes ao namespace do seed, acrescente `--reset`. Contas reais e os quatro logins de demonstração são preservados.

Os perfis gerados não têm senha conhecida nem identidade no Firebase. Para entrar, utilize os logins de demonstração existentes; `--connect-demo-accounts` conecta esses perfis à rede fictícia. O administrador existente pode consultar métricas e filtrar contas na aplicação.

O modelo usa contatos recíprocos aprovados, pedidos pendentes, bloqueios e consentimentos sintéticos dos responsáveis, em vez de seguidores unilaterais. Contas denunciadas e suspensas são situações independentes. Suspensão bloqueia os recursos sociais. Há menores sem verificações completas e vínculos familiares pausados para testar restrições.

As sete imagens fornecidas estão em `seed_media`, com origem descrita no catálogo. Elas aparecem nos primeiros avatares e posts. Os demais avatares e as imagens adicionais são placeholders locais variados. A mídia é normalizada, armazenada como BLOB no SQLite e servida pela rota autenticada `/media/{id}`. URLs genéricas no manifesto são referências de placeholder; o seed não depende de downloads externos.

Posts incluem galerias e categorias; stories incluem itens ativos e expirados. Conversas têm participantes autorizados, alternância de remetentes, horários variados e mensagens lidas/não lidas. Métricas familiares usam visualizações e propostas de conversa; não expõem mensagens privadas ao responsável.

Validação automatizada:

```powershell
python -m unittest discover -s backend -p "test_*.py"
flutter test
flutter analyze
```
