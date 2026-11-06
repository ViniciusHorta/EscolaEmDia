# Escola em Dia

Nova base Flutter, construída a partir das referências do Google Stitch em `UI/`.

## Executar na Web

```sh
flutter pub get
flutter run -d chrome --web-port=8081
```

A página inicial apresenta a conta familiar do Stitch: criação de conta e entrada, validação de campos, visibilidade da palavra-passe e aceitação dos termos. O registo e o login por e-mail estão ligados ao Supabase. A sessão é mantida pelo SDK e pode ser encerrada com «Sair da conta». Acesso social e recuperação de palavra-passe continuam desativados; os documentos legais ainda não estão disponíveis. Não usar o registo como aceitação legal definitiva enquanto os documentos não forem publicados.

A galeria interativa continua acessível em `/#/components` e pelo botão «Ver componentes» em desenvolvimento. Os dados da galeria são exemplos.

## Configuração central de CORS e publicação das funções

Todas as sete Edge Functions importam `supabase/functions/_shared/cors.ts`. As origens deixam de estar fixas no código e passam a ser lidas de `ALLOWED_ORIGINS`, em **Edge Functions → Secrets** no painel Supabase. Valor de desenvolvimento:

```text
http://localhost:8081,http://127.0.0.1:8081,http://localhost:8080,http://127.0.0.1:8080
```

Separar origens por vírgula, sem caminhos nem barra final. Em produção, configurar os domínios HTTPS efetivos. Não aceita `*`, `null`, lista vazia nem entradas inválidas; configuração ausente ou inválida devolve 503 `CORS_NOT_CONFIGURED`. Origem não autorizada devolve 403. Pedidos nativos sem Origin continuam sujeitos à autenticação e autorização de cada rota. Não há alteração da configuração de redirecionamento do Supabase Auth.

**Configurar a variável antes de publicar esta versão.** As versões já publicadas só passam a usar esta configuração depois de atualizadas. Para desenvolvimento com Supabase local, copiar `supabase/functions/.env.example` para `.env` na mesma pasta. O ficheiro `.env` está ignorado pelo Git.

**Publicação atual:** as instruções históricas abaixo que mandam copiar apenas `index.ts` foram substituídas pela publicação via Supabase CLI, incluindo o módulo partilhado. Na raiz do projeto, depois de instalar e autenticar a CLI (`supabase login`), publicar todas as funções:

```sh
supabase functions deploy --project-ref hhgxxvvreyhigxynrgmv
```

O `supabase/config.toml` já desativa a verificação JWT legada nas sete funções; cada rota mantém a sua própria validação. O módulo `_shared` é incluído pelas importações e não é uma função independente. Alterações no módulo exigem republicar todas as funções que o usam. Alterações apenas ao valor de um Secret não exigem republicação: https://supabase.com/docs/guides/functions/secrets . Publicação pela CLI: https://supabase.com/docs/guides/functions/deploy .

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
- `lib/features/attempts/`: perguntas, respostas, pausa, recuperação e conflitos de revisão.
- `lib/features/reviews/`: resumos das fichas com respostas abertas pendentes.
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


## PIN do responsável — instalação no Supabase

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

1. Após as migrações do PIN do responsável, executar `supabase/migrations/202611040003_create_families_and_children.sql` uma única vez no SQL Editor. Cria `families`, `family_members`, `children`, `child_pin_credentials` e `family_audit_events`, com os campos nucleares do ERD e metadados técnicos de idempotência e hashing. Não elimina a tabela nem os dados do PIN adulto.
2. Gerar outro segredo aleatório (`openssl rand -hex 32`) e guardá-lo nos Secrets das Edge Functions com o nome `CHILD_PIN_PEPPER`. Não substituir o `PARENT_PIN_PEPPER`, não enviar o valor no chat nem guardá-lo no código. Preservar uma cópia segura: alterar o segredo invalida a verificação dos PINs infantis existentes.
3. Publicar a função `families` com o conteúdo de `supabase/functions/families/index.ts`. Desativar apenas nesta função a opção de verificação de JWT com segredo legado: o código valida cada sessão com `auth.getUser(token)`. A função `parent-pin` já publicada mantém-se.
4. Reiniciar a aplicação em `http://localhost:8081/`. Após o PIN do responsável, abre o formulário infantil se ainda não houver perfis.

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

«Mudar de utilizador» revoga a sessão e volta ao seletor infantil. O modo infantil não tem ligação direta à gestão do responsável; «Sair do dispositivo» revoga a sessão e termina a conta adulta. É necessário autenticar o adulto novamente para voltar à gestão. O desbloqueio do responsável por PIN e o bloqueio por inatividade são instalados na etapa abaixo. A preferência de navegação local não é uma fronteira de autorização do servidor; futuras operações sensíveis do responsável deverão também exigir uma autorização de desbloqueio validada no servidor.

O espaço de estudo apresenta o perfil devolvido pelo servidor. As fichas atribuídas são carregadas pela função worksheets descrita abaixo; sem atribuições, apresenta um estado vazio. Não há resultados fictícios. As ilustrações continuam a usar os avatares provisórios.

Validação manual pelo utilizador: entrar com cada criança, verificar que o PIN incorreto não entra, mudar de utilizador e conferir os respetivos perfis; testar o bloqueio após cinco falhas e a recuperação após cinco minutos. Atualizar a página deve manter o seletor infantil, pedindo PIN outra vez. Sair do dispositivo deve pedir autenticação adulta antes de mostrar a gestão familiar. Não enviar PINs ou tokens no chat.


