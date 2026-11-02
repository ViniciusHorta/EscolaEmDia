export function validationFeedback(questions, answers, attempt = 0) {
  const choices = questions.filter(question => question.type === 'multiple-choice');
  if (!choices.length) return {
    mode: 'review', title: 'As tuas ideias merecem ser partilhadas!',
    message: 'Boa dedicação! Revê as respostas escritas com um adulto e descobre o que já fizeste bem.',
    correct: 0, total: 0, percentage: null
  };
  const correct = choices.filter(question => answers[question.id] === question.correctAnswer).length;
  const celebration = correct * 100 >= choices.length * 70;
  const messages = celebration ? [
    ['Boa! Estás a brilhar!', 'Cada descoberta merece uma pequena festa. Continua com essa curiosidade!'],
    ['Uma salva de palmas para ti!', 'O teu esforço está a dar frutos. Há mais aventuras à tua espera!'],
    ['Uau, que grande conquista!', 'Aprender passo a passo leva-te longe. Celebra o que conseguiste!']
  ] : [
    ['Cada tentativa faz-te crescer!', 'Lê as explicações com calma e tenta outra vez. Tu consegues dar o próximo passo!'],
    ['A tua aventura continua!', 'Pede uma pista, revê uma pergunta de cada vez e volta a experimentar. Estamos a torcer por ti!'],
    ['Ainda há descobertas à tua espera!', 'Os erros ajudam-nos a aprender. Respira fundo, escolhe uma pergunta e tenta de novo!']
  ];
  const [title, message] = messages[attempt % messages.length];
  return { mode: celebration ? 'celebrate' : 'encourage', title, message,
    correct, total: choices.length, percentage: Math.floor(correct * 100 / choices.length) };
}
