# Escola em dia

> **Versão Flutter:** o novo front-end está em `flutter_app/`. Consulta `flutter_app/README.md` para executar no navegador. Os ficheiros React foram preservados; ambas as versões usam os mesmos exercícios JSON e o servidor Node. O progresso de cada versão é independente.


Aplicação local React em português europeu, com servidor Node e exercícios guardados em ficheiros JSON. Inclui compreensão oral e escrita, dicionário, sílabas, sílaba tónica, onomatopeias, formação e família de palavras, expressão escrita e Estudo do Meio (São Martinho, 11 de novembro).

## Executar

Requisitos: Node.js 20.19+ ou 22.12+ e npm.

Na pasta deste projeto:

```sh
npm install
npm run dev
```

Abre **http://localhost:5173**. Mantém o terminal aberto. Para parar, carrega em Ctrl+C. São usadas as portas 5173 (React) e 3001 (servidor). Se estiverem ocupadas, encerra os processos anteriores antes de iniciar.

Para executar a versão compilada:

```sh
npm run build
npm start
```

Abre **http://localhost:3001**. O servidor está limitado ao computador local. Não é necessário publicar o site nem configurar uma base de dados. A aplicação usa fontes Google quando existe ligação à Internet; tem fontes alternativas locais. A instalação inicial requer Internet.

## Utilizar

1. Escolhe uma matéria no menu lateral (Português, Estudo do Meio ou Todas as matérias), seleciona um tema ou pesquisa um exercício. Em ecrãs pequenos, o menu aparece acima da lista.
2. Responde às perguntas e carrega em **Validar respostas**. As perguntas de escolha múltipla são comparadas com `correctAnswer`; perguntas sem resposta recebem feedback específico. As respostas escritas ficam para revisão com um adulto.
3. Altera as respostas e volta a validar, ou escolhe **Recomeçar este exercício**.
4. Em compreensão oral, escolhe **Ouvir texto**. A leitura utiliza a síntese de voz do navegador (`pt-PT`), cuja disponibilidade e pronúncia dependem do sistema. Existe uma transcrição alternativa.
5. Em **Adicionar exercício**, cola ou edita o JSON e carrega em **Guardar exercício**. O servidor verifica a estrutura e cria o ficheiro `data/exercises/<id>.json`. Um id existente não é sobrescrito.
6. **Exportar JSON** descarrega uma cópia do exercício, incluindo respostas corretas.

Os exercícios ficam no disco, na pasta `data/exercises/`, e continuam disponíveis depois de reiniciar. Para cópia de segurança, copia essa pasta. Podes editar os ficheiros diretamente com o servidor parado; ao reiniciar ou recarregar a página, são lidos novamente. Um ficheiro inválido impede o carregamento da lista e deve ser corrigido.

As respostas do aluno e o estado de validação ficam apenas no `localStorage` deste navegador e endereço. Não são gravados nos ficheiros dos exercícios. Limpar os dados do navegador apaga o progresso. Os endereços de desenvolvimento e produção têm progresso independente. Não existe autenticação, separação de alunos nem proteção das soluções: é uma ferramenta local de estudo e autocorreção.

## Formato JSON

```json
{
  "id": "silabas-exemplo",
  "title": "À descoberta das sílabas",
  "subject": "Português",
  "topic": "Sílabas",
  "instructions": "Lê e responde.",
  "questions": [
    {
      "id": "q1",
      "type": "multiple-choice",
      "prompt": "Quantas sílabas tem a palavra castanha?",
      "options": [
        { "id": "a", "text": "Duas" },
        { "id": "b", "text": "Três" }
      ],
      "correctAnswer": "b",
      "explanation": "cas-ta-nha: três sílabas."
    },
    {
      "id": "q2",
      "type": "written",
      "prompt": "Escreve uma frase com a palavra castanha.",
      "explanation": "Revê a letra maiúscula, a pontuação e o sentido da frase com um adulto."
    }
  ]
}
```

`id`, `title`, `topic` e `questions` são obrigatórios. O id do exercício aceita até 80 letras minúsculas sem acentos, números e hífens, começando por letra ou número. Cada pergunta tem um id único, um prompt e um dos tipos indicados acima. As opções usam ids únicos dentro da pergunta; `correctAnswer` contém o id exato de uma opção. Há uma única resposta correta por pergunta de escolha múltipla. São aceites 1–50 perguntas e 2–8 opções por pergunta.

`instructions`, `text` (texto de leitura), `audioText` (texto para síntese de voz) e `explanation` são opcionais. O limite por submissão é de 256 KB. Não são suportados comentários, vírgulas finais ou blocos Markdown dentro do JSON.

## Estrutura

