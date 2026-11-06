# Administração (ferramenta local)

Página estática para gerir o catálogo no Supabase: **fichas e perguntas**, **temas/disciplinas** e **relatos de problemas** feitos pelos pais.

## Usar

1. Aplicar as migrações `202611060001_admin_catalogue_management.sql`, `202611060002_admin_topic_usage_by_version.sql`
   e `202611060003_archive_topics.sql`, e fazer deploy da Edge Function `worksheets` (esconde temas arquivados aos pais).
2. Abrir `tools/admin/index.html` diretamente no navegador (duplo clique).
3. Ligar com o URL do projeto e a chave `service_role` **legacy (JWT)**. A chave fica só em memória.

Não publicar esta página: com a chave `service_role` tem acesso total à base.

## Regras importantes

- **Versões publicadas são imutáveis.** Editar perguntas, ano ou temas de uma ficha publicada cria uma nova versão.
  Quem já tem a ficha atribuída mantém a versão antiga; novas atribuições usam a mais recente. O título não é versionado.
- **Guardar rascunho** grava sem mudar o que os pais veem; **Guardar e publicar** torna a versão visível.
- Fichas publicadas não se apagam — **arquivam-se** (deixam de aparecer aos pais; atribuições existentes continuam).
- Temas usados por fichas só podem ser renomeados. Retirar um tema de uma ficha publicada cria uma nova versão;
  as versões antigas continuam ligadas a ele («em versões antigas»), por isso não pode ser apagado.
- Esses temas podem ser **arquivados**: deixam de aparecer no editor e aos pais, sem mexer no histórico.
  Só é possível quando nenhuma versão atual nem a versão publicada visível aos pais o usa. Podem ser reativados.

## Estrutura

- `js/core.js` — estado, chamadas RPC, mensagens, diálogos
- `js/content.js` — validação das perguntas (espelha `valid_worksheet_content`), pedido para a IA, pré-visualização
- `js/worksheets.js` / `js/editor.js` — lista e editor de fichas
- `js/topics.js` — disciplinas e temas
- `js/reports.js` — relatos de problemas em perguntas

Todas as escritas passam por funções `admin_*` (`security definer`, apenas `service_role`).