## Desbloqueio do responsável e inatividade — instalação

1. Executar uma vez `supabase/migrations/202611050001_create_parent_unlock_sessions.sql` no SQL Editor, após as migrações anteriores. Não altera os PINs nem as famílias/crianças. Cria `adult_pin_attempts`, `parent_unlock_sessions` e RPCs exclusivas de service_role, com RLS e sem acesso direto aos dados pelos clientes.
2. Atualizar a função existente `parent-pin` com o conteúdo atual de `supabase/functions/parent-pin/index.ts`. Mantém a verificação de JWT com segredo legado desativada: a função valida o JWT no Auth e só depois usa o identificador session_id do token verificado. Reutiliza `PARENT_PIN_PEPPER` sem o alterar.
3. Atualizar também a função existente `families` com `supabase/functions/families/index.ts`, mantendo a configuração atual de JWT. Os pedidos POST passam a exigir JWT adulto e X-Parent-Unlock válido. Aplicar ambos os servidores antes de testar o novo Flutter. Não é preciso alterar a função child-sessions.
4. Reiniciar o Flutter. O seletor infantil e o espaço de estudo apresentam «Área do responsável». O PIN correto revoga a sessão infantil ativa e abre a gestão familiar sem terminar a sessão Auth do adulto. Novas entradas adultas também pedem o PIN do responsável após a verificação de que foi configurado.

A rota lógica POST `/v1/parent-pin/verify` está publicada em `/functions/v1/parent-pin/v1/verify`. Recebe apenas pin, nunca um identificador de adulto. Acrescentam-se as rotas auxiliares GET `/v1/unlock-status`, POST `/v1/touch` e POST `/v1/revoke` sob a mesma função. Pedidos de verificação limitados por adulto: cinco reservas por janela de 15 minutos, bloqueio de cinco minutos. PIN correto na quinta tentativa ainda desbloqueia. Pedidos concorrentes e abandonados não contornam o contador.

O servidor emite um token opaco par_ de 256 bits, guarda apenas SHA-256 e associa-o ao adulto, à sessão Supabase Auth e à versão da credencial. O token fica apenas em memória no Flutter. Não é persistido em preferências, no URL ou em logs. Não substitui a sessão Auth e não autoriza operações de outro adulto ou de outra sessão. A entrada no modo infantil e a saída da conta eliminam a autorização local e tentam revogá-la no servidor; em falha de rede, mantém-se o prazo de expiração do servidor.

A atividade de ponteiro, deslocação e teclado repõe o prazo local de cinco minutos. Há pedidos touch apenas após atividade real (com limitação de frequência e atualização após o último evento), sem keepalive periódico em repouso. O servidor também exige autorização não expirada, com prazo móvel de cinco minutos e limite absoluto de doze horas. Regressar a uma aplicação suspensa consulta a validade sem prolongar o prazo. Em falha de validação, o cliente bloqueia. Atualizar a página exige novo PIN do responsável ou regressa ao seletor infantil, consoante o modo guardado.

Criar família ou criança exige X-Parent-Unlock no servidor. A listagem mínima de famílias/perfis continua disponível com JWT adulto no dispositivo partilhado para apresentar o seletor infantil; dados futuros de respostas, revisão e operações sensíveis também deverão exigir autorização do responsável. As RPCs de criação permanecem exclusivas do servidor e não podem ser chamadas pelo Flutter para contornar a verificação da Edge Function.

Validação manual: testar PIN do responsável errado/correto; confirmar que um PIN infantil não abre a área do responsável (quando os valores são diferentes); voltar ao modo infantil; deixar a área do responsável sem atividade durante cinco minutos e verificar que volta a bloquear; testar nova gravação de perfil após desbloquear e limite de cinco falhas. Não enviar PINs ou tokens no chat. A recuperação de PIN com reautenticação recente continua pendente.


## Catálogo e preparação de fichas — instalação

1. Executar uma vez `supabase/migrations/202611050002_create_worksheet_catalogue.sql`. Cria as entidades do ERD: subjects, topics, worksheets, worksheet_versions, worksheet_version_topics e worksheet_assignments, mais a vista de metadados worksheet_catalogue. Mantém os dados das famílias, crianças e PINs.
2. Executar `supabase/migrations/202611050003_seed_sample_worksheets.sql` para carregar o catálogo inicial de exemplos: Matemática e Português, anos 1.º a 4.º, com duas áreas por disciplina/ano e fichas para cada tema isolado ou os dois juntos. São 24 fichas de exemplo, cada uma com quatro perguntas objetivas e duas abertas. Estão identificadas na interface por «Ficha de exemplo». Este conteúdo foi preparado para demonstração; não representa validação editorial nem alinhamento certificado com o currículo oficial. O seed pode ser repetido sem alterar versões publicadas.
3. Publicar a nova função `worksheets` com `supabase/functions/worksheets/index.ts` e desativar a verificação de JWT com segredo legado apenas nessa função. O código valida JWT adulto e desbloqueio do responsável, ou exclusivamente o token infantil na listagem da própria criança. Não há novos segredos nem necessidade de atualizar as outras funções.
4. Reiniciar o Flutter. Desbloquear a área do responsável e escolher «Preparar ficha». Selecionar criança, disciplina e pelo menos um tema, rever a proposta e disponibilizar. «Ver no perfil» abre o seletor infantil na criança escolhida e continua a exigir o respetivo PIN.

