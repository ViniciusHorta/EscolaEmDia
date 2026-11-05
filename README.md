# Escola em Dia

Nova base Flutter, construída a partir das referências do Google Stitch em `UI/`.

## Executar na Web

```sh
flutter pub get
flutter run -d chrome --web-port=8081
```

A página inicial apresenta a conta familiar do Stitch: criação de conta e entrada, validação de campos, visibilidade da palavra-passe e aceitação dos termos. O registo e o login por e-mail estão ligados ao Supabase. A sessão é mantida pelo SDK e pode ser encerrada com «Sair da conta». Acesso social e recuperação de palavra-passe continuam desativados; os documentos legais ainda não estão disponíveis. Não usar o registo como aceitação legal definitiva enquanto os documentos não forem publicados.

A galeria interativa continua acessível em `/#/components` e pelo botão «Ver componentes» em desenvolvimento. Os dados da galeria são exemplos.

## Supabase — preparação para testar

O projeto está configurado em `lib/core/config/supabase_config.dart` com o URL e a chave pública fornecidos. Esses valores são públicos e podem ser substituídos por `--dart-define=SUPABASE_URL=...` e `--dart-define=SUPABASE_PUBLISHABLE_KEY=...`. Nunca colocar uma chave secret ou service_role no Flutter.

No painel Supabase:

1. Em Authentication, manter o fornecedor Email ativo e a confirmação de e-mail ligada.
2. Em Authentication → URL Configuration, adicionar `http://localhost:8081/` a Redirect URLs. Só alterar o Site URL para esse endereço se o projeto for exclusivamente de desenvolvimento.
3. Executar a aplicação sempre na mesma origem/porta para regressar pelo link de confirmação e recuperar a sessão.

```sh
flutter pub get
flutter run -d chrome --web-port=8081
```

Criar conta com um e-mail acessível, abrir a confirmação no mesmo navegador e entrar. Depois atualizar a página para verificar a sessão e usar «Sair da conta». Se o envio de e-mail for recusado, verificar as configurações e os limites de envio do projeto no Supabase.

A autenticação adulta usa Supabase Auth. As funções de PIN e de famílias validam a sessão e a confirmação de e-mail no servidor antes de aceder aos dados. A criação familiar e infantil exige a instalação abaixo.

Referência: https://supabase.com/docs/reference/dart/auth-signup

## Estrutura

- `lib/core/theme/`: cores, tipografia, espaçamentos e tema.
- `lib/shared/widgets/`: componentes partilhados, sem dependências dos ecrãs.
- `lib/features/auth/`: ecrã de entrada e criação de conta familiar.
- `lib/features/family/`: famílias, perfis infantis e conclusão da configuração.
- `lib/features/worksheets/`: catálogo, preparação, proposta, atribuição e cards infantis.
- `lib/features/component_gallery/`: demonstração dos componentes.
- `assets/fonts/`: fonte Lexend local e respetiva licença.
- `test/`: testes de interação.
- `web/`: entrada Web.
- `UI/`: referências originais do Stitch, preservadas.

A fonte Lexend é incluída nos assets; não depende do Google Fonts em execução. O roxo principal segue os HTML exportados (`#5845CA`). Os cards de perfil usam ícones provisórios; as ilustrações dos protótipos ainda não foram incorporadas.

## Validar

```sh
flutter analyze
flutter test
flutter build web
```

Apenas a plataforma Web está preparada nesta etapa. A configuração familiar, os restantes ecrãs de produto, as regras de acesso aos dados e as plataformas móveis serão implementados em passos posteriores.


## PIN parental — instalação no Supabase

O ecrã de configuração abre após o login de um adulto com e-mail confirmado, se a função indicar que ainda não existe PIN. Pede os mesmos quatro dígitos duas vezes. Após a confirmação de gravação, regressa à área de sessão. A instalação do servidor abaixo é necessária antes de testar este fluxo; não foi aplicada automaticamente ao projeto remoto.

