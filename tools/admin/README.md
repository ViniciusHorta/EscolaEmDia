# Administração (ferramenta local)

Página estática para gerir o catálogo no Supabase: **fichas e perguntas**, **temas/disciplinas**, **relatos de problemas** feitos pelos responsáveis e **documentos legais** (Termos e Privacidade).

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

## Estrutura

- `js/core.js` — estado, chamadas RPC, mensagens, diálogos
- `js/content.js` — validação das perguntas (espelha `valid_worksheet_content`), pedido para a IA, pré-visualização
- `js/worksheets.js` / `js/editor.js` — lista e editor de fichas
- `js/topics.js` — disciplinas e temas
- `js/reports.js` — relatos de problemas em perguntas
- `js/legal.js` — publicação de versões dos Termos de Utilização e da Política de Privacidade (requer `202611060006_legal_documents.sql`)

Todas as escritas passam por funções `admin_*` (`security definer`, apenas `service_role`).