O catálogo usa fichas publicadas e versionadas, não geração de perguntas. A seleção de temas tem correspondência exata com os temas da versão; sem correspondência, informa que não existe proposta e permite mudar a seleção. Quando existir mais de uma ficha compatível, o adulto pode escolher a alternativa. A dimensão é calculada pela quantidade de perguntas, e a proposta apresenta as contagens reais de escolha múltipla e respostas abertas. Não promete uma proporção fixa de 70/30 nem inventa uma duração estimada.

A publicação exige temas coerentes com disciplina e ano. JSONB valida os tipos iniciais de perguntas, IDs e opções únicos, limites de perguntas/opções e referência correta da solução. Versões publicadas e as suas associações a temas não podem ser alteradas ou eliminadas; alterações pedagógicas exigem uma nova versão. Conteúdo inclui soluções para uso futuro da correção no servidor. Apenas a pré-visualização do responsável desbloqueada recebe o conteúdo completo.

A atribuição usa clientRequestId, mantém a versão exata e é confirmada pelo servidor. A transação valida novamente o desbloqueio do responsável, pertença familiar e ano escolar, guarda a atribuição e o evento de auditoria. Pedidos repetidos não duplicam a atribuição; a mesma versão não pode ter duas atribuições ativas para a mesma criança. Uma realização futura usará worksheet_attempts, sem criar uma atribuição nova para cada repetição.

A listagem infantil usa o cliente HTTP de sessão infantil, sem JWT adulto. A API valida a sessão opaca e só permite o próprio childId. Devolve título, disciplina, temas, ano, contagens e identificação da versão/atribuição; nunca perguntas, soluções, explicações ou critérios de correção. O card apresenta «Por começar». O início e a gravação de respostas são instalados na etapa abaixo. A entrega e a correção objetiva são instaladas na etapa abaixo; classificação manual das respostas abertas continua pendente.

Rotas sob `/functions/v1/worksheets`: GET `/v1/subjects`, GET `/v1/topics`, GET `/v1/worksheets`, GET `/v1/worksheets/{id}`, POST/GET `/v1/children/{id}/assignments`. Listas são paginadas por cursor; erros seguem code/message/requestId. O contrato está em `supabase/api/worksheets.openapi.yaml`. As tabelas têm RLS e não permitem acesso direto ao Flutter; escritas de atribuição e auditoria são exclusivas da RPC autorizada ao servidor.

Validação manual pelo utilizador: disponibilizar uma ficha para uma criança e conferir que aparece apenas no respetivo perfil; atribuir outra à segunda criança; testar mudança de disciplina/temas e impedir duplicar a mesma versão ativa. Verificar que cinco minutos de inatividade na preparação bloqueiam a área do responsável e impedem a gravação sem novo desbloqueio. Não enviar tokens ou PINs no chat.


## Realizar ficha e guardar progresso — instalação

1. Executar uma vez `supabase/migrations/202611050004_create_attempts_and_answers.sql` depois das migrações anteriores. Cria worksheet_attempts, answers e sync_operations. A chave estrangeira composta garante que a criança e a versão da tentativa são as da atribuição; há no máximo uma tentativa em progresso por atribuição e uma resposta por pergunta/tentativa. Não elimina as fichas ou atribuições existentes.
2. Publicar a função `attempts` com `supabase/functions/attempts/index.ts`, mantendo a verificação de JWT com segredo legado desativada nessa função. Só aceita tokens infantis opacos, validados dentro de cada transação. Não há segredos novos.
3. Atualizar a função `worksheets` com o conteúdo atual de `supabase/functions/worksheets/index.ts`. A lista passa a incluir activeAttemptId, para apresentar «Começar» ou «Continuar». As outras funções mantêm-se.
4. Reiniciar o Flutter. Entrar numa criança, abrir uma ficha, responder e usar Seguinte/Anterior. «Pausar» ou «Guardar e pausar» guardam as respostas antes de regressar ao espaço de estudo. A entrega e a correção automática são instaladas na etapa abaixo.

O aluno vê uma pergunta de cada vez, com opções de escolha múltipla ou resposta aberta. Pode escrever até 5000 caracteres, indicar explicitamente que resolveu no caderno ou deixar sem resposta. A contagem de progresso mede perguntas respondidas, não acertos. Não há feedback de correção, nota ou contagem decrescente. A API constrói o payload por lista de campos permitidos; exclui correctAnswer, explanation, critérios e campos extra das opções. Mantém a ordem e os IDs das perguntas da versão publicada.

As respostas são guardadas no servidor ao navegar ou pausar. Alterações pendentes também são persistidas localmente, por criança e tentativa, para recuperação. A interface distingue progresso confirmado no servidor de alterações existentes apenas neste dispositivo. Uma falha não apresenta a resposta como sincronizada. Pode tentar novamente ou, depois da confirmação de persistência local, escolher pausar com alterações neste dispositivo.

O identificador de início é persistido antes do pedido para permitir repetição após perda da resposta. Cada operação de resposta tem operationId e baseRevision; a operação e a alteração são confirmadas numa única transação. sync_operations é partilhada para início e gravação, sem limpeza automática nesta etapa. Um pedido repetido não cria outra tentativa nem duplica a gravação; um identificador reutilizado com outros dados é rejeitado.

