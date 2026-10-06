# Segurança, privacidade e proteção de menores

## Estado e limites

Esta versão é uma base de desenvolvimento local. Não é certificada juridicamente e não está pronta para publicação para crianças. O servidor recusa inicialização sem `CONEXIA_DEV=1`; não existe modo de produção com entrega de e-mail ou responsável verificado. A idade é declarada pelo usuário e **não constitui aferição de idade**. A conta declarada adulta pode usar os recursos no ambiente local; isso não é uma barreira adequada para lançamento público.

A política implementada mantém perfis de menores privados e bloqueia recursos sociais enquanto a confirmação de e-mail e a aprovação independente do responsável não estiverem presentes. Não há endpoint público que transforme aceite, selfie ou booleano enviado pelo cliente em aprovação. A seleção de idade e o campo de responsável também não comprovam vínculo familiar.

## Decisões técnicas implementadas

- Senhas: somente hash scrypt no servidor, salt aleatório por senha, comparação em tempo constante. Não há hashing caseiro no Flutter. Senhas não ficam no banco do app.
- Sessões: access em memória, refresh no armazenamento seguro nativo, rotação, expiração, logout e revogação na redefinição de senha. No web não usamos localStorage para tokens; faltam cookies HttpOnly/BFF para sessão persistente de produção.
- Autorização: checada no servidor em recursos sociais, incluindo mídia; dados privados de outras contas não são retornados. Adultos só aprovam pedidos de contato destinados a eles; menores não podem aprovar sem fluxo do responsável.
- Bloqueios: verificados em ambas as direções no feed, stories, comentários, perfis e mensagens.
- Mensagens: somente contatos aprovados; envio requer preferência habilitada em ambas as contas, limite por remetente e validação de tamanho.
- Auditoria: tipo de evento, hash do identificador aleatório da conta e horário. Não registra conteúdo de chat, senhas, códigos, e-mails ou corpo HTTP.
- Dados: perfil público não inclui nascimento nem e-mail. E-mail do responsável e nascimento permanecem no servidor. Exportação omite credenciais; exclusão da conta remove dados associados por cascata.
- Galeria: somente foto escolhida pelo usuário; sem solicitação de acesso à câmera ou coleta biométrica. Upload verifica tamanho/MIME/assinatura e leitura exige autorização. Isso não substitui decodificação segura ou moderação de mídia.

## Biometria: três tecnologias distintas

| Tecnologia | Finalidade | O que não demonstra | Decisão nesta versão |
|---|---|---|---|
| Biometria local do aparelho (`local_auth`) | Solicitar autenticação aprovada pelo sistema operacional, incluindo biometria configurada ou credencial do aparelho | Identidade civil, idade e vínculo de responsável; aparelho pode ser compartilhado | Não adicionada; pode ser avaliada como proteção opcional para uma sessão já autenticada |
| Liveness / prova de presença | Avaliar se a captura pertence a uma pessoa presente, com resistência a ataques de apresentação | Identidade ou idade por si só | Não implementada; exige avaliação de fornecedor e riscos |
| Verificação facial de identidade | Comparação biométrica com uma referência validada e uma finalidade definida | Consentimento jurídico, necessidade e proporcionalidade do tratamento | Desativada; nenhuma imagem facial ou template é coletado para esse fim |

Detectar um rosto com câmera/ML não comprova identidade. `backend/providers.py` define contratos mínimos para entrega de e-mail e verificação do responsável. O provedor desconfigurado sempre rejeita callbacks. Esses contratos ainda precisam ser conectados ao serviço e a um protocolo de callbacks autenticados, com proteção contra replay, auditoria e minimização de dados. Priorizar verificação não biométrica de idade e participação do responsável quando adequada.

## Requisitos que exigem análise jurídica e operacional

A Lei 15.211/2025 e a LGPD devem orientar o desenho, mas o código isolado não demonstra conformidade. Validar com profissionais responsáveis:

1. Finalidades, bases legais, melhor interesse, classificação por faixa etária e efetividade da aferição de idade; considerar riscos de falsa declaração de maioridade.
2. Quando e como participação/consentimento do responsável devem ser obtidos, comprovados, revogados e versionados, respeitando autonomia progressiva e transparência para o menor.
3. Avisos claros por idade, direitos de acesso/correção/exclusão/portabilidade, canal de atendimento, retenção, tratamento de backups e obrigações de preservação aplicáveis.
4. Necessidade de relatório de impacto, avaliação de ameaças, fornecedores, contratos de tratamento, transferência internacional e resposta a incidentes.
5. Moderação, escalonamento urgente, prazos e deveres de comunicação/remoção, treinamento humano e proteção contra aliciamento, assédio e exposição indevida.
6. Ausência de publicidade comportamental e desenho sem padrões manipulativos; as funcionalidades atuais não incluem anúncios nem recomendações comportamentais.
7. Se biometria vier a ser proposta: necessidade, alternativa menos invasiva, segurança, proporcionalidade, categoria sensível, retenção e avaliação específica de fornecedor/uso.

## Pendências antes de produção

- Verificação de idade e responsável efetiva; painel com identidade própria do responsável, autorização por vínculo e trilha auditável.
- E-mail entregue por provedor, sem códigos em respostas ou logs, proteção anti-enumeração também em cadastro/tempo de resposta e recuperação.
- HTTPS, gestão de segredos no servidor, hospedagem segura, autorização administrativa, limites distribuídos e revisão independente de segurança.
- Pipeline que decodifique/reencode imagens, remova EXIF/GPS, impeça arquivos malformados, aplique moderação e limites de dimensões. Atualmente as imagens são armazenadas como recebidas; não usar dados pessoais reais.
- Processamento de vídeos, mídia no chat, antivírus quando aplicável, URLs privadas de curta validade e armazenamento externo apropriado.
- Retenção automatizada, filas de moderação, atendimento urgente, alertas de risco e avaliação humana de denúncias. A ferramenta local `moderate.py` não substitui essa operação.
- Revisão de persistência/exportação: o JSON atual cobre perfil básico, publicações, comentários, denúncias, bloqueios e mensagens; processo completo de direitos deve incluir outras relações e registros sujeitos à base legal.
- Configurações nativas do secure storage, backups, permissões de rede e plataforma, teste de acessibilidade e validação dos pacotes resolvidos.

## Fontes primárias consultadas em 06/10/2026

- [ECA Digital — Lei 15.211/2025, texto oficial](https://www.planalto.gov.br/ccivil_03/_ato2023-2026/2025/lei/l15211.htm).
- [LGPD — texto compilado oficial](https://planalto.gov.br/ccivil_03/_ato2015-2018/2018/lei/l13709compilado.htm).
- [ANPD — tratamento de dados de crianças e adolescentes](https://www.gov.br/anpd/pt-br/acesso-a-informacao/institucional/atos-normativos/regulamentacoes_anpd/tratamento_de_dados_de_criancas_e_adolescentes.pdf).
- [local_auth — documentação mantida por Flutter](https://pub.dev/packages/local_auth).

A lista identifica referências para revisão; não é parecer jurídico nem certificação.
