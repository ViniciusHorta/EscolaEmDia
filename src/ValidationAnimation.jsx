import React from 'react';

export default function ValidationAnimation({ feedback }) {
  const { mode, title, message, percentage, correct, total } = feedback;
  return <div className={`validation-animation validation-${mode}`} role="status" aria-live="polite" aria-atomic="true">
    <div className="validation-decoration" aria-hidden="true">
      {mode === 'celebrate' && <div className="confetti-cloud">{Array.from({ length: 24 }, (_, index) => <i key={index} style={{ '--x': `${(index * 37 + 5) % 100}%`, '--delay': `${(index % 6) * .13}s`, '--turn': `${index * 43}deg`, '--color': ['#e1ac3c', '#3a9071', '#dc7b68', '#8c86c0'][index % 4] }}/>)}</div>}
      <span className="validation-mascot">{mode === 'celebrate' ? '🌟' : mode === 'encourage' ? '🌱' : '✏️'}</span>
      <span className="validation-spark spark-one">{mode === 'celebrate' ? '✦' : '✧'}</span><span className="validation-spark spark-two">✧</span>
    </div>
    <div className="validation-copy"><span className="eyebrow">{mode === 'celebrate' ? 'HORA DE CELEBRAR!' : mode === 'encourage' ? 'UM PASSO DE CADA VEZ' : 'VAMOS REVER JUNTOS'}</span><h3>{title}</h3><p>{message}</p>
      {percentage !== null && <span className="validation-score">{percentage}% de acertos · {correct} de {total} perguntas de escolha múltipla</span>}
    </div>
  </div>;
}
