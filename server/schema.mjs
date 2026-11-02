export function validateExercise(value) {
  const fail = message => { throw new Error(message); };
  const text = v => typeof v === 'string' && v.trim().length > 0;
  if (!value || typeof value !== 'object' || Array.isArray(value)) fail('O exercício deve ser um objeto JSON.');
  if (!/^[a-z0-9][a-z0-9-]{0,79}$/.test(value.id ?? '')) fail('O id deve ter até 80 letras minúsculas, números ou hífen.');
  if (!text(value.title) || !text(value.topic)) fail('Preenche title e topic.');
  for (const key of ['subject', 'instructions', 'text', 'audioText']) {
    if (value[key] !== undefined && typeof value[key] !== 'string') fail(`${key} deve ser texto.`);
  }
  if (!Array.isArray(value.questions) || !value.questions.length || value.questions.length > 50) fail('Inclui entre 1 e 50 perguntas.');
  const ids = new Set();
  for (const q of value.questions) {
    if (!q || !text(q.id) || ids.has(q.id)) fail('Cada pergunta precisa de um id único.');
    ids.add(q.id);
    if (!text(q.prompt)) fail(`A pergunta ${q.id} precisa de prompt.`);
    if (!['multiple-choice', 'written'].includes(q.type)) fail(`Tipo inválido em ${q.id}. Usa multiple-choice ou written.`);
    if (q.explanation !== undefined && typeof q.explanation !== 'string') fail('explanation deve ser texto.');
    if (q.type === 'multiple-choice') {
      if (!Array.isArray(q.options) || q.options.length < 2 || q.options.length > 8) fail(`${q.id}: inclui entre 2 e 8 opções.`);
      const optionIds = new Set();
      for (const option of q.options) {
        if (!option || !text(option.id) || !text(option.text) || optionIds.has(option.id)) fail(`${q.id}: as opções precisam de id único e text.`);
        optionIds.add(option.id);
      }
      if (!optionIds.has(q.correctAnswer)) fail(`${q.id}: correctAnswer deve corresponder ao id de uma opção.`);
    }
  }
  return value;
}
