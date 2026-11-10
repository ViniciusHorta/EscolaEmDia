# Administração (ferramenta local)

Página estática para gerir o Supabase. Navegação pela barra lateral:

- **Conteúdos** — fichas e perguntas, temas/disciplinas
- **Relatos** — problemas reportados pelos responsáveis nas perguntas
- **Configurações** — documentos legais (Termos e Privacidade) e planos e limites (`billing_settings`, editáveis dentro de margens)
- **Utilizadores** — responsáveis com famílias, crianças, plano (Premium/Free/Bloqueada), forma de pagamento,
  último pagamento, renovação, valor, atividade e histórico de faturação; conceder/retirar Premium manual;
  cancelar assinaturas Stripe e Google Play (renovação ou já com reembolso)

## Usar

1. Aplicar as migrações `202611060001_admin_catalogue_management.sql`, `202611060002_admin_topic_usage_by_version.sql`
   e `202611060003_archive_topics.sql`, e fazer deploy da Edge Function `worksheets` (esconde temas arquivados aos responsáveis).
2. Abrir `tools/admin/index.html` diretamente no navegador (duplo clique).
3. Ligar com o URL do projeto e a chave `service_role` **legacy (JWT)**. A chave fica só em memória.

Não publicar esta página: com a chave `service_role` tem acesso total à base.

## Regras importantes

- **Versões publicadas são imutáveis.** Editar perguntas, ano ou temas de uma ficha publicada cria uma nova versão.
  Quem já tem a ficha atribuída mantém a versão antiga; novas atribuições usam a mais recente. O título não é versionado.
- **Guardar rascunho** grava sem mudar o que os responsáveis veem; **Guardar e publicar** torna a versão visível.
- Fichas publicadas não se apagam — **arquivam-se** (deixam de aparecer aos responsáveis; atribuições existentes continuam).
- Temas usados por fichas só podem ser renomeados. Retirar um tema de uma ficha publicada cria uma nova versão;
  as versões antigas continuam ligadas a ele («em versões antigas»), por isso não pode ser apagado.
- Esses temas podem ser **arquivados**: deixam de aparecer no editor e aos responsáveis, sem mexer no histórico.
  Só é possível quando nenhuma versão atual nem a versão publicada visível aos responsáveis o usa. Podem ser reativados.

- **Documentos legais são imutáveis.** Cada publicação cria uma versão nova. «Exige novo aceite» obriga todos os responsáveis
  a aceitar no próximo acesso (com o resumo «O que mudou»); desmarcar só para correções menores. A primeira versão exige sempre aceite.

- **Responsáveis.** Requer `202611100001_admin_users.sql` (sem ela, as outras secções funcionam e esta mostra o aviso).
  **Cancelar** uma assinatura Stripe ou Google Play passa pela Edge Function `admin-billing` (requer
  `202611100002_admin_billing_actions.sql`), que cancela na plataforma de origem com a chave do servidor:
  «cancelar a renovação» mantém o Premium até ao fim do período; «cancelar já» revoga e reembolsa o último pagamento.
  O estado final chega pelos webhooks. App Store ainda não suportada. Premium **manual** concede-se e retira-se aqui.
  Tudo fica registado no histórico.
- **Planos e limites.** Cada limite só aceita valores dentro de margens seguras (ex.: `max_premium_children` ≤ 5,
  o número de produtos-vaga nas lojas). Aumentar `free_child_slots` atribui logo as vagas; reduzir não as retira.

- **Free / Premium.** Cada ficha tem um tipo de acesso (selo na lista; clicar alterna). Fichas novas são Premium.
  Fichas Free não podem ser publicadas com mais perguntas do que o limite (`free_max_questions` em `billing_settings`,
  6 por omissão) — a base recusa. Se o limite for reduzido, as fichas já publicadas continuam válidas e aparecem
  com o selo «Acima do limite Free» (filtro próprio). Requer `202611070003_billing_limits.sql`.

## Estrutura

- `js/core.js` — estado, chamadas RPC, mensagens, diálogos
- `js/content.js` — validação das perguntas (espelha `valid_worksheet_content`), pedido para a IA, pré-visualização
- `js/worksheets.js` / `js/editor.js` — lista e editor de fichas
- `js/topics.js` — disciplinas e temas
- `js/reports.js` — relatos de problemas em perguntas
- `js/users.js` — responsáveis, assinaturas, histórico de faturação e planos e limites
- `js/legal.js` — publicação de versões dos Termos de Utilização e da Política de Privacidade (requer `202611060006_legal_documents.sql`)

Todas as escritas passam por funções `admin_*` (`security definer`, apenas `service_role`).
