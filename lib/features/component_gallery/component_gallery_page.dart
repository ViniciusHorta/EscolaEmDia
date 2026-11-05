import 'package:flutter/material.dart';
import '../../core/theme/app_tokens.dart';
import '../../shared/widgets/app_badge.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_card.dart';
import '../../shared/widgets/app_text_field.dart';
import '../../shared/widgets/cards/profile_card.dart';
import '../../shared/widgets/cards/subject_card.dart';
import '../../shared/widgets/cards/worksheet_card.dart';
import '../../shared/widgets/layout/app_page.dart';
import '../../shared/widgets/pin/app_pin_input.dart';

class ComponentGalleryPage extends StatefulWidget {
  const ComponentGalleryPage({super.key});

  @override
  State<ComponentGalleryPage> createState() => _ComponentGalleryPageState();
}

class _ComponentGalleryPageState extends State<ComponentGalleryPage> {
  String profile = 'Martim';
  String subject = 'Matemática';
  String pin = '';
  String? pinError;
  bool loading = false;

  void message(String value) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(value)));

  Future<void> loadExample() async {
    setState(() => loading = true);
    await Future<void>.delayed(const Duration(seconds: 1));
    if (mounted) setState(() => loading = false);
  }

  Widget section(String title, String description, Widget child) => Padding(
        padding: const EdgeInsets.only(bottom: 32),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(description, style: const TextStyle(color: AppColors.muted)),
          const SizedBox(height: 18),
          child,
        ]),
      );

  Widget columns(List<Widget> children) =>
      LayoutBuilder(builder: (context, constraints) {
        final width = constraints.maxWidth >= 700
            ? (constraints.maxWidth - 20) / 2
            : constraints.maxWidth;
        return Wrap(spacing: 20, runSpacing: 20, children: [
          for (final child in children) SizedBox(width: width, child: child)
        ]);
      });

  @override
  Widget build(BuildContext context) => AppPage(
        title: 'Pequenas peças, grandes descobertas.',
        subtitle:
            'Experimenta os botões, escolhe um perfil e testa o PIN. Esta página apresenta os componentes da nova aplicação com dados de exemplo.',
        children: [
          section(
              'Botões',
              'Ações principais, alternativas e estados de interação.',
              columns([
                AppCard(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                      AppButton(
                          label: 'Guardar e continuar',
                          icon: Icons.arrow_forward_rounded,
                          onPressed: () =>
                              message('Botão principal selecionado.')),
                      const SizedBox(height: 18),
                      AppButton(
                          label: 'Voltar',
                          variant: AppButtonVariant.secondary,
                          icon: Icons.arrow_back_rounded,
                          onPressed: () =>
                              message('Botão secundário selecionado.')),
                      const SizedBox(height: 18),
                      AppButton(
                          label: 'Tudo pronto!',
                          variant: AppButtonVariant.success,
                          icon: Icons.check_rounded,
                          onPressed: () => message('Ação concluída.')),
                    ])),
                AppCard(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                      const AppButton(
                          label: 'Ação indisponível', onPressed: null),
                      const SizedBox(height: 18),
                      AppButton(
                          label: loading ? 'A guardar…' : 'Testar carregamento',
                          loading: loading,
                          onPressed: loadExample),
                      const SizedBox(height: 24),
                      const Wrap(spacing: 8, runSpacing: 8, children: [
                        AppBadge(
                            label: 'Por começar',
                            icon: Icons.play_circle_outline),
                        AppBadge(
                            label: 'Concluída',
                            icon: Icons.check_circle_outline,
                            color: AppColors.success,
                            background: AppColors.successSoft),
                      ]),
                    ])),
              ])),
          section(
              'Perfis',
              'O mesmo card muda de estado quando selecionado.',
              columns([
                ProfileCard(
                    name: 'Martim',
                    schoolYear: 3,
                    avatar: Icons.face_rounded,
                    selected: profile == 'Martim',
                    onTap: () => setState(() => profile = 'Martim')),
                ProfileCard(
                    name: 'Leonor',
                    schoolYear: 4,
                    avatar: Icons.face_3_rounded,
                    selected: profile == 'Leonor',
                    onTap: () => setState(() => profile = 'Leonor')),
              ])),
          section(
              'PIN e formulários',
              'Escreve com o teclado ou toca nos números. O PIN desta demonstração não é guardado.',
              columns([
                AppCard(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                      Align(
                          child: AppPinInput(
                        label: 'PIN de $profile',
                        errorText: pinError,
                        onChanged: (value) => setState(() {
                          pin = value;
                          pinError = null;
                        }),
                      )),
                      const SizedBox(height: 24),
                      AppButton(
                          label: 'Entrar',
                          icon: Icons.arrow_forward_rounded,
                          onPressed: pin.length != 4
                              ? null
                              : () => message(
                                  'PIN completo. Demonstração sem autenticação.')),
                      const SizedBox(height: 12),
                      TextButton(
                          onPressed: () => setState(() =>
                              pinError = 'PIN incorreto. Tenta novamente.'),
                          child: const Text('Mostrar exemplo de erro')),
                    ])),
                const AppCard(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                      AppTextField(
                          label: 'Alcunha da criança',
                          hint: 'Como gosta de ser chamada?'),
                      SizedBox(height: 24),
                      AppTextField(
                          label: 'Nome da família', hint: 'A nossa família'),
                      SizedBox(height: 24),
                      AppTextField(
                          label: 'Campo com erro',
                          errorText: 'Preenche este campo para continuar.'),
                    ])),
              ])),
          section(
              'Disciplinas',
              'Cards selecionáveis para preparar uma ficha.',
              columns([
                SubjectCard(
                    title: 'Matemática',
                    subtitle: 'Números, frações e descobertas',
                    icon: Icons.calculate_outlined,
                    selected: subject == 'Matemática',
                    onTap: () => setState(() => subject = 'Matemática')),
                SubjectCard(
                    title: 'Português',
                    subtitle: 'Palavras, histórias e ideias',
                    icon: Icons.menu_book_rounded,
                    selected: subject == 'Português',
                    onTap: () => setState(() => subject = 'Português')),
              ])),
          section(
              'Fichas',
              'Um card composto por etiquetas, conteúdo e botão partilhados.',
              columns([
                WorksheetCard(
                    title: 'Matemática: Frações e Multiplicação',
                    description: 'Um desafio divertido e sem pressa.',
                    questionCount: 6,
                    onStart: () => message('Ficha de exemplo selecionada.')),
                WorksheetCard(
                    title: 'Português: Sinónimos',
                    description: 'Continua a tua descoberta das palavras.',
                    questionCount: 5,
                    actionLabel: 'Continuar',
                    onStart: () => message('Continuar ficha de exemplo.')),
              ])),
        ],
      );
}