1. Se a tabela inicial já foi criada, executar apenas `supabase/migrations/202611040002_align_adult_pin_credentials.sql` no SQL Editor. Esta migração renomeia a tabela para `adult_pin_credentials`, a chave para `adult_user_id` e acrescenta `updated_at`, preservando os dados. Numa instalação nova, executar os dois ficheiros por ordem. Não voltar a executar a migração inicial depois do alinhamento: ela é mantida como histórico e recriaria o nome antigo. Se ambas as tabelas existirem, a migração de alinhamento interrompe com erro para evitar escolher ou perder dados.
2. Gerar um segredo aleatório, por exemplo com `openssl rand -hex 32`. Em Edge Functions → Secrets, guardar esse valor como `PARENT_PIN_PEPPER`. Não enviar o segredo no chat, guardar no Git ou colocar no Flutter. Manter uma cópia segura: mudar ou perder este segredo impede verificar os PINs existentes.
3. Criar/publicar a função `parent-pin` com o conteúdo de `supabase/functions/parent-pin/index.ts`. A validação de JWT do gateway legado deve estar desativada para esta função, conforme `supabase/config.toml`: a função valida obrigatoriamente o token de sessão com `auth.getUser(token)` e verifica o e-mail confirmado antes de qualquer acesso aos dados. Não há acesso anónimo.
4. Se usar a CLI com o projeto associado, a publicação corresponde a `supabase functions deploy parent-pin --project-ref hhgxxvvreyhigxynrgmv`. O `config.toml` aplica a configuração da função. Não é necessário expor a service_role no cliente; a função utiliza os segredos padrão do ambiente Supabase.
5. Só após a publicação, reiniciar o Flutter e testar: criar PIN, repetir PIN diferente (deve rejeitar), repetir corretamente, sair e voltar a entrar (não deve pedir a criação outra vez).

A função expõe `GET /v1/status` e `POST /v1/setup`, publicados como `/functions/v1/parent-pin/v1/status` e `/functions/v1/parent-pin/v1/setup`. Correspondem às rotas lógicas `GET /v1/parent-pin/status` e `POST /v1/parent-pin/setup`. São adições ao contrato original, que previa apenas verificação e recuperação do PIN. O corpo da criação é `{"pin":"1234"}` (exemplo de formato, não PIN recomendado); o antigo campo `action` deixou de existir. O Flutter já usa as rotas novas. A função antiga, se publicada, tem de ser atualizada após a migração e antes de testar o cliente.

Os erros seguem `{"error":{"code":"...","message":"...","requestId":"uuid"}}`, com `X-Request-Id` também no cabeçalho. Os logs contêm apenas domínio, operação, estado HTTP, código do erro e identificador do pedido. O contrato implementado está em `supabase/api/parent-pin.openapi.yaml`. O utilizador vem sempre da sessão validada, não de um identificador fornecido pelo Flutter. A tabela não é acessível pelos papéis `anon` ou `authenticated`, e o servidor tem apenas SELECT e INSERT. O primeiro PIN não pode ser sobrescrito, nem por pedidos simultâneos.

O armazenamento usa PBKDF2-HMAC-SHA256 com 600 000 iterações, salt aleatório e pré-hash HMAC com pepper exclusivo do servidor. O PIN não é guardado nas preferências locais, metadados de Auth ou logs da aplicação. As origens permitidas são localhost/127.0.0.1 nas portas 8080 e 8081; acrescentar a origem HTTPS de produção ao publicar a aplicação.

Esta etapa configura o PIN. O desbloqueio, a limitação de tentativas e o bloqueio após inatividade são instalados na etapa descrita abaixo. A recuperação/alteração com reautenticação continua pendente. O PIN configurado não deve ser confundido com autorização de operações futuras: estas também terão de ser validadas no servidor.

