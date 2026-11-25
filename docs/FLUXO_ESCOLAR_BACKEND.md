# Acompanhamento escolar autorizado — backend

## Interpretação do quadro

O fluxo implementado é: responsável -> convite -> aceite do tutor -> modo
compartilhado -> consulta limitada -> pausa/revogação, com registros de ações.
O aluno consulta seus próprios vínculos, modo e registros. O tutor é uma conta
adulta verificada convidada para um aluno específico; não é um administrador.

Anotações ambíguas como “coordenadores”, “processos BL” e “exposto” não foram
transformadas em permissões globais. Não existe publicação pública de dados de
menores. A identidade profissional do tutor não é certificada pelo sistema:
a escolha e autorização pertencem ao responsável atual. Cadastro institucional,
turmas e coordenação escolar exigem um fluxo próprio antes de conceder acesso.

## Estados e permissões

- Padrão: `guardian_only` (somente família).
- `shared`: permite acesso dos tutores que aceitaram convites ativos.
- `paused`: interrompe o acesso escolar; não pausa o login/feed do aluno.
- Convites: `pending`, `active`, `declined`, `expired`, `revoked`.
- Convite pendente expira em sete dias. Revogado não pode ser reaceito.
- Escopos `summary` (categorias/contagem) e `history` (categorias/horários,
  últimos 50 registros). Nenhum deles fornece texto, fotos ou mensagens privadas.
- A consulta começa após o aceite e a última ativação do modo compartilhado.
  Não revela histórico anterior nem o período em que o modo estava pausado.
- Para ampliar escopo, revogue o vínculo e envie novo convite com novo aceite.
- Vínculo familiar pausado, troca de responsável, bloqueio, suspensão e chegada
  à maioridade impedem o acesso. São reavaliados a cada requisição.
- Os convites são internos ao app; nenhuma mensagem de e-mail é enviada.

## Endpoints (token Firebase/Bearer da conta correspondente)

| Método | Caminho | Quem / ação |
|---|---|---|
| POST | `/school/children/{childId}/tutors` | Responsável convida tutor |
| GET | `/school/invitations` | Tutor consulta seus convites pendentes |
| POST | `/school/invitations/{inviteId}/decision` | Tutor aceita ou recusa |
| PATCH | `/school/children/{childId}/privacy` | Responsável escolhe modo |
| GET | `/school/children/{childId}/privacy` | Responsável ou aluno consulta modo |
| GET | `/school/children/{childId}/tutors` | Responsável ou aluno consulta vínculos |
| DELETE | `/school/children/{childId}/tutors/{inviteId}` | Responsável revoga |
| GET | `/school/students` | Tutor lista somente alunos acessíveis |
| GET | `/school/children/{childId}/activity?days=7` | Tutor autorizado consulta atividade |
| GET | `/school/children/{childId}/audit` | Responsável ou aluno consulta eventos |

Corpo do convite:
```json
{"tutorId":"ID_DA_CONTA_ADULTA","scope":"summary","consent":true,"consentVersion":"school-v1"}
```
Aceite: `{"accept":true}`. Recusa: `{"accept":false}`.
Modo: `{"mode":"shared"}` (ou `guardian_only` / `paused`).
Atividade aceita `days=7` ou `days=30`. Usa os registros já existentes do feed,
que não significam interesse ou aprovação do conteúdo.

## Persistência e segurança

Tabelas aditivas: `tutor_links`, `school_privacy`, `school_audit`. Índice único
impede convites simultâneos para o mesmo aluno/tutor. Repetir o mesmo convite
retorna o vínculo existente; um escopo diferente exige revogação. Transações do
Service mantêm alterações e auditoria atômicas. Limite: 20 convites/hora por
responsável. Listagens têm limite de 100 itens, histórico de atividade de 50.

`/me/export` inclui vínculos escolares da própria conta, preferências do aluno
e ações próprias. Exclusão usa chaves estrangeiras em cascata; o ator de um evento
fica nulo se excluído. Auditoria escolar registra evento e horário, sem copiar
conteúdo do feed, senhas ou tokens. É preservada até a exclusão do aluno; uma
política institucional de retenção ainda deve ser definida antes de produção.

Estas são medidas técnicas de privacidade, não certificação de conformidade
com a LGPD. O produto ainda precisa definir responsabilidades institucionais,
termos e processos de atendimento apropriados ao uso real.

## Integração e testes

Reinicie a API para carregar as rotas e aplicar a migração aditiva. Nenhuma conta
existente vira tutor automaticamente.
O acompanhamento familiar já existente continua independente.

As telas Flutter agora consomem estes endpoints: o painel da família abre o
acompanhamento de cada menor, a opção “Área do tutor” reúne convites e alunos,
e o menor consulta seus próprios vínculos sem poder alterar permissões.
O seletor de tutor usa `GET /school/tutor-candidates`, que retorna somente
contatos adultos aprovados, sem e-mails ou datas de nascimento.

Testes: `python -m unittest discover -s backend`. `test_school.py` cobre
consentimento, aceite, modo padrão, expiração, destinatário, revogação, mudança de
escopo, isolamento familiar, chats, bloqueios, suspensão, minimização, exportação
e cascata de exclusão.