```text
src/                 Interface React e estilos
server/index.mjs     Servidor HTTP, API e ficheiros locais
server/schema.mjs    Validação do JSON, partilhada com a interface
data/exercises/      Exercícios de exemplo e novos exercícios
scripts/dev.mjs      Arranque conjunto do servidor e Vite
```

API local: `GET /api/exercises` lista os exercícios; `POST /api/exercises` cria um ficheiro exclusivo. O servidor não oferece operações de eliminação ou sobrescrita pela API.

## Matérias no menu lateral

O campo opcional `subject` indica a matéria (por exemplo, `"Português"`, `"Estudo do Meio"` ou `"Matemática"`). Uma matéria nova aparece automaticamente no menu ao guardar um exercício. O campo `topic` indica o tema dentro dessa matéria. Nos JSON antigos sem `subject`, os temas de língua incluídos são agrupados em Português e o tema Estudo do Meio na respetiva matéria; temas desconhecidos aparecem em Outras matérias. Os filtros e a pesquisa combinam-se com a matéria selecionada.

## Telas e sessões por matéria

A tela inicial apresenta a lista de exercícios, organizada por matéria e tema. Ao selecionar um exercício, abre-se uma tela dedicada, com botões para voltar à lista e avançar para o próximo exercício da mesma matéria.

Para começar a contar resultados, seleciona uma matéria no menu e carrega em **Iniciar sessão**. Existe uma sessão independente por matéria: podes alternar entre Português e Estudo do Meio sem misturar resultados. Iniciar uma sessão começa com respostas vazias, sem importar as tentativas do estudo livre.

- **Certo:** todas as perguntas de escolha múltipla estão corretas e não há respostas escritas por rever.
- **Errado:** pelo menos uma resposta de escolha múltipla está errada ou por responder.
- **Para rever:** as perguntas de escolha múltipla estão corretas (ou não existem) e há perguntas escritas. Um adulto pode classificar o exercício completo como certo ou errado após rever a escrita. Para marcar como certo, as escolhas múltiplas têm de estar corretas.

Cada exercício conta uma vez por sessão; a última validação substitui o resultado anterior. Editar ou limpar respostas não altera a contagem até validar novamente. As contagens medem exercícios completos, não perguntas individuais.

**Terminar sessão** mantém o resumo guardado. **Nova sessão · zerar contagem** substitui apenas a sessão dessa matéria e começa do zero. Sessões e respetivas respostas persistem no navegador, em separado do estudo livre. Limpar os dados do navegador apaga estas informações. As sessões não alteram os ficheiros JSON.

Para verificar a lógica de classificação e contagem:

```sh
node --test src/sessions.test.mjs
```

O botão hamburger (☰) no cabeçalho abre e fecha o menu lateral global, disponível em todas as telas. O menu inclui Home e as matérias. Em computadores, o conteúdo ajusta-se à largura do menu; em telemóveis, o menu abre sobre o conteúdo e fecha ao escolher uma página, clicar fora ou premir Escape. A preferência de abertura fica guardada no navegador.

## Navegação global e relatórios por matéria

A **Home** apresenta uma introdução e os cartões das matérias. Seleciona uma matéria pelo cartão ou pelo menu hamburger no cabeçalho para abrir a sua página.

Cada matéria tem a sua lista de exercícios, pesquisa e filtro por tema, botão **Iniciar sessão** e **Relatório de execução**. O relatório mostra os totais de exercícios certos, errados e para rever, além da lista de exercícios validados com o respetivo resultado. O botão Abrir permite regressar ao exercício. As matérias mantêm sessões independentes; a Home não agrega os relatórios de execução.

A tela do exercício mantém o menu global e o botão de regresso à matéria. A contagem é atualizada ao validar e pode ser consultada no relatório da matéria.

## Animações ao validar

Ao validar um exercício, uma percentagem de acertos nas perguntas de escolha múltipla de **70% ou mais** apresenta uma estrela animada, confettis e uma mensagem de celebração. Abaixo de 70%, aparece uma planta a crescer com uma mensagem de incentivo. Perguntas por responder contam como incorretas neste cálculo. A percentagem apresentada é truncada à unidade para não mostrar 70% quando o resultado real está abaixo do limiar.

Exercícios apenas de escrita mostram uma mensagem de dedicação e revisão, sem nota automática. Nos exercícios mistos, a percentagem refere-se exclusivamente à escolha múltipla. Esta celebração não altera a classificação do exercício na sessão, que continua a exigir todas as escolhas corretas e a revisão da escrita.

As animações repetem-se em cada validação, terminam em poucos segundos e respeitam a preferência de movimento reduzido do dispositivo. Não utilizam som.