A fila local usa temporariamente shared_preferences para recuperação na Web, não uma implementação completa do Sync Manager previsto. Apenas pendências e posição da pergunta são persistidas; respostas confirmadas saem da fila. Não guarda PINs ou tokens. Não permite abrir fichas novas sem servidor, não sincroniza sem sessão e não faz background sync. Limpar dados do navegador pode perder respostas ainda não confirmadas. O armazenamento Web não é isolamento privado garantido contra quem controla o navegador; o isolamento da API é sempre validado no servidor.

Se outra sessão modificar a mesma resposta, a revisão otimista rejeita a sobrescrita. A resposta local é preservada e a interface oferece «Manter a minha resposta» (nova operação baseada na revisão atual) ou «Usar resposta do servidor». As outras pendências são mantidas. Expiração de sessão exige novo PIN infantil; não descarta pendências. Tentativas submetidas/finalizadas ou atribuições retiradas não aceitam alterações. A consulta de uma tentativa própria retirada permanece disponível para recuperação, sem edição.

As perguntas são renderizadas dentro do modo infantil, sem uma rota independente que permaneça visível após saída, troca de perfil ou desbloqueio do responsável. Ao pedir a área do responsável, a ficha aguarda a persistência local antes de abrir o PIN. Os rascunhos de outra criança não são carregados pela interface.

Rotas sob `/functions/v1/attempts`: POST `/v1/assignments/{id}/attempts`, GET `/v1/attempts/{id}`, PUT `/v1/attempts/{id}/answers/{questionId}`. Os contratos estão em `supabase/api/attempts.openapi.yaml`. As consultas adultas, entrega, resultados, revisão do responsável, novas tentativas após conclusão e sincronização em lote serão implementadas nos seus passos próprios. Ao implementar a repetição, remover ou substituir o identificador local de início de uma tentativa já concluída, em vez de reutilizá-lo.

Validação manual pelo utilizador: responder, navegar, pausar e continuar; sair/entrar e confirmar recuperação; testar resposta escrita, caderno e limpar resposta. Confirmar que o progresso não aparece na outra criança. Para conflito, abrir a mesma criança/ficha em dois navegadores e alterar a mesma pergunta a partir de revisões diferentes. Nenhum teste automático foi executado nesta etapa.


## Entregar ficha e encaminhar revisão do responsável — instalação

1. Executar `supabase/migrations/202611050005_submit_attempts_and_pending_reviews.sql` uma vez após as migrações anteriores. Preserva tentativas e respostas. Acrescenta o tipo submit_attempt à idempotência, cria answer_reviews e answer_review_events conforme o ERD e prepara entrega/consulta por RPC. Não cria classificações fictícias nem modifica as respostas já guardadas.
2. Atualizar a função `attempts` com o conteúdo atual de `supabase/functions/attempts/index.ts`, mantendo a verificação de JWT com segredo legado desativada. Acrescenta POST `/v1/attempts/{id}/submit` e GET `/v1/attempts/{id}/result` ao domínio existente.
3. Atualizar também `worksheets` com `supabase/functions/worksheets/index.ts`, na mesma configuração de JWT. A listagem inclui a tentativa mais recente e o estado; o card passa de «Continuar» para «Ver entrega», sem iniciar automaticamente outra tentativa.
4. Publicar a nova função `reviews` com `supabase/functions/reviews/index.ts`, com verificação de JWT legado desativada. Usa JWT adulto confirmado e autorização do responsável em cada consulta. Não necessita de segredos novos.
5. Reiniciar o Flutter. Na última pergunta, «Terminar ficha» guarda primeiro as pendências e abre uma confirmação com a quantidade de perguntas respondidas. «Confirmar entrega» só mostra sucesso após a resposta do servidor. Respostas em branco são permitidas após confirmação explícita e aparecem no resumo, sem classificação do responsável inventada.

A submissão inclui operationId e expectedRevisions de todas as perguntas. O identificador/intenção é persistido antes do pedido, depois de confirmar todas as gravações anteriores. O servidor bloqueia a tentativa e compara as revisões de cada resposta; se houve alteração noutro dispositivo, rejeita a entrega e pede revisão dos dados atuais. Só depois confirma submittedAt, transição de estado, auditoria e idempotência em conjunto. Uma repetição do mesmo pedido não repete a entrega nem o evento. Após entrega, o RPC de gravação continua a rejeitar alterações.

A correção objetiva é calculada no servidor a partir das respostas congeladas e correctAnswer da versão imutável. Não há tabela de notas globais. O resumo infantil mostra contagens agregadas de escolhas múltiplas e de respostas abertas por rever, sem devolver as soluções. Respostas abertas typed com texto não vazio e paper entram na revisão; ausentes/unanswered/brancas não entram. O estado passa a pending_review se há respostas abertas por classificar e a completed se não há revisão necessária. A classificação manual será implementada no passo seguinte, usando as tabelas já criadas.

Uma falha ou perda da confirmação não aparece como «entregue»: a intenção mantém-se e os campos ficam bloqueados até repetir o mesmo pedido ou consultar o estado do servidor. Reabrir uma tentativa que o servidor já recebeu consulta o resumo real. Rascunhos locais que não entraram numa entrega feita por outra sessão são preservados e podem ser consultados em modo de leitura; não são apagados nem apresentados como parte da entrega. A ficha não é considerada entregue offline só por ter sido terminada localmente.

