# Escola em dia · Flutter

Front-end Flutter para Web, com código partilhado preparado para Android e iOS. O servidor Node e os exercícios JSON continuam em `../server/` e `../data/exercises/`. A versão React foi preservada.

## Executar no navegador

Requisitos: Flutter instalado, Chrome e Node.js. A primeira instalação dos pacotes requer acesso à Internet.

**Terminal 1 — servidor dos exercícios:**

```sh
cd /Users/viniciushorta/Documents/Projetos/escola-em-dia
node server/index.mjs
```

Se já existe um servidor nesta porta, para-o antes de iniciar este, para carregar a nova configuração da API.

**Terminal 2 — aplicação Flutter:**

```sh
cd /Users/viniciushorta/Documents/Projetos/escola-em-dia/flutter_app
flutter pub get
flutter run -d chrome --web-port=8080 --dart-define=API_BASE_URL=http://localhost:3001
```

O Flutter abre o Chrome. Mantém os dois terminais em execução. Usa `r` no terminal Flutter para atualizar a aplicação e `q` para sair. O servidor aceita as origens locais das portas 8080 (Flutter) e 5173 (React). Usa a porta 8080 para evitar problemas de acesso à API e manter o progresso no mesmo endereço.

## Funcionalidades

- Home com cartões das matérias e menu hamburger global, adaptado a telemóveis e computadores.
- Lista com pesquisa e temas dentro de cada matéria; exercício numa tela separada.
- Editor JSON com validação e gravação pelo servidor no ficheiro `data/exercises/<id>.json`. O formato existente mantém-se, incluindo as respostas corretas.
- Exportação de JSON por partilha ou download, conforme o dispositivo; consulta e cópia do JSON como alternativa.
- Compreensão oral com leitura em voz alta e transcrição. As vozes dependem do sistema e do navegador. Exercícios da matéria Inglês usam voz `en-GB`; os restantes usam `pt-PT`.
- Sessão independente por matéria, com certos, errados, respostas para rever e relatório por exercício.
- Revalidar substitui o resultado anterior, sem duplicar contagens. Terminar mantém o relatório; uma nova sessão dessa matéria começa do zero.
- Perguntas escritas exigem revisão por um adulto. Um exercício só fica certo na sessão se todas as escolhas estiverem corretas e a escrita tiver sido revista.
- Celebração animada a partir de 70% de acertos nas escolhas múltiplas, incentivo abaixo desse limiar e mensagem sem nota para exercícios só de escrita. As animações respeitam a preferência de movimento reduzido.

Os exercícios são guardados em ficheiros pelo Node. Respostas e sessões são guardadas localmente no navegador/dispositivo, através de `shared_preferences`. São dados independentes da versão React; não há importação automática do progresso antigo. Limpar os dados locais apaga o progresso. Não há sincronização entre dispositivos nem contas de alunos.

## Verificar e compilar

```sh
flutter analyze
flutter test
flutter build web --dart-define=API_BASE_URL=http://localhost:3001
```

Depois de compilar, podes servir o Flutter pelo próprio Node. Para o servidor anterior e, na pasta `escola-em-dia`, executa:

```sh
WEB_DIRECTORY=flutter_app/build/web node server/index.mjs
```

Abre http://localhost:3001. Sem `WEB_DIRECTORY`, o servidor continua a servir a compilação React, quando existe. Este projeto destina-se a execução local; para alojamento remoto, configura uma API acessível por HTTPS.

## Android e iOS: etapa futura

O código Dart evita APIs exclusivas do navegador. As pastas nativas ainda não foram geradas nem compiladas nesta entrega. Quando fores preparar os apps, executa na pasta `flutter_app`:

```sh
flutter create --empty --platforms=android,ios --org pt.escolaemdia --project-name escola_em_dia .
flutter pub get
flutter devices
```

Não uses `--overwrite`: os ficheiros Dart existentes devem ser mantidos. Depois verifica as configurações dos projetos gerados e as instruções dos plugins, em particular `flutter_tts` e `share_plus`.

Para um emulador Android, o endereço do computador é normalmente `10.0.2.2`:

```sh
flutter run -d ID_DO_EMULADOR --dart-define=API_BASE_URL=http://10.0.2.2:3001
```

O Android precisa da permissão INTERNET e, apenas para desenvolvimento com este servidor HTTP local, de uma configuração de tráfego HTTP na variante de debug. O iOS precisa das configurações de rede local apropriadas ao simulador/dispositivo. Em produção, utiliza HTTPS. A compilação iOS exige macOS e Xcode. Os apps continuam a depender da API Node; o servidor não é incorporado na aplicação.

O Node mantém-se limitado a `127.0.0.1`. Um telemóvel físico não consegue aceder ao localhost do computador: a disponibilização do servidor na rede e o respetivo controlo de acesso devem ser tratados na etapa mobile. Não uses `localhost` como API num dispositivo físico esperando que aponte para o computador.

## Ficheiros

```text
lib/main.dart                       Telas, navegação, editor JSON, áudio e exportação
lib/models/exercise.dart            Modelo e validação do formato existente
lib/services/exercise_api.dart      Cliente HTTP; API_BASE_URL configurável
lib/services/school_state.dart      Sessões, respostas e persistência local
lib/widgets/validation_banner.dart  Animações de celebração e incentivo
test/                              Testes de classificação e sessões
web/                               Entrada da aplicação Web
```

As dependências estão declaradas no pubspec; o `pubspec.lock` será gerado por `flutter pub get`. Esta etapa criou e verificou a sintaxe dos ficheiros Dart, mas não executou a resolução de pacotes, os testes Flutter ou a compilação Flutter. Os comandos acima fazem essas verificações no teu ambiente.
