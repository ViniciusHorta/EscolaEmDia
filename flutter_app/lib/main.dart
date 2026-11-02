import 'dart:convert';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/exercise.dart';
import 'services/exercise_api.dart';
import 'services/school_state.dart';
import 'widgets/validation_banner.dart';

const green = Color(0xff236453);
const resultLabels = {
  'correct': 'Certo',
  'wrong': 'Errado',
  'review': 'Para rever',
};
const exampleJson = {
  'id': 'novo-exercicio',
  'title': 'À descoberta das palavras',
  'subject': 'Português',
  'topic': 'Sílabas',
  'instructions': 'Lê com atenção e responde.',
  'questions': [
    {
      'id': 'q1',
      'type': 'multiple-choice',
      'prompt': 'Quantas sílabas tem a palavra «castanha»?',
      'options': [
        {'id': 'a', 'text': 'Duas'},
        {'id': 'b', 'text': 'Três'},
        {'id': 'c', 'text': 'Quatro'},
      ],
      'correctAnswer': 'b',
      'explanation': 'cas-ta-nha: três sílabas.',
    },
  ],
};

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SharedPreferences? preferences;
  try {
    preferences = await SharedPreferences.getInstance();
  } catch (_) {
    /* Modo em memória. */
  }
  runApp(
    SchoolApp(
      state: SchoolState(api: ExerciseApi(), preferences: preferences),
    ),
  );
}

class SchoolApp extends StatelessWidget {
  const SchoolApp({super.key, required this.state});
  final SchoolState state;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Escola em dia',
    debugShowCheckedModeBanner: false,
    locale: const Locale('pt', 'PT'),
    supportedLocales: const [Locale('pt', 'PT')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: green),
      scaffoldBackgroundColor: const Color(0xfff8f9f5),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xfffcfcf8),
        foregroundColor: green,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: green,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
        ),
      ),
    ),
    home: SchoolShell(state: state),
  );
}

class SchoolShell extends StatefulWidget {
  const SchoolShell({super.key, required this.state});
  final SchoolState state;
  @override
  State<SchoolShell> createState() => _SchoolShellState();
}

class _SchoolShellState extends State<SchoolShell> {
  SchoolState get school => widget.state;
  final scaffold = GlobalKey<ScaffoldState>();
  final scroll = ScrollController();
  final validationAnchor = GlobalKey();
  final tts = FlutterTts();
  String? subject;
  Exercise? exercise;
  String topic = 'Todos os temas';
  String query = '';
  bool wideNavOpen = true;
  bool speaking = false;
  int validationAttempt = 0;
  bool showAnimation = false;
  int answerRevision = 0;

  @override
  void initState() {
    super.initState();
    school.load();
    tts.setCompletionHandler(() {
      if (mounted) setState(() => speaking = false);
    });
    tts.setCancelHandler(() {
      if (mounted) setState(() => speaking = false);
    });
    tts.setErrorHandler((message) {
      if (mounted) {
        setState(() => speaking = false);
        tell('Não foi possível ler o texto. Podes usar a transcrição.');
      }
    });
  }

  @override
  void dispose() {
    tts.stop();
    scroll.dispose();
    super.dispose();
  }

  void tell(String message) {
    if (mounted)
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
  }

  void go(String? name, {Exercise? selected}) {
    tts.stop();
    setState(() {
      subject = name;
      exercise = selected;
      topic = 'Todos os temas';
      query = '';
      speaking = false;
      showAnimation = false;
      answerRevision++;
    });
    if (scaffold.currentState?.isDrawerOpen == true)
      Navigator.of(context).pop();
    if (scroll.hasClients) scroll.jumpTo(0);
  }

  Future<void> speak(Exercise item) async {
    try {
      if (speaking) {
        await tts.stop();
        if (mounted) setState(() => speaking = false);
        return;
      }
      await tts.setLanguage(item.subject == 'Inglês' ? 'en-GB' : 'pt-PT');
      await tts.setSpeechRate(0.45);
      if (!mounted) return;
      setState(() => speaking = true);
      await tts.speak(item.audioText);
    } catch (_) {
      if (mounted) setState(() => speaking = false);
      tell('Leitura em voz alta indisponível. Usa a transcrição.');
    }
  }