A área do responsável mostra «Revisões pendentes» agrupadas pela criança e ordenadas pelas entregas mais antigas dentro de cada criança. O endpoint GET `/v1/families/{id}/pending-reviews` está publicado sob `/functions/v1/reviews`, com paginação por cursor de tentativa (ordem criança/data/id). Devolve resumo e perfil mínimo apenas após validar o desbloqueio e a pertença familiar; nenhum endpoint desta etapa permite classificar manualmente. A atualização do painel é explícita ou ocorre ao reabrir a área, sem monitorização periódica.

Validação manual pelo utilizador: entregar uma ficha mista preenchida, conferir contagem das escolhas e pendências abertas, sair/entrar e abrir «Ver entrega», confirmar que as respostas já não mudam; na área do responsável, conferir o resumo pendente para a criança correta. Entregar outra com respostas abertas em branco deve excluir essas perguntas da revisão. Testar perda de ligação na confirmação não pode mostrar sucesso falso. Não foram executados testes automáticos.

## Classificação do responsável de respostas abertas — instalação

1. Executar uma vez `supabase/migrations/202611050006_parent_answer_reviews.sql`, após a migração 005. Preserva fichas, tentativas, respostas e revisões existentes. Acrescenta RPCs de detalhe/classificação/listagem de revisões concluídas e o tipo review_answer à idempotência. As contagens agregadas passam a incluir writtenCorrect/writtenPartial/writtenIncorrect, calculadas a partir das revisões.
2. Publicar a função atualizada com `supabase functions deploy reviews --project-ref hhgxxvvreyhigxynrgmv` na raiz do projeto. Mantém o CORS partilhado e a configuração ALLOWED_ORIGINS; não há segredos novos nem alteração da autenticação. Os outros endpoints de resultados recebem as novas contagens através da função SQL atualizada, sem nova publicação.
3. Reiniciar o Flutter. Área do responsável → Pendentes → Rever respostas. Os cards reutilizáveis mostram pergunta, resposta escrita ou indicação para consultar o caderno. O seletor apresenta Correta, Parcialmente correta e Incorreta, sem pré-selecionar uma classificação. Escolhas múltiplas mostram a correção automática em leitura; respostas abertas em branco não oferecem classificação.

Cada toque no seletor guarda imediatamente no servidor e só atualiza a classificação visível após confirmação. A gravação é uma transação: valida desbloqueio e pertença familiar, bloqueia a tentativa, compara baseRevision (0 para primeira classificação), insere/atualiza a avaliação, regista adulto/data/histórico/auditoria e muda a tentativa para completed quando não restam abertas pendentes. A resposta entregue pela criança permanece congelada. Não cria uma nota global nem pontos/medalhas fictícios. O resumo infantil passa a mostrar contagens das classificações do responsável quando é consultado novamente.

operationId e o conteúdo do pedido mantêm-se em memória enquanto a confirmação é incerta. Falhas não mostram sucesso: pode repetir o mesmo pedido sem duplicar o histórico ou consultar o estado no servidor. Outras classificações ficam bloqueadas durante essa confirmação. Cada gravação devolve também o detalhe atualizado da ficha para alinhar os cards com eventuais decisões de outro adulto. Um conflito com outro adulto exige atualizar e escolher novamente; nunca sobrescreve silenciosamente. Não há fila offline de revisões do responsável nem armazenamento local das respostas consultadas. Se a página for fechada ou o acesso bloquear, a reabertura consulta novamente o servidor.

É possível pausar após qualquer classificação confirmada. A secção Revistas permite reabrir tentativas concluídas e alterar classificações, mantendo histórico. O botão de voltar no fim não executa outra gravação: a última classificação necessária já concluiu a revisão. O conteúdo é integrado no espaço do responsável, sem rota independente; bloqueio por inatividade ou perda de autorização desmonta a página e exige novo PIN. Só adultos com sessão confirmada e desbloqueio válido recebem o detalhe com soluções; o resultado infantil continua agregado.

Rotas da função reviews: GET `/v1/families/{id}/pending-reviews`, GET `/v1/families/{id}/reviewed-attempts`, GET `/v1/attempts/{id}/review`, PUT `/v1/answers/{id}/review`. Contrato em `supabase/api/reviews.openapi.yaml`. Funções internas não são executáveis por clientes e as RPCs de negócio são exclusivas de service_role, com search_path vazio e verificações próprias de autorização. Referência: https://supabase.com/docs/guides/database/functions . As decisões simultâneas são serializadas pelo bloqueio da tentativa: https://www.postgresql.org/docs/current/explicit-locking.html .

Validação manual pelo utilizador: abrir a ficha pendente já entregue; classificar uma resposta, voltar e reabrir para conferir persistência; classificar a última e conferir que sai de Pendentes e aparece em Revistas; alterar uma classificação e reabrir para confirmar; consultar novamente o resultado infantil; conferir que brancas e escolhas múltiplas não aceitam avaliação manual. Em dois navegadores com acesso do responsável, alterar a mesma resposta a partir da mesma revisão deve gerar conflito no segundo. Uma falha de ligação não deve mostrar uma classificação como guardada; repetir a confirmação não duplica o evento. Conferir bloqueio por inatividade e isolamento entre famílias. Não foram executados testes automáticos, análise estática, build nem publicação nesta etapa; a execução fica a cargo do utilizador.

## Acompanhamento por criança — instalação

