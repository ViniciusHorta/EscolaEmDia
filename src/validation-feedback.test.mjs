import test from 'node:test';
import assert from 'node:assert/strict';
import { validationFeedback } from './validation-feedback.mjs';

function result(correct, total) {
  const questions = Array.from({ length: total }, (_, i) => ({ id: `q${i}`, type: 'multiple-choice', correctAnswer: 'a' }));
  const answers = Object.fromEntries(questions.slice(0, correct).map(q => [q.id, 'a']));
  return validationFeedback(questions, answers);
}
test('celebra a partir de exatamente 70%, incluindo 100%', () => {
  assert.equal(result(7, 10).mode, 'celebrate');
  assert.equal(result(7, 10).percentage, 70);
  assert.equal(result(10, 10).mode, 'celebrate');
});
test('incentiva abaixo de 70%, sem arredondar para um resultado de celebração', () => {
  assert.equal(result(0, 10).mode, 'encourage');
  assert.equal(result(6, 10).mode, 'encourage');
  assert.equal(result(16, 23).mode, 'encourage');
  assert.equal(result(16, 23).percentage, 69);
});
test('respostas escritas não entram na percentagem nem recebem nota automática', () => {
  const questions = [{ id: 'q1', type: 'multiple-choice', correctAnswer: 'a' }, { id: 'q2', type: 'written' }];
  assert.equal(validationFeedback(questions, { q1: 'a' }).percentage, 100);
  const written = validationFeedback([questions[1]], { q2: 'Uma frase.' });
  assert.equal(written.mode, 'review');
  assert.equal(written.percentage, null);
});
