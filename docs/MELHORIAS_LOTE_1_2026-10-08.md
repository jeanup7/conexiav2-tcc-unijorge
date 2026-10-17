# Conexia — primeiro lote de correções da auditoria

Data: 08/10/2026. Referência: [auditoria de arquitetura e UX](RELATORIO_ARQUITETURA_UX_E_PLANO_2026-10-08.md).

Este lote corrige regressões prioritárias do aplicativo e da API. Não encerra os 24 achados da auditoria nem representa autorização para implantação pública. As alterações anteriores do projeto foram preservadas; não houve publicação no GitHub ou exclusão do banco existente.

## Alterações implementadas

- **Contatos:** a API bloqueia aprovação direta quando qualquer participante é menor, inclusive quando o destinatário é adulto. A tela identifica esses pedidos e desabilita a aprovação. Pedidos repetidos não duplicam notificações; criação e aprovação adulta bilateral usam transações.
- **Paginação:** feed, stories e histórico de mensagens passam a usar cursor composto por horário e ID. Publicações com horários iguais não desaparecem entre páginas. Entrada numérica legada continua aceita; as respostas novas usam strings opacas.
- **Feed e busca:** o servidor busca publicações em lotes, agrega imagens, categorias e curtidas e mantém as regras de visibilidade. A busca aplica o limite aos perfis autorizados, evitando uma página vazia causada por candidatos privados anteriores.
- **Navegação e curtidas:** as abas visitadas preservam estado e rolagem; abas ainda não abertas não carregam suas telas. Curtir atualiza apenas a publicação, sem recarregar feed e stories. A API aceita o estado desejado de curtida, tornando repetições idempotentes. Respostas antigas de carregamentos concorrentes são descartadas e páginas são deduplicadas.
- **Chat:** abre as 200 mensagens mais recentes, permite carregar histórico anterior e mescla mensagens por ID. Buscar mensagens não altera leitura. A confirmação explícita aceita somente IDs recebidos do interlocutor; listas inválidas são rejeitadas sem alteração parcial. O cliente confirma após exposição visível e suspende polling fora da conversa ou em segundo plano. Envio pendente não acessa controlador descartado ao fechar a tela.
- **Acompanhamento:** stories deixam de ser aceitos como visualizações de publicações do feed. O temporizador de exposição é encerrado após registro bem-sucedido e não registra abas ocultas.
- **Sessão e imagens:** sair de uma sessão Firebase no dispositivo usa o SDK, sem revogar os demais dispositivos pela API. Sessões locais são limpas mesmo se a revogação remota falhar. Imagens privadas atualizam ao mudar a referência; a configuração de ajuste da galeria chega ao componente de imagem.
- **Limites e índices:** cada janela de limitação conserva sua própria expiração. Foram adicionados índices de consulta para feed, autor, mensagens, pedidos, bloqueios e curtidas.

## Evidências de verificação

- `python -m unittest discover -s backend -v`: **60 testes aprovados**, incluindo 14 regressões novas. O primeiro conjunto foi executado antes das correções e reproduziu as falhas.
- `flutter test --reporter expanded`: **22 testes aprovados**, incluindo cinco novos testes de cursor, abas/curtidas, histórico/envio, leitura visível e logout Firebase local.
- `flutter analyze`: **nenhum problema encontrado**.
- `git diff --check`: sem erros de espaços ou marcadores de conflito; somente avisos de normalização de finais de linha do Windows.
- `flutter build web --debug --dart-define=API_URL=http://127.0.0.1:8080`: **compilação concluída**, saída em `build/web`.

No cenário isolado da auditoria — SQLite em memória, 5.000 publicações de um autor adulto público, página de 15 itens e sem Firebase/rede — a consulta caiu de **10.092 para 7 comandos SQL**. Esse resultado verifica o custo de consultas naquele cenário; não mede latência real, consumo de memória do navegador ou desempenho em produção.

Os testes usam bancos temporários e clientes simulados. Não substituem testes com as duas caixas de e-mail reais, dispositivos Android/iOS ou carga concorrente.

### Relação com os achados

| Achado | Situação neste lote |
|---|---|
| A01 | Atalho de aprovação bloqueado; consentimento familiar completo e revisão de contatos legados pendentes. |
| A02, A03, A13, A14 | Regressões descritas corrigidas e cobertas por testes. |
| A04 | Consulta paginada em lotes e índices implementados; medição isolada repetida. |
| A06 | Expiração por janela corrigida; limites por conta e múltiplas instâncias pendentes. |
| A09 | Abas visitadas preservadas; consistência social compartilhada ainda pendente. |
| A10 | Curtidas locais, deduplicação e descarte de respostas antigas do feed implementados; carregamento independente de stories pendente. |
| A12 | Saída Firebase local e limpeza após erro de API implementadas; falhas do SDK ainda exigem tratamento. |
| A21, A22, A23 | Melhorias parciais em timers, imagens e callbacks do chat; validação completa pendente. |
| Demais achados | Permanecem no plano de ação original. |

## Limites e próximas etapas

1. **Consentimento de contatos pelo responsável:** ainda precisa de fluxo completo, persistência de consentimentos e revogação. Novos pedidos envolvendo menores permanecem pendentes. Contatos de menores aprovados anteriormente não foram migrados ou revogados neste lote; é necessário revisar sua validade antes de uso real. A aprovação do vínculo familiar da conta e a aprovação de contatos são regras distintas.
2. **Sessão e estado:** completar observação da identidade Firebase, cancelamento por troca de sessão, sincronização entre telas e tratamento de falhas de signOut. O estado social ainda não é um repositório compartilhado com cache; preservar abas não resolve toda a consistência.
3. **Mídia:** implementar decodificação e reprocessamento no servidor, remoção de metadados, limites de dimensões e cache do cliente. As fotos continuam armazenadas em SQLite e transportadas em JSON/base64.
4. **Servidor:** substituir o bloqueio global e as chamadas externas sob esse bloqueio, validar limites por conta e concorrência, adotar migrações versionadas e infraestrutura adequada. A correção de janelas não torna os limites em memória apropriados a múltiplas instâncias.
5. **Direitos e operação:** completar exportação, reconciliação Firebase/SQLite, moderação operacional e tratamento de estados parciais. A falha de stories ainda pode afetar o carregamento inicial do feed.
6. **Produto e UX:** validar em aparelhos reais, histórico longo com alturas variadas, acessibilidade e jornadas familiares. Escolas e tutores continuam sendo expansão planejada, sem implementação neste lote.

## Como aplicar localmente

Reinicie a API para carregar as novas regras e criar os índices de forma aditiva. Não apague o SQLite. Reinicie também o Flutter (`R` no terminal de `flutter run`, ou encerre e execute novamente), pois os contratos de cursor e confirmação de leitura mudaram.

Na pasta do aplicativo, mantendo a configuração Firebase já existente no ambiente do servidor:

```powershell
$env:CONEXIA_DEV='1'
python backend/server.py
```

Em outro terminal:

```powershell
flutter run -d chrome --web-port 5300 --dart-define=API_URL=http://127.0.0.1:8080
```

Contratos atualizados: [API.md](API.md). A auditoria original permanece como registro histórico; este arquivo registra o que foi efetivamente corrigido e o que continua pendente.