1. Aplicar o ficheiro `acompanhamento-criancas.patch` preparado para esta etapa, a partir da pasta autorizada do chat. Contém a nova funcionalidade, a migração SQL, a configuração e a documentação. Não cria outro projeto nem altera as respostas existentes. Não iniciar a funcionalidade antes dos passos seguintes.
2. No SQL Editor do Supabase, executar uma vez `supabase/migrations/202611050007_child_progress.sql`, depois da migração 006. Cria duas RPCs de consulta e um índice de paginação; não cria notas, duplica respostas nem altera estados de tentativas.
3. Na raiz do projeto, publicar `supabase functions deploy progress --project-ref hhgxxvvreyhigxynrgmv`. A nova função usa o CORS partilhado e ALLOWED_ORIGINS já existente. `supabase/config.toml` desativa a verificação JWT legada para progress; a função verifica JWT adulto confirmado e cada RPC valida o desbloqueio e pertença à família. Não há segredos novos.
4. Reiniciar o Flutter e, na área do responsável, usar Ver acompanhamento no card de cada criança.

A visão geral distingue atribuições ativas/por começar de realizações em curso, entregas, concluídas, entregas por rever e respostas por rever. Uma atribuição por começar é ativa e ainda não tem nenhuma tentativa em curso ou entregue; tentativas abandonadas não impedem essa contagem. Em curso conta também tentativas preservadas de atribuições retiradas. Resultados por disciplina usam exclusivamente tentativas entregues (submitted, pending_review ou completed): escolhas múltiplas corretas sobre o total de perguntas dessa categoria; abertas corretas/parcialmente corretas/incorretas; abertas pendentes; perguntas em branco. Não soma parcialmente corretas como corretas nem calcula uma nota global. Não pretende medir domínio curricular ou evolução temporal; mostra contagens do histórico disponível.

Os resumos incluem todo o histórico da criança, inclusive entregas de atribuições retiradas. Cada repetição contará como uma realização independente, sem duplicar a atribuição. Disciplinas sem entregas mostram a ausência de resultados, e crianças sem dados recebem estados vazios. Novas classificações do responsável são refletidas ao atualizar ou regressar da consulta de uma entrega, sem polling.

O histórico é paginado no servidor, 50 por página, por startedAt/id decrescentes. Os filtros por disciplina e estado aplicam-se apenas à lista; mudar filtro reinicia cursor e resultados. Carregar mais preserva as entradas anteriores e elimina duplicados. Falhas de paginação mantêm os dados já carregados e permitem repetir. Fichas atribuídas mas nunca iniciadas contam no resumo e não inventam uma tentativa no histórico. Atribuições retiradas têm indicação visível. Todas as entregas, mesmo sem revisão manual necessária, podem ser abertas através da revisão do responsável existente; tentativas não entregues mostram apenas metadados nesta etapa.

A página usa os componentes AppPage/AppCard/AppButton/AppBadge e acrescenta ProgressStatCard, SubjectProgressCard e AttemptHistoryCard. Integra-se no espaço do responsável, sem rota independente. Ao abrir uma entrega a partir do histórico, voltar regressa ao acompanhamento da mesma criança e recarrega resultados. Bloqueio de PIN ou saída desmonta a página e elimina a seleção. Nenhuma resposta, solução ou token é persistido localmente pelo acompanhamento; todas as consultas voltam a validar autorização, incluindo pedidos de páginas seguintes. A API devolve exclusivamente perfil mínimo, metadados e contagens; respostas e soluções continuam no endpoint adulto desbloqueado de revisão.

Rotas da nova função progress: GET `/v1/children/{id}/progress` e GET `/v1/children/{id}/attempts`, com cursor/subjectId/status opcionais só na segunda. Contrato em `supabase/api/progress.openapi.yaml`. As RPCs são exclusivas de service_role, com search_path vazio; Flutter não lê tabelas de negócio diretamente. Os agregados são calculados a partir das tabelas atuais e do resumo de entrega existente, sem armazenar notas derivadas.

Validação manual pelo utilizador: abrir o acompanhamento de cada criança e confirmar isolamento; comparar uma ficha concluída e uma pendente com os resumos; testar disciplina/estado, listas vazias e Atualizar; abrir entrega pelo histórico, alterar uma classificação e voltar ao acompanhamento; confirmar que a pendência desaparece depois da última classificação; conferir que uma ficha nunca iniciada conta em Por começar; validar bloqueio por inatividade. Para mais de 50 realizações, conferir Carregar mais sem duplicados nem omissões numa lista sem alterações simultâneas. Não foram executados testes automáticos, análise estática, build, consultas remotas ou publicação nesta etapa; o utilizador executará a validação. Foi verificada apenas a aplicabilidade do patch ao conteúdo local.

## Repetir fichas concluídas — instalação

1. Aplicar o patch `repetir-fichas.patch` preparado para esta etapa. Inclui Flutter, migração, atualizações de duas Edge Functions e contratos/documentação. Não foi aplicado automaticamente ao repositório porque a pasta está fora das permissões de escrita deste chat.
2. Executar uma vez `supabase/migrations/202611050008_repeat_worksheet_attempts.sql`, depois da migração 007. Acrescenta attempt_number, numera as tentativas existentes por atribuição e ordem started_at/id, e garante números positivos e únicos por atribuição. Preserva todos os IDs, respostas, correções e operações anteriores. Atualiza a função de início e os payloads/resumos, acrescentando uma vista de estado por atribuição, apenas para service_role.
3. Publicar as duas funções atualizadas, na raiz do projeto, com `supabase functions deploy attempts --project-ref hhgxxvvreyhigxynrgmv` e `supabase functions deploy worksheets --project-ref hhgxxvvreyhigxynrgmv`. Não há alterações aos segredos, CORS ou JWT. Os endpoints de revisão/acompanhamento usam os payloads SQL atualizados sem nova publicação.
4. Reiniciar o Flutter. No espaço infantil, uma ficha cuja última tentativa está completed apresenta Fazer outra vez, tanto no card como no resumo. A confirmação explica que as respostas e correções antigas ficam guardadas e que uma tentativa já iniciada noutro dispositivo será retomada. Fichas pending_review não oferecem repetição; primeiro terminar a revisão do responsável. Começar continua a iniciar a primeira realização e Continuar retoma a que está em curso.