  Future<void> export(Exercise item, BuildContext buttonContext) async {
    try {
      final box = buttonContext.findRenderObject() as RenderBox?;
      await Share.shareXFiles(
        [
          XFile.fromData(
            utf8.encode(const JsonEncoder.withIndent('  ').convert(item.json)),
            mimeType: 'application/json',
            name: '${item.id}.json',
          ),
        ],
        fileNameOverrides: ['${item.id}.json'],
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      );
    } catch (_) {
      tell(
        'Não foi possível exportar. Podes copiar o JSON no editor de consulta.',
      );
      showJson(item);
    }
  }

  Future<void> showJson(Exercise item) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('JSON · ${item.title}'),
        content: SizedBox(
          width: 650,
          child: SingleChildScrollView(
            child: SelectableText(
              const JsonEncoder.withIndent('  ').convert(item.json),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(
                  text: const JsonEncoder.withIndent('  ').convert(item.json),
                ),
              );
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Copiar JSON'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  Future<void> addExercise() async {
    final created = await showDialog<Exercise>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ExerciseEditor(school: school, initialSubject: subject),
    );
    if (created != null && mounted) {
      go(created.subject);
      tell('Exercício guardado em ${created.id}.json.');
    }
  }

  Widget heading(String eyebrow, String title, [String? description]) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        eyebrow.toUpperCase(),
        style: const TextStyle(
          fontSize: 10,
          color: Color(0xff819175),
          letterSpacing: 1.5,
          fontWeight: FontWeight.bold,
        ),
      ),
      const SizedBox(height: 10),
      Semantics(
        header: true,
        child: Text(
          title,
          style: Theme.of(context).textTheme.headlineMedium
              ?.copyWith(color: green, fontWeight: FontWeight.bold),
        ),
      ),
      if (description != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(
            description,
            style: const TextStyle(color: Color(0xff718366), height: 1.7),
          ),
        ),
    ],
  );
  Widget panel(Widget child, {Color color = Colors.white}) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 20),
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: color,
      border: Border.all(color: const Color(0xffe0e5dc)),
      borderRadius: BorderRadius.circular(16),
    ),
    child: child,
  );
  IconData subjectIcon(String value) => value == 'Português'
      ? Icons.menu_book_rounded
      : value == 'Estudo do Meio'
      ? Icons.eco_outlined
      : value == 'Inglês'
      ? Icons.translate_rounded
      : Icons.auto_stories_outlined;

  Widget navigation() => SafeArea(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 28, 24, 16),
          child: Text(
            'O TEU ESPAÇO',
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 1.5,
              color: Color(0xff819175),
            ),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.home_outlined),
          title: const Text('Home'),
          selected: subject == null,
          selectedColor: green,
          selectedTileColor: const Color(0xffdfe9d8),
          onTap: () => go(null),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 28, 24, 12),
          child: Text(
            'MATÉRIAS',
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 1.5,
              color: Color(0xff819175),
            ),
          ),
        ),
        Expanded(
          child: ListView(
            children: school.subjects
                .map(
                  (name) => ListTile(
                    leading: Icon(subjectIcon(name)),
                    title: Text(name),
                    trailing: Text(
                      '${school.forSubject(name).length}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    selected: subject == name,
                    selectedColor: green,
                    selectedTileColor: const Color(0xffdfe9d8),
                    onTap: () => go(name),
                  ),
                )
                .toList(),
          ),
        ),
        const Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Cada matéria tem a sua sessão e o seu relatório.',
            style: TextStyle(
              fontSize: 12,
              height: 1.8,
              color: Color(0xff819175),
            ),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: school,
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1100;
        return Scaffold(
          key: scaffold,
          appBar: AppBar(
            automaticallyImplyLeading: false,
            leading: IconButton(
              tooltip: wide && wideNavOpen ? 'Fechar menu' : 'Abrir menu',
              icon: const Icon(Icons.menu),
              onPressed: () {
                if (wide)
                  setState(() => wideNavOpen = !wideNavOpen);
                else
                  scaffold.currentState?.openDrawer();
              },
            ),
            title: InkWell(
              onTap: () => go(null),
              child: const Text(
                '✦ escola em dia.',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            actions: [
              if (constraints.maxWidth > 650)
                Padding(
                  padding: const EdgeInsets.only(right: 24),
                  child: Center(
                    child: Text(
                      subject ?? 'Home',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ),
            ],
          ),
          drawer: wide
              ? null
              : Drawer(
                  backgroundColor: const Color(0xfff0f3e9),
                  child: navigation(),
                ),
          body: Row(
            children: [
              if (wide && wideNavOpen)
                Container(
                  width: 250,
                  color: const Color(0xfff0f3e9),
                  child: navigation(),
                ),
              Expanded(
                child: SingleChildScrollView(
                  controller: scroll,
                  padding: EdgeInsets.all(constraints.maxWidth < 650 ? 18 : 36),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1120),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (school.loading) const LinearProgressIndicator(),
                          if (school.error != null)
                            panel(
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(school.error!),
                                  const SizedBox(height: 12),
                                  OutlinedButton(
                                    onPressed: school.load,
                                    child: const Text('Tentar novamente'),
                                  ),
                                ],
                              ),
                              color: const Color(0xfffff0ec),
                            ),
                          if (school.persistenceError != null)
                            panel(
                              Text(school.persistenceError!),
                              color: const Color(0xfffff4df),
                            ),
                          if (subject == null)
                            home()
                          else if (exercise == null)
                            subjectPage(subject!)
                          else
                            exercisePage(exercise!),
                          const SizedBox(height: 30),
                          const Divider(),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 18),
                            child: Text(
                              'escola em dia. · Feito para mentes curiosas.\nExercícios em ficheiros locais · Progresso neste dispositivo',
                              style: TextStyle(
                                fontSize: 11,
                                height: 1.8,
                                color: Color(0xff819175),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );

  Widget home() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 18),
      heading(
        'Pequenas descobertas, todos os dias',
        'Aprender é uma\ngrande aventura.',
        'Um pouco de leitura, palavras e mundo à tua volta. Escolhe uma matéria e dá o próximo passo.',
      ),
      const SizedBox(height: 24),
      FilledButton.icon(
        onPressed: addExercise,
        icon: const Icon(Icons.add),
        label: const Text('Adicionar exercício'),
      ),
      const SizedBox(height: 32),
      panel(
        Wrap(
          spacing: 40,
          runSpacing: 20,
          children: [
            metric('${school.exercises.length}', 'exercícios'),
            metric('${school.subjects.length}', 'matérias'),
            metric(
              '${school.exercises.map((e) => e.topic).toSet().length}',
              'temas',
            ),
          ],
        ),
        color: const Color(0xffeef1e7),
      ),
      const SizedBox(height: 10),
      heading('Por onde vamos começar?', 'As tuas matérias'),
      const SizedBox(height: 24),
      LayoutBuilder(
        builder: (context, box) => Wrap(
          spacing: 18,
          runSpacing: 18,
          children: school.subjects
              .map(
                (name) => SizedBox(
                  width: box.maxWidth < 600
                      ? box.maxWidth
                      : (box.maxWidth - 18) / 2,
                  child: Card(
                    color: Colors.white,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => go(name),
                      child: Padding(
                        padding: const EdgeInsets.all(26),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(subjectIcon(name), size: 38, color: green),
                            const SizedBox(height: 18),
                            Text(
                              name,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              '${school.forSubject(name).length} exercícios · Explorar matéria →',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
      ),
      if (!school.loading && school.error == null && school.exercises.isEmpty)
        const Text('Adiciona o primeiro exercício para começar.'),
    ],
  );
  Widget metric(String value, String label) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        value,
        style: const TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.bold,
          color: green,
        ),
      ),
      const SizedBox(height: 5),
      Text(
        label,
        style: const TextStyle(fontSize: 12, color: Color(0xff718366)),
      ),
    ],
  );

  Widget subjectPage(String name) {
    final items = school.forSubject(name);
    final session = school.sessions[name];
    final counts = school.counts(name);
    final topics = ['Todos os temas', ...items.map((e) => e.topic).toSet()];
    final visible = items
        .where(
          (e) =>
              (topic == 'Todos os temas' || e.topic == topic) &&
              '${e.title} ${e.topic}'.toLowerCase().contains(
                query.toLowerCase(),
              ),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        heading(
          'A tua matéria',
          name,
          'Explora os exercícios e acompanha a tua aprendizagem.',
        ),
        const SizedBox(height: 18),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: addExercise,
            icon: const Icon(Icons.add),
            label: const Text('Adicionar exercício'),
          ),
        ),
        const SizedBox(height: 24),
        panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              heading(
                session?.active == true
                    ? 'Sessão em curso'
                    : 'Pronto para começar?',
                'A tua sessão',
                session?.active == true
                    ? 'Cada exercício conta uma vez. Revalidar atualiza o resultado anterior.'
                    : 'Começa uma sessão para contar certos e errados desta matéria.',
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: school.loading
                    ? null
                    : () {
                        if (session?.active == true) {
                          school.finishSession(name);
                          tell('Sessão terminada. O relatório fica guardado.');
                        } else {
                          school.startSession(name);
                          tell(
                            'Sessão de $name iniciada. A contagem começa em zero.',
                          );
                        }
                      },
                child: Text(
                  session?.active == true
                      ? 'Terminar sessão'
                      : session != null
                      ? 'Nova sessão · zerar contagem'
                      : 'Iniciar sessão',
                ),
              ),
            ],
          ),
          color: const Color(0xffeef3e7),
        ),
        panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              heading(name, 'Relatório de execução'),
              const SizedBox(height: 20),
              Wrap(
                spacing: 32,
                runSpacing: 20,
                children: [
                  metric('${counts['correct']}', 'Certos'),
                  metric('${counts['wrong']}', 'Errados'),
                  metric('${counts['review']}', 'Para rever'),
                  metric(
                    '${counts.values.fold(0, (a, b) => a + b)} / ${items.length}',
                    'Exercícios validados',
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                session == null
                    ? 'Inicia uma sessão para preencher o relatório.'
                    : '${session.active ? 'Em curso' : 'Terminada'} · Início: ${MaterialLocalizations.of(context).formatShortDate(session.startedAt.toLocal())} ${TimeOfDay.fromDateTime(session.startedAt.toLocal()).format(context)}',
                style: const TextStyle(fontSize: 12),
              ),
              if (session != null)
                ...items
                    .where((e) => session.results.containsKey(e.id))
                    .map(
                      (e) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(e.title),
                        subtitle: Text(
                          resultLabels[session.results[e.id]] ?? 'Para rever',
                        ),
                        trailing: const Icon(Icons.arrow_forward),
                        onTap: () => go(name, selected: e),
                      ),
                    ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        heading('Vamos praticar?', 'Os teus exercícios'),
        const SizedBox(height: 20),
        TextField(
          key: ValueKey('search-$name'),
          decoration: const InputDecoration(
            labelText: 'Pesquisar exercícios',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (value) => setState(() => query = value),
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<String>(
          value: topics.contains(topic) ? topic : topics.first,
          decoration: const InputDecoration(labelText: 'Tema'),
          items: topics
              .map((t) => DropdownMenuItem(value: t, child: Text(t)))
              .toList(),
          onChanged: (value) => setState(() => topic = value ?? topics.first),
        ),
        const SizedBox(height: 18),
        if (visible.isEmpty && !school.loading)
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text(
              'Nenhum exercício encontrado. Experimenta outro tema ou outra pesquisa.',
            ),
          ),
        ...visible.map(
          (e) => Card(
            color: Colors.white,
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 12,
              ),
              leading: Icon(subjectIcon(name), color: green),
              title: Text(
                e.title,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                '${e.topic} · ${e.questions.length} perguntas${session?.active == true ? ' · ${resultLabels[session?.results[e.id]] ?? 'Por fazer'}' : ''}',
              ),
              trailing: const Icon(Icons.arrow_forward_rounded),
              onTap: () => go(name, selected: e),
            ),
          ),
        ),
      ],
    );
  }

  Widget exercisePage(Exercise item) {
    final attempt = school.attempt(item);
    final session = school.sessions[item.subject];
    final siblings = school.forSubject(item.subject);
    final nextIndex = siblings.indexWhere((e) => e.id == item.id) + 1;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 850),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => go(item.subject),
                icon: const Icon(Icons.arrow_back),
                label: Text('Voltar a ${item.subject}'),
              ),
            ),
            if (school.inSession(item))
              panel(
                Text(
                  'Sessão de ${item.subject} em curso. Os resultados aparecem no relatório da matéria.',
                ),
                color: const Color(0xffeef3e7),
              ),
            panel(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  heading(item.topic, item.title, item.instructions),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 10,
                    children: [
                      Builder(
                        builder: (buttonContext) => TextButton.icon(
                          onPressed: () => export(item, buttonContext),
                          icon: const Icon(Icons.download_outlined),
                          label: const Text('Exportar JSON'),
                        ),
                      ),
                      TextButton(
                        onPressed: () => showJson(item),
                        child: const Text('Ver / copiar JSON'),
                      ),
                    ],
                  ),
                  if (item.text.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: panel(
                        SelectableText(
                          item.text,
                          style: const TextStyle(height: 1.9, fontSize: 16),
                        ),
                        color: const Color(0xfffaf8ef),
                      ),
                    ),
                  if (item.audioText.isNotEmpty)
                    panel(
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Escuta e descobre',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: () => speak(item),
                            icon: Icon(
                              speaking ? Icons.stop : Icons.volume_up_outlined,
                            ),
                            label: Text(speaking ? 'Parar' : 'Ouvir texto'),
                          ),
                          ExpansionTile(
                            tilePadding: EdgeInsets.zero,
                            title: const Text('Ler a transcrição'),
                            children: [
                              SelectableText(
                                item.audioText,
                                style: const TextStyle(height: 1.8),
                              ),
                            ],
                          ),
                        ],
                      ),
                      color: const Color(0xffeef3e7),
                    ),
                  const SizedBox(height: 16),
                  ...item.questions.asMap().entries.map((entry) {
                    final q = entry.value;
                    final correct = attempt.answers[q.id] == q.correctAnswer;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${entry.key + 1}. ${q.prompt}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                              height: 1.6,
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (q.isChoice)
                            ...q.options.map(
                              (option) => RadioListTile<String>(
                                contentPadding: EdgeInsets.zero,
                                title: Text(option.text),
                                value: option.id,
                                groupValue: attempt.answers[q.id],
                                onChanged: (value) {
                                  if (value != null) {
                                    school.answer(item, q.id, value);
                                    setState(() => showAnimation = false);
                                  }
                                },
                              ),
                            )
                          else
                            TextFormField(
                              key: ValueKey(
                                '${item.id}-${q.id}-$answerRevision',
                              ),
                              initialValue: attempt.answers[q.id] ?? '',
                              minLines: 4,
                              maxLines: 10,
                              decoration: const InputDecoration(
                                hintText: 'Escreve aqui a tua resposta…',
                              ),
                              onChanged: (value) {
                                school.answer(item, q.id, value);
                                setState(() => showAnimation = false);
                              },
                            ),
                          if (attempt.checked)
                            Container(
                              width: double.infinity,
                              margin: const EdgeInsets.only(top: 12),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: !q.isChoice
                                    ? const Color(0xffeef1f7)
                                    : correct
                                    ? const Color(0xffeaf4e9)
                                    : const Color(0xfffff4df),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    !q.isChoice
                                        ? (attempt.answers[q.id]
                                                      ?.trim()
                                                      .isNotEmpty ==
                                                  true
                                              ? 'Resposta registada — para rever com um adulto.'
                                              : 'Ainda não escreveste uma resposta.')
                                        : correct
                                        ? '✓ Muito bem!'
                                        : attempt.answers.containsKey(q.id)
                                        ? 'Vamos aprender com esta tentativa.'
                                        : 'Ainda não escolheste uma opção.',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (q.isChoice && !correct)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Text(
                                        'Resposta correta: ${q.options.firstWhere((o) => o.id == q.correctAnswer).text}',
                                      ),
                                    ),
                                  if (q.explanation.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Text(
                                        q.explanation,
                                        style: const TextStyle(height: 1.7),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    );
                  }),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: () {
                        school.validate(item);
                        setState(() {
                          showAnimation = true;
                          validationAttempt++;
                        });
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          final target = validationAnchor.currentContext;
                          if (mounted && target != null)
                            Scrollable.ensureVisible(
                              target,
                              alignment: .5,
                              duration: MediaQuery.of(context).disableAnimations
                                  ? Duration.zero
                                  : const Duration(milliseconds: 400),
                            );
                        });
                      },
                      icon: const Icon(Icons.check),
                      label: const Text('Validar respostas'),
                    ),
                  ),
                  if (attempt.checked && showAnimation)
                    SizedBox(
                      key: validationAnchor,
                      child: ValidationBanner(
                        key: ValueKey(validationAttempt),
                        exercise: item,
                        answers: Map.of(attempt.answers),
                      ),
                    ),
                  if (attempt.checked)
                    Padding(
                      padding: const EdgeInsets.only(top: 20),
                      child: panel(
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.choices.isEmpty
                                  ? 'Exercício pronto para revisão.'
                                  : '${item.correctCount(attempt.answers)} de ${item.choices.length} respostas de escolha múltipla corretas.',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (item.hasWriting)
                              const Padding(
                                padding: EdgeInsets.only(top: 12),
                                child: Text(
                                  'As respostas escritas precisam da revisão de um adulto.',
                                ),
                              ),
                            if (school.inSession(item))
                              Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Text(
                                  'Resultado na sessão: ${resultLabels[session?.results[item.id]] ?? 'Por validar'}.',
                                ),
                              ),
                            TextButton(
                              onPressed: () {
                                school.reset(item);
                                setState(() {
                                  showAnimation = false;
                                  answerRevision++;
                                });
                              },
                              child: const Text('Recomeçar este exercício'),
                            ),
                          ],
                        ),
                        color: const Color(0xfff1f5ec),
                      ),
                    ),
                  if (attempt.checked &&
                      school.inSession(item) &&
                      item.hasWriting)
                    panel(
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Revisão de um adulto',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Revê todas as respostas escritas e classifica o exercício completo.',
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 12,
                            runSpacing: 8,
                            children: [
                              OutlinedButton(
                                onPressed:
                                    item.correctCount(attempt.answers) ==
                                        item.choices.length
                                    ? () => school.review(item, 'correct')
                                    : null,
                                child: const Text('Marcar como certo'),
                              ),
                              OutlinedButton(
                                onPressed: () => school.review(item, 'wrong'),
                                child: const Text('Marcar como errado'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  const Divider(),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      OutlinedButton(
                        onPressed: () => go(item.subject),
                        child: const Text('← Lista de exercícios'),
                      ),
                      if (nextIndex > 0 && nextIndex < siblings.length)
                        FilledButton(
                          onPressed: () =>
                              go(item.subject, selected: siblings[nextIndex]),
                          child: const Text('Próximo exercício →'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ExerciseEditor extends StatefulWidget {
  const ExerciseEditor({super.key, required this.school, this.initialSubject});
  final SchoolState school;
  final String? initialSubject;
  @override
  State<ExerciseEditor> createState() => _ExerciseEditorState();
}

class _ExerciseEditorState extends State<ExerciseEditor> {
  late final TextEditingController source = TextEditingController(
    text: const JsonEncoder.withIndent('  ').convert({
      ...exampleJson,
      if (widget.initialSubject != null) 'subject': widget.initialSubject,
    }),
  );
  bool saving = false;
  String? error;
  @override
  void dispose() {
    source.dispose();
    super.dispose();
  }

  Future<void> save() async {
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final exercise = await widget.school.create(source.text);
      if (mounted) Navigator.of(context).pop(exercise);
    } catch (e) {
      if (mounted)
        setState(() {
          saving = false;
          error = e.toString();
        });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: AlertDialog(
      title: const Text('Uma nova descoberta'),
      content: SizedBox(
        width: 720,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Cola ou edita o JSON. Usa um id único. O servidor guarda o exercício num ficheiro .json.',
              ),
              const SizedBox(height: 14),
              const Text(
                'Campos: id, title, subject, topic e questions. Perguntas multiple-choice incluem options e correctAnswer. Para escrita, usa written.',
                style: TextStyle(fontSize: 12, height: 1.7),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: source,
                enabled: !saving,
                minLines: 12,
                maxLines: 20,
                autocorrect: false,
                enableSuggestions: false,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  height: 1.6,
                ),
                decoration: const InputDecoration(
                  labelText: 'JSON do exercício',
                  alignLabelWithHint: true,
                ),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        TextButton(
          onPressed: saving
              ? null
              : () {
                  source.text = const JsonEncoder.withIndent('  ')
                      .convert(exampleJson);
                },
          child: const Text('Carregar exemplo'),
        ),
        FilledButton(
          onPressed: saving ? null : save,
          child: Text(saving ? 'A guardar…' : 'Guardar exercício'),
        ),
      ],
    ),
  );
}
