# Administração (ferramenta local)

Página estática para gerir o Supabase. Navegação pela barra lateral:

- **Conteúdos** — fichas e perguntas, temas/disciplinas e **Cobertura** (matriz curricular do 1.º ao 3.º ciclo › temas › conteúdos
  × fichas publicadas: mínimo de 1 Free e 3 Premium por conteúdo; lista do que criar a seguir)
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
4. A página atual fica no endereço (`#/fichas/<id>`, `#/cobertura/<disciplina>/<ano>`, `#/temas`, …): o «voltar» do navegador
   funciona e, ao recarregar, depois de voltar a ligar, o admin abre a mesma página (a chave volta a ser pedida).

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

- **Imagens nas perguntas.** Requer `202611220001_question_images_bucket.sql` e `202611220002_question_images.sql`.
  «🖼 Adicionar imagem» envia o ficheiro (PNG, JPEG, WebP ou GIF; fotos grandes são reduzidas para WebP até 1600 px, máx. 2 MB)
  para o bucket público `question-images` e guarda na pergunta `"image": {"path": "…", "alt": "…"}`.
  «Remover imagem» só a tira da pergunta: o ficheiro fica no bucket, porque versões antigas publicadas podem usá-lo.
  Nome do ficheiro: `<disciplina>/<ano>/<título-da-ficha>/<pergunta>-<AAAAMMDD-HHMMSS>.<ext>`
  (ex.: `matematica/5/comparacao-e-ordenacao-de-fracoes-e-decimais-na-reta-02/q1-20261122-194233.webp`).
  A exportação/importação de fichas mantém o caminho, mas **não copia os ficheiros**. A **Migração** copia-os.

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

- **Conteúdos da grade** (só admin). Requer `202611210001_topic_contents.sql`. Nível abaixo do tema: Disciplina › Ano › Tema › Conteúdo.
  Geridos em Cobertura (clicar numa célula): «Colar lista» com os tópicos de estudo das educadoras (uma linha por conteúdo;
  uma linha «Tema:» muda o tema) ou «Importar rascunho» (`js/curriculum-draft.js`, Aprendizagens Essenciais — rever antes).
  Cada ficha marca os seus conteúdos no editor; a marcação não é versionada. Os responsáveis só veem temas com fichas publicadas
  (Edge Function `worksheets`, `/v1/topics`), por isso temas novos criados para organizar conteúdos não lhes aparecem vazios.

- **Exportar / importar fichas entre ambientes** (lista de Fichas). «⇩ Exportar» grava num ficheiro JSON as fichas dos filtros atuais
  (versão mais recente, temas, conteúdos da grade, Free/Premium). «⇧ Importar», ligado ao outro ambiente, mostra a pré-visualização:
  fichas novas, as que já existem (mesma disciplina, título e ano: ignorar ou atualizar) e erros (ex.: disciplina em falta).
  Temas e conteúdos são ligados pelo nome e criados se faltarem. Por omissão grava como rascunho.

- **Migração** (Conteúdos › 🔀 Migração). Requer `202611260001_admin_worksheet_digests.sql` **nas duas bases**.
  Leva fichas da base ligada (origem) para outra (destino), ex.: staging → produção.
  1. Pede o URL e a chave `service_role` legacy do destino (só em memória).
  2. Compara as duas bases e lista só as fichas da **origem** que não existem no destino ou estão diferentes
     (perguntas, temas, Free/Premium, conteúdos da grade, publicação), por disciplina › ano › tema. O que só existe
     no destino não aparece; fichas arquivadas não se migram. Fichas com título repetido (mesma disciplina e ano)
     ficam bloqueadas até se mudar o título.
  3. Escolhes as fichas (uma a uma ou o grupo inteiro) e «Migrar selecionadas»: copia as imagens das perguntas
     (mesmo caminho no bucket; as que já existem não são substituídas), cria temas e conteúdos em falta e grava a ficha —
     publicada se está publicada na origem; uma ficha que já existe ganha uma versão nova.

## Estrutura

- `js/core.js` — estado, chamadas RPC, mensagens, diálogos
- `js/content.js` — validação das perguntas (espelha `valid_worksheet_content`), pedido para a IA, pré-visualização
- `js/worksheets.js` / `js/editor.js` — lista e editor de fichas
- `js/topics.js` — disciplinas e temas
- `js/curriculum-draft.js` — rascunho dos conteúdos por disciplina/ano/tema
- `js/transfer.js` — exportar/importar fichas entre ambientes
- `js/migrate.js` — migração de fichas e imagens para outra base
- `js/coverage.js` — cobertura do catálogo; a matriz curricular e os mínimos (`MIN_FREE`, `MIN_PREMIUM`) estão no topo do ficheiro
- `js/reports.js` — relatos de problemas em perguntas
- `js/users.js` — responsáveis, assinaturas, histórico de faturação e planos e limites
- `js/legal.js` — publicação de versões dos Termos de Utilização e da Política de Privacidade (requer `202611060006_legal_documents.sql`)

Todas as escritas passam por funções `admin_*` (`security definer`, apenas `service_role`).