A repetição usa POST `/v1/assignments/{id}/attempts`, a atribuição original e a mesma versão imutável. Acrescenta previousAttemptId ao pedido, juntamente com um clientRequestId novo para essa origem concluída. O servidor valida a sessão infantil e a atribuição ativa; bloqueia a atribuição, valida a origem completed e, na ausência de outra tentativa em curso, exige que seja a mais recente. Cria a tentativa com o próximo número e sem copiar respostas/revisões. Não altera nem reabre a tentativa anterior. Se já existir uma em curso, retoma essa realização. A restrição existente de uma tentativa em progresso por atribuição continua em vigor. Sem origem explícita, um pedido inicial desatualizado devolve a realização existente em leitura, sem criar repetições silenciosas.

A identificação de início é persistida antes do pedido, numa chave por criança/atribuição/tentativa de origem, substituindo a utilização da chave inicial nesse novo ciclo. Uma falha ou perda da resposta repete a mesma operação; não gera um identificador novo a cada tentativa de confirmação. O servidor guarda a associação em sync_operations e devolve sempre a mesma realização para essa operação, mesmo se já tiver sido entregue. Dados diferentes com o mesmo identificador são rejeitados. A origem desatualizada sem outra em curso dá REPEAT_STATE_CHANGED e pede regresso à lista. Expiração de sessão exige novo PIN; a listagem atual permite recuperar a tentativa criada, mesmo se a confirmação não chegou ao dispositivo.

Respostas pendentes e intenção de entrega continuam em chaves por childId/attemptId. Um novo controller é criado para a repetição, com pergunta inicial e sem carregar o rascunho da realização anterior. Pendências antigas não são apagadas. A gravação, revisão otimista, entrega, correção automática e revisão do responsável reutilizam os mesmos fluxos, sempre associados ao novo ID. Se o pedido retomar uma tentativa existente com respostas, a interface informa que já havia progresso guardado. A confirmação está embutida no modo infantil, sem rota independente que permaneça visível após expiração de sessão ou troca de perfil.

Tentativa 1/2/3 aparece na realização, no resultado, nos cards infantis, nas listas de revisão e no histórico do responsável. Cada entrega conta separadamente no acompanhamento por disciplina e mantém as suas classificações. Não duplica a atribuição, não altera o catálogo e não guarda nota global. A auditoria regista attempt.started ou attempt.repeated apenas quando uma nova tentativa é criada, com a origem da repetição, sem respostas, PINs ou tokens. A vista assignment_attempt_state devolve no máximo uma linha por atribuição para evitar que um histórico longo esgote o limite de linhas da consulta de estado infantil.

A instalação SQL vem antes da publicação: a função anterior continua compatível com o parâmetro SQL final opcional durante a transição; a função worksheets atualizada precisa da vista criada pela migração. Os contratos atualizados estão em `supabase/api/attempts.openapi.yaml`, `worksheets.openapi.yaml`, `reviews.openapi.yaml` e `progress.openapi.yaml`. As novas propriedades attemptNumber/latestAttemptNumber têm fallback nos modelos para dados anteriores à publicação. Não é possível escolher o número da tentativa pelo cliente. Funções internas de payload continuam sem execução direta por anon/authenticated/service_role; apenas as RPCs de negócio são executáveis por service_role.

Validação manual pelo utilizador: abrir uma ficha completed, escolher Fazer outra vez e cancelar (não deve criar realização); confirmar e conferir Tentativa 2 com respostas vazias; responder, pausar e continuar; entregar e corrigir; conferir Tentativas 1 e 2 no histórico com as respetivas respostas/classificações; confirmar as contagens agregadas e repetir novamente para Tentativa 3. Conferir que pending_review não permite repetição, que outra criança não vê a realização e que uma atribuição retirada impede novo início. Em dois navegadores da mesma criança, pedir repetição da mesma ficha deve resultar numa única tentativa em curso; o segundo retoma a existente. Perda da resposta de início seguida de repetição do pedido não pode criar outra tentativa. Não foram executados testes automáticos, análise estática, build nem publicação nesta etapa; o utilizador fará a validação. Só foi verificada a aplicabilidade do patch ao conteúdo local.

## Correção detalhada no espaço infantil — instalação

