export const sessionStorageKey = 'escola-em-dia-sessions-v1';

export function readSessions(storage) {
  try {
    const value = JSON.parse(storage.getItem(sessionStorageKey) || '{}');
    if (!value || typeof value !== 'object' || Array.isArray(value)) return {};
    return Object.fromEntries(Object.entries(value).filter(([, session]) => session &&
      typeof session.active === 'boolean' && session.results && typeof session.results === 'object' &&
      !Array.isArray(session.results) && session.progress && typeof session.progress === 'object' && !Array.isArray(session.progress)));
  } catch { return {}; }
}

export function exerciseResult(exercise, answers) {
  const choices = exercise.questions.filter(q => q.type === 'multiple-choice');
  if (choices.some(q => answers[q.id] !== q.correctAnswer)) return 'wrong';
  return exercise.questions.some(q => q.type === 'written') ? 'review' : 'correct';
}

export function countResults(results = {}) {
  const values = Object.values(results);
  return {
    correct: values.filter(value => value === 'correct').length,
    wrong: values.filter(value => value === 'wrong').length,
    review: values.filter(value => value === 'review').length
  };
}