Referências: [autenticação nas Edge Functions](https://supabase.com/docs/guides/functions/auth-legacy-jwt), [armazenamento de credenciais — OWASP](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html).


## Famílias e perfis infantis — instalação

1. Após as migrações do PIN parental, executar `supabase/migrations/202611040003_create_families_and_children.sql` uma única vez no SQL Editor. Cria `families`, `family_members`, `children`, `child_pin_credentials` e `family_audit_events`, com os campos nucleares do ERD e metadados técnicos de idempotência e hashing. Não elimina a tabela nem os dados do PIN adulto.
2. Gerar outro segredo aleatório (`openssl rand -hex 32`) e guardá-lo nos Secrets das Edge Functions com o nome `CHILD_PIN_PEPPER`. Não substituir o `PARENT_PIN_PEPPER`, não enviar o valor no chat nem guardá-lo no código. Preservar uma cópia segura: alterar o segredo invalida a verificação dos PINs infantis existentes.
3. Publicar a função `families` com o conteúdo de `supabase/functions/families/index.ts`. Desativar apenas nesta função a opção de verificação de JWT com segredo legado: o código valida cada sessão com `auth.getUser(token)`. A função `parent-pin` já publicada mantém-se.
4. Reiniciar a aplicação em `http://localhost:8081/`. Após o PIN parental, abre o formulário infantil se ainda não houver perfis.

O formulário inclui alcunha, seis avatares, anos escolares de 1.º a 4.º e confirmação do PIN infantil. Os avatares usam emojis provisórios; ilustrações do Stitch ainda não foram incorporadas. Entrada rápida, emparelhamento e login infantil não são apresentados como funcionalidades disponíveis nesta etapa.

Na primeira gravação, se o adulto não tiver família, cria-se uma família e a associação ao adulto. Depois, perfil e hash do PIN são gravados atomicamente numa RPC, com registo de auditoria sem PIN. Se houver falha no segundo pedido, a família fica guardada e pode ser reutilizada. O identificador de pedido é mantido em memória para repetir a mesma submissão sem duplicar o perfil. Adultos com várias famílias escolhem qual utilizar; não há unicidade global que os limite a uma família.

O PIN usa PBKDF2-HMAC-SHA256 com 600 000 iterações, salt aleatório e HMAC com o segredo infantil. O hash, o salt e a impressão de idempotência ficam numa tabela sem acesso pelos papéis `anon` ou `authenticated`. A função apenas devolve o perfil. As RPCs são exclusivas de `service_role`, têm search_path vazio e verificam as associações na mesma transação. As tabelas têm RLS ativo e não concedem acesso direto ao Flutter.

A API segue as rotas lógicas aprovadas, publicadas sob `/functions/v1/families`: `GET/POST /v1/families` e `GET/POST /v1/families/{id}/children`. Listas têm paginação por cursor. O contrato está em `supabase/api/families.openapi.yaml`. Os erros seguem code/message/requestId; os logs não incluem perfis, PINs ou tokens.

Validação manual pelo utilizador: criar uma criança, rejeitar confirmação de PIN diferente, guardar corretamente, adicionar outra criança e sair/entrar para confirmar a persistência. Não enviar os PINs no chat. A edição de perfis, redefinição de PIN, convites e emparelhamento de dispositivos ficam para etapas posteriores.


## Entrada infantil — instalação

1. Executar uma vez `supabase/migrations/202611040004_create_child_sessions.sql` no SQL Editor após as migrações anteriores. Cria `child_sessions` e a tabela técnica de tentativas `child_pin_attempts`. Não altera os perfis nem os PINs existentes.
2. Publicar a nova função `child-sessions`, usando `supabase/functions/child-sessions/index.ts`, e desativar a verificação de JWT com segredo legado apenas nessa função. O código valida a sessão adulta com Auth na criação; as outras rotas validam tokens infantis opacos. Reutiliza `CHILD_PIN_PEPPER`, sem criar ou substituir segredos.
3. Executar `flutter pub get` e reiniciar a aplicação na porta 8081. Na área familiar, escolher «Entrar no espaço infantil», selecionar uma criança e introduzir o PIN. A listagem dos perfis usa a autorização adulta do dispositivo partilhado; os pedidos do espaço infantil usam um cliente HTTP separado e exclusivamente o token infantil.

A função expõe POST `/v1/child-sessions`, GET `/v1/child-sessions/me` e POST `/v1/child-sessions/revoke`, sob `/functions/v1/child-sessions`. A rota `me` é uma extensão ao catálogo inicial para recuperar apenas o perfil da sessão, sem aceitar childId. O contrato está em `supabase/api/child-sessions.openapi.yaml`.

O servidor limita cada criança a cinco tentativas por janela de 15 minutos e bloqueia por cinco minutos. As tentativas são reservadas atomicamente antes do cálculo do hash, incluindo pedidos concorrentes ou abandonados. Um PIN correto na quinta tentativa ainda pode iniciar a sessão e reinicia o contador. Desafios expiram em 30 segundos e não podem ser reutilizados. Os RPCs são acessíveis apenas a service_role; as tabelas têm RLS ativo e não concedem acesso direto ao cliente.

Os tokens são aleatórios (256 bits), não são JWTs e ficam apenas em memória no Flutter; a base guarda exclusivamente SHA-256 do token. A sessão dura uma hora, pode ser revogada e depende da família ativa, do adulto autorizador continuar membro e da versão do PIN. Não há refresh tokens, emparelhamento ou acesso autónomo em dispositivos novos nesta entrega. Recarregar a página exige novamente o PIN da criança. A preferência local recorda apenas o modo infantil e a família, não o token ou PIN.

«Mudar de utilizador» revoga a sessão e volta ao seletor infantil. O modo infantil não tem ligação direta à gestão parental; «Sair do dispositivo» revoga a sessão e termina a conta adulta. É necessário autenticar o adulto novamente para voltar à gestão. O desbloqueio parental por PIN e o bloqueio por inatividade são instalados na etapa abaixo. A preferência de navegação local não é uma fronteira de autorização do servidor; futuras operações parentais sensíveis deverão também exigir uma autorização de desbloqueio validada no servidor.

O espaço de estudo apresenta o perfil devolvido pelo servidor. As fichas atribuídas são carregadas pela função worksheets descrita abaixo; sem atribuições, apresenta um estado vazio. Não há resultados fictícios. As ilustrações continuam a usar os avatares provisórios.

Validação manual pelo utilizador: entrar com cada criança, verificar que o PIN incorreto não entra, mudar de utilizador e conferir os respetivos perfis; testar o bloqueio após cinco falhas e a recuperação após cinco minutos. Atualizar a página deve manter o seletor infantil, pedindo PIN outra vez. Sair do dispositivo deve pedir autenticação adulta antes de mostrar a gestão familiar. Não enviar PINs ou tokens no chat.


## Desbloqueio parental e inatividade — instalação

1. Executar uma vez `supabase/migrations/202611050001_create_parent_unlock_sessions.sql` no SQL Editor, após as migrações anteriores. Não altera os PINs nem as famílias/crianças. Cria `adult_pin_attempts`, `parent_unlock_sessions` e RPCs exclusivas de service_role, com RLS e sem acesso direto aos dados pelos clientes.
2. Atualizar a função existente `parent-pin` com o conteúdo atual de `supabase/functions/parent-pin/index.ts`. Mantém a verificação de JWT com segredo legado desativada: a função valida o JWT no Auth e só depois usa o identificador session_id do token verificado. Reutiliza `PARENT_PIN_PEPPER` sem o alterar.
3. Atualizar também a função existente `families` com `supabase/functions/families/index.ts`, mantendo a configuração atual de JWT. Os pedidos POST passam a exigir JWT adulto e X-Parent-Unlock válido. Aplicar ambos os servidores antes de testar o novo Flutter. Não é preciso alterar a função child-sessions.
4. Reiniciar o Flutter. O seletor infantil e o espaço de estudo apresentam «Área dos pais». O PIN correto revoga a sessão infantil ativa e abre a gestão familiar sem terminar a sessão Auth do adulto. Novas entradas adultas também pedem o PIN parental após a verificação de que foi configurado.

A rota lógica POST `/v1/parent-pin/verify` está publicada em `/functions/v1/parent-pin/v1/verify`. Recebe apenas pin, nunca um identificador de adulto. Acrescentam-se as rotas auxiliares GET `/v1/unlock-status`, POST `/v1/touch` e POST `/v1/revoke` sob a mesma função. Pedidos de verificação limitados por adulto: cinco reservas por janela de 15 minutos, bloqueio de cinco minutos. PIN correto na quinta tentativa ainda desbloqueia. Pedidos concorrentes e abandonados não contornam o contador.

O servidor emite um token opaco par_ de 256 bits, guarda apenas SHA-256 e associa-o ao adulto, à sessão Supabase Auth e à versão da credencial. O token fica apenas em memória no Flutter. Não é persistido em preferências, no URL ou em logs. Não substitui a sessão Auth e não autoriza operações de outro adulto ou de outra sessão. A entrada no modo infantil e a saída da conta eliminam a autorização local e tentam revogá-la no servidor; em falha de rede, mantém-se o prazo de expiração do servidor.

A atividade de ponteiro, deslocação e teclado repõe o prazo local de cinco minutos. Há pedidos touch apenas após atividade real (com limitação de frequência e atualização após o último evento), sem keepalive periódico em repouso. O servidor também exige autorização não expirada, com prazo móvel de cinco minutos e limite absoluto de doze horas. Regressar a uma aplicação suspensa consulta a validade sem prolongar o prazo. Em falha de validação, o cliente bloqueia. Atualizar a página exige novo PIN parental ou regressa ao seletor infantil, consoante o modo guardado.

Criar família ou criança exige X-Parent-Unlock no servidor. A listagem mínima de famílias/perfis continua disponível com JWT adulto no dispositivo partilhado para apresentar o seletor infantil; dados futuros de respostas, revisão e operações sensíveis também deverão exigir autorização parental. As RPCs de criação permanecem exclusivas do servidor e não podem ser chamadas pelo Flutter para contornar a verificação da Edge Function.

Validação manual: testar PIN parental errado/correto; confirmar que um PIN infantil não abre a área parental (quando os valores são diferentes); voltar ao modo infantil; deixar a área parental sem atividade durante cinco minutos e verificar que volta a bloquear; testar nova gravação de perfil após desbloquear e limite de cinco falhas. Não enviar PINs ou tokens no chat. A recuperação de PIN com reautenticação recente continua pendente.


## Catálogo e preparação de fichas — instalação

1. Executar uma vez `supabase/migrations/202611050002_create_worksheet_catalogue.sql`. Cria as entidades do ERD: subjects, topics, worksheets, worksheet_versions, worksheet_version_topics e worksheet_assignments, mais a vista de metadados worksheet_catalogue. Mantém os dados das famílias, crianças e PINs.
2. Executar `supabase/migrations/202611050003_seed_sample_worksheets.sql` para carregar o catálogo inicial de exemplos: Matemática e Português, anos 1.º a 4.º, com duas áreas por disciplina/ano e fichas para cada tema isolado ou os dois juntos. São 24 fichas de exemplo, cada uma com quatro perguntas objetivas e duas abertas. Estão identificadas na interface por «Ficha de exemplo». Este conteúdo foi preparado para demonstração; não representa validação editorial nem alinhamento certificado com o currículo oficial. O seed pode ser repetido sem alterar versões publicadas.
3. Publicar a nova função `worksheets` com `supabase/functions/worksheets/index.ts` e desativar a verificação de JWT com segredo legado apenas nessa função. O código valida JWT adulto e desbloqueio parental, ou exclusivamente o token infantil na listagem da própria criança. Não há novos segredos nem necessidade de atualizar as outras funções.
4. Reiniciar o Flutter. Desbloquear a área dos pais e escolher «Preparar ficha». Selecionar criança, disciplina e pelo menos um tema, rever a proposta e disponibilizar. «Ver no perfil» abre o seletor infantil na criança escolhida e continua a exigir o respetivo PIN.

O catálogo usa fichas publicadas e versionadas, não geração de perguntas. A seleção de temas tem correspondência exata com os temas da versão; sem correspondência, informa que não existe proposta e permite mudar a seleção. Quando existir mais de uma ficha compatível, o adulto pode escolher a alternativa. A dimensão é calculada pela quantidade de perguntas, e a proposta apresenta as contagens reais de escolha múltipla e respostas abertas. Não promete uma proporção fixa de 70/30 nem inventa uma duração estimada.

A publicação exige temas coerentes com disciplina e ano. JSONB valida os tipos iniciais de perguntas, IDs e opções únicos, limites de perguntas/opções e referência correta da solução. Versões publicadas e as suas associações a temas não podem ser alteradas ou eliminadas; alterações pedagógicas exigem uma nova versão. Conteúdo inclui soluções para uso futuro da correção no servidor. Apenas a pré-visualização parental desbloqueada recebe o conteúdo completo.

A atribuição usa clientRequestId, mantém a versão exata e é confirmada pelo servidor. A transação valida novamente o desbloqueio parental, pertença familiar e ano escolar, guarda a atribuição e o evento de auditoria. Pedidos repetidos não duplicam a atribuição; a mesma versão não pode ter duas atribuições ativas para a mesma criança. Uma realização futura usará worksheet_attempts, sem criar uma atribuição nova para cada repetição.

A listagem infantil usa o cliente HTTP de sessão infantil, sem JWT adulto. A API valida a sessão opaca e só permite o próprio childId. Devolve título, disciplina, temas, ano, contagens e identificação da versão/atribuição; nunca perguntas, soluções, explicações ou critérios de correção. O card apresenta «Por começar». Resolver, guardar respostas e entregar a ficha continuam para a etapa seguinte, sem botões que simulem uma realização já disponível.

Rotas sob `/functions/v1/worksheets`: GET `/v1/subjects`, GET `/v1/topics`, GET `/v1/worksheets`, GET `/v1/worksheets/{id}`, POST/GET `/v1/children/{id}/assignments`. Listas são paginadas por cursor; erros seguem code/message/requestId. O contrato está em `supabase/api/worksheets.openapi.yaml`. As tabelas têm RLS e não permitem acesso direto ao Flutter; escritas de atribuição e auditoria são exclusivas da RPC autorizada ao servidor.

Validação manual pelo utilizador: disponibilizar uma ficha para uma criança e conferir que aparece apenas no respetivo perfil; atribuir outra à segunda criança; testar mudança de disciplina/temas e impedir duplicar a mesma versão ativa. Verificar que cinco minutos de inatividade na preparação bloqueiam a área parental e impedem a gravação sem novo desbloqueio. Não enviar tokens ou PINs no chat.