1. Aplicar o patch `correcao-infantil.patch` preparado nesta etapa. Acrescenta componentes de leitura, o endpoint de correção e metadados para consultar a última tentativa concluída, mesmo quando há outra em curso.
2. Executar uma vez `supabase/migrations/202611050009_child_attempt_feedback.sql`, depois da migração 008. Cria a RPC de consulta de correção e acrescenta duas colunas à vista de estado das atribuições; não altera respostas, classificações, tentativas ou números existentes.
3. Publicar as funções atualizadas attempts e worksheets, cada uma com `supabase functions deploy NOME --project-ref hhgxxvvreyhigxynrgmv`. A configuração de CORS/JWT e os segredos mantêm-se. A migração deve anteceder a publicação.
4. Reiniciar o Flutter. No resumo de uma tentativa completed, usar Ver a correção. No card da ficha no espaço infantil aparece Ver correção da tentativa N, relativo à realização completed mais recente; continua disponível enquanto a criança responde a uma repetição. Não interrompe nem apaga o progresso dessa repetição.

A nova página mostra o enunciado, a resposta entregue e a classificação por pergunta. Em escolhas múltiplas incorretas ou em branco, apresenta também o texto da opção correta e a explicação publicada, caso exista. Em respostas abertas, apresenta apenas a resposta escrita ou indicação de caderno e a classificação atual dos responsáveis: correta, parcialmente correta ou incorreta. Não inventa uma resposta-modelo ou explicação para abertas; sugere conversar com os responsáveis quando há algo a melhorar. Perguntas sem resposta têm essa indicação e não são apresentadas como classificadas pelos responsáveis.

Enquanto a revisão está pendente, Atualizar resultado permite consultar novamente o resumo e disponibilizar a correção assim que estiver concluída. O filtro inicial O que posso melhorar inclui incorretas, parcialmente corretas e perguntas sem resposta; Todas as respostas permite consultar também as corretas. A existência de todas as respostas corretas tem estado positivo explícito, sem uma lista vazia ambígua. Contexto de leitura/instruções pode ser reaberto na mesma página. Atualizar correção consulta novamente o servidor, para refletir alterações do responsável posteriores. Não há edição ou nova submissão nesta página e a correção não é persistida localmente.

GET `/v1/attempts/{id}/feedback`, na função attempts, valida novamente a sessão opaca e titularidade no servidor. Só devolve detalhes se status=completed. In_progress, submitted e pending_review devolvem 409 FEEDBACK_NOT_AVAILABLE; outro perfil devolve ATTEMPT_NOT_FOUND. O servidor constrói um payload por campos permitidos, sem identidade do adulto, PINs, tokens, histórico de revisões ou rubricas/critério privado. A resposta correta e a explicação publicada de escolha múltipla são uma nova exposição deliberada exclusivamente nesta consulta de aprendizagem após conclusão. Os payloads normais de começo/continuação/perguntas/resumo e a listagem infantil continuam sem soluções. Ver o resultado de uma realização anterior concluída durante uma repetição é permitido para aprendizagem e não altera a versão da ficha.

Os componentes ChildFeedbackPage e ChildFeedbackCard ficam dentro do modo infantil existente, sem uma rota que permaneça aberta depois da saída ou troca de perfil. A expiração da sessão desmonta a correção e exige novo PIN. Abrir a área do responsável mantém a proteção do PIN. A consulta usa o cliente HTTP infantil, sem JWT adulto ou acesso direto do Flutter às tabelas. A RPC é exclusiva de service_role, com search_path vazio e autorização própria. A vista assignment_attempt_state continua acessível apenas ao servidor e acrescenta latest_completed_attempt_id/number; o endpoint de fichas expõe apenas os respetivos metadados.

Validação manual pelo utilizador: consultar a tentativa concluída já existente com erros; comparar a resposta escolhida e a opção correta; conferir a classificação de uma aberta escrita e de uma feita no caderno; testar os dois filtros e o caso de todas corretas; verificar que uma pergunta em branco aparece como Sem resposta. Começar ou continuar outra tentativa e consultar a correção anterior pelo card, regressando depois ao progresso guardado. Uma tentativa ainda por rever não deve oferecer a sua correção detalhada; a RPC também deve rejeitar uma chamada direta a esse ID. Conferir isolamento entre crianças, expiração de sessão e atualização após alteração do responsável. Não foram executados testes automáticos, análise estática, build, consultas remotas ou publicação nesta etapa; só foi verificada a aplicabilidade do patch ao conteúdo local. Não foram feitos commits.

## Edição do perfil infantil — instalação

1. No SQL Editor do Supabase, executar uma vez `supabase/migrations/202611060004_update_child_profile.sql`. Cria a RPC `update_child_profile`, exclusiva de service_role, com search_path vazio. Se a RPC já tinha sido criada antes, executar também `supabase/migrations/202611060005_fix_update_child_profile_changed_fields.sql`, que corrige a falha ao gravar alterações (`STORAGE_UNAVAILABLE`).
2. Republicar a função famílias: `supabase functions deploy families --project-ref hhgxxvvreyhigxynrgmv`. Passa a aceitar `PUT /v1/families/{id}/children/{childId}` (CORS inclui PUT). Usa o `CHILD_PIN_PEPPER` existente; não há segredos novos.
3. Na área do responsável, separador Família, usar «Editar perfil» no card da criança.

O adulto pode alterar a alcunha, o avatar e o ano escolar. O PIN mantém-se por omissão; «Alterar PIN» pede o novo código duas vezes. Com novo PIN, as sessões infantis ativas são revogadas, o bloqueio de tentativas é limpo e a criança entra com o novo código. A auditoria (`child.updated`) regista apenas os nomes dos campos alterados, nunca o PIN. Exige área do responsável desbloqueada e pertença ativa à família. Contrato em `supabase/api/families.openapi.yaml`. Alterar o ano escolar não altera fichas já atribuídas nem o histórico.
