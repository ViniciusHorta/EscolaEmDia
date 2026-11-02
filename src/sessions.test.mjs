import { test } from 'node:test';
import assert from 'node:assert/strict';
import { exerciseResult, countResults, readSessions } from './sessions.mjs';

const exercise = { questions: [
  { id: 'q1', type: 'multiple-choice', correctAnswer: 'a' },
  { id: 'q2', type: 'multiple-choice', correctAnswer: 'b' }
] };

test('um exercício só está certo quando todas as escolhas estão corretas', () => {
  assert.equal(exerciseResult(exercise, { q1: 'a', q2: 'b' }), 'correct');
  assert.equal(exerciseResult(exercise, { q1: 'a', q2: 'a' }), 'wrong');
  assert.equal(exerciseResult(exercise, { q1: 'a' }), 'wrong');
  assert.equal(exerciseResult(exercise, {}), 'wrong');
});

test('a escrita exige revisão, mesmo com todas as escolhas corretas', () => {
  const mixed = { questions: [...exercise.questions, { id: 'q3', type: 'written' }] };
  assert.equal(exerciseResult(mixed, { q1: 'a', q2: 'b', q3: 'Uma frase.' }), 'review');
  assert.equal(exerciseResult(mixed, { q1: 'a', q2: 'a' }), 'wrong');
  assert.equal(exerciseResult({ questions: [{ id: 'q1', type: 'written' }] }, {}), 'review');
});

test('revalidar substitui a classificação sem duplicar exercícios e mantém as matérias separadas', () => {
  const portuguese = { ex1: 'wrong', ex2: 'review' };
  const environment = { ex3: 'correct' };
  assert.deepEqual(countResults(portuguese), { correct: 0, wrong: 1, review: 1 });
  portuguese.ex1 = 'correct';
  assert.deepEqual(countResults(portuguese), { correct: 1, wrong: 0, review: 1 });
  assert.deepEqual(countResults(environment), { correct: 1, wrong: 0, review: 0 });
  assert.deepEqual(countResults({}), { correct: 0, wrong: 0, review: 0 });
});

test('as sessões e respostas podem ser recuperadas após recarregar', () => {
  const sessions = {
    'Português': { active: true, results: { ex1: 'wrong' }, progress: { ex1: { answers: { q1: 'b' }, checked: true } } },
    'Estudo do Meio': { active: false, results: { ex2: 'correct' }, progress: {} }
  };
  assert.deepEqual(readSessions({ getItem: () => JSON.stringify(sessions) }), sessions);
  for (const value of ['[1]', 'null', '{invalid', '{"Português":null}']) {
    assert.deepEqual(readSessions({ getItem: () => value }), {});
  }
  assert.deepEqual(readSessions({ getItem() { throw new Error('Storage indisponível'); } }), {});
});
