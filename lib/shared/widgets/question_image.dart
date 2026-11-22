import 'package:flutter/material.dart';
import '../../core/config/supabase_config.dart';
import '../../core/theme/app_tokens.dart';

/// Imagem opcional de uma questão: `"image": {"path": "…", "alt": "…"}` no conteúdo da ficha.
/// O ficheiro está no bucket público `question-images` do Supabase do ambiente atual.
class QuestionImage {
  const QuestionImage({required this.path, this.alt = ''});
  final String path, alt;

  static const bucket = 'question-images';

  String get url => '${SupabaseConfig.url}/storage/v1/object/public/$bucket/'
      '${path.split('/').map(Uri.encodeComponent).join('/')}';

  /// Devolve null quando não há imagem ou o valor não tem o formato esperado.
  static QuestionImage? tryParse(Object? value) {
    if (value is! Map) return null;
    final path = value['path'];
    if (path is! String || path.trim().isEmpty) return null;
    final alt = value['alt'];
    return QuestionImage(path: path, alt: alt is String ? alt.trim() : '');
  }
}

/// Mostra a imagem da questão com cantos arredondados; tocar abre em ecrã inteiro com zoom.
/// Se a imagem não carregar, mostra um aviso discreto em vez de partir o ecrã.
class QuestionImageView extends StatelessWidget {
  const QuestionImageView(this.image, {super.key, this.maxHeight = 260, this.zoomable = true});
  final QuestionImage image;
  final double maxHeight;
  final bool zoomable;

  @override
  Widget build(BuildContext context) {
    final label = image.alt.isEmpty ? 'Imagem da pergunta' : image.alt;
    final picture = ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Image.network(
          image.url,
          fit: BoxFit.contain,
          semanticLabel: label,
          loadingBuilder: (context, child, progress) => progress == null ? child
              : SizedBox(height: maxHeight * .6, child: const Center(child: CircularProgressIndicator(strokeWidth: 2.5))),
          errorBuilder: (context, error, stack) => Container(
            padding: const EdgeInsets.all(14),
            color: AppColors.muted.withValues(alpha: .08),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.broken_image_outlined, color: AppColors.muted), SizedBox(width: 8),
              Flexible(child: Text('Não foi possível carregar a imagem.', style: TextStyle(color: AppColors.muted))),
            ]),
          ),
        ),
      ),
    );
    if (!zoomable) return Center(child: picture);
    return Center(
      child: Semantics(
        button: true,
        hint: 'Toca para ampliar',
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _openFullScreen(context, label),
          child: picture,
        ),
      ),
    );
  }

  void _openFullScreen(BuildContext context, String label) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: const Text('Imagem')),
        body: InteractiveViewer(
          maxScale: 5,
          child: Center(child: Image.network(image.url, fit: BoxFit.contain, semanticLabel: label)),
        ),
      ),
    ));
  }
}
