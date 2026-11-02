import React, { useEffect, useRef, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { validateExercise } from '../server/schema.mjs';
import { readSessions, sessionStorageKey, exerciseResult, countResults } from './sessions.mjs';
import { validationFeedback } from './validation-feedback.mjs';
import ValidationAnimation from './ValidationAnimation.jsx';
import './style.css';

const example = {
  id: 'novo-exercicio', title: 'À descoberta das palavras', subject: 'Português', topic: 'Sílabas',
  instructions: 'Lê a pergunta e escolhe a resposta correta.',
  questions: [{ id: 'q1', type: 'multiple-choice', prompt: 'Quantas sílabas tem a palavra «castanha»?',
    options: [{ id: 'a', text: 'Duas' }, { id: 'b', text: 'Três' }, { id: 'c', text: 'Quatro' }],
    correctAnswer: 'b', explanation: 'cas-ta-nha: três sílabas. É uma palavra trissilábica.' }]
};
const storageKey = 'escola-em-dia-progress-v1';
const portugueseTopics = new Set(['Compreensão oral', 'Compreensão escrita', 'Dicionário', 'Sílabas', 'Sílaba tónica', 'Onomatopeias', 'Formação de palavras', 'Família de palavras', 'Expressão escrita']);
function subjectOf(exercise) {
  return exercise.subject?.trim() || (exercise.topic === 'Estudo do Meio' ? 'Estudo do Meio' : portugueseTopics.has(exercise.topic) ? 'Português' : 'Outras matérias');
}
function readProgress() {
  try {
    const parsed = JSON.parse(localStorage.getItem(storageKey) || '{}');
    return parsed && typeof parsed === 'object' && !Array.isArray(parsed) ? parsed : {};
  } catch { return {}; }
}
function download(name, value) {
  const url = URL.createObjectURL(new Blob([JSON.stringify(value, null, 2)], { type: 'application/json' }));
  const a = document.createElement('a'); a.href = url; a.download = name; a.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
function App() {
  const [exercises, setExercises] = useState([]);
  const [activeId, setActiveId] = useState('');
  const [topic, setTopic] = useState('Todos os temas');
  const [subject, setSubject] = useState('');
  const [query, setQuery] = useState('');
  const [progress, setProgress] = useState(readProgress);
  const [sessions, setSessions] = useState(() => readSessions(localStorage));
  const [view, setView] = useState('home');
  const [navCollapsed, setNavCollapsed] = useState(() => {
    try { const saved = localStorage.getItem('escola-em-dia-nav-collapsed'); return saved === null ? window.matchMedia('(max-width: 960px)').matches : saved === 'true'; }
    catch { return false; }
  });
  const [sessionError, setSessionError] = useState('');
  const [validation, setValidation] = useState(null);
  const validationAttemptRef = useRef(0);
  const validationResultRef = useRef(null);
  const [editor, setEditor] = useState(false);
  const [json, setJson] = useState(JSON.stringify(example, null, 2));
  const [error, setError] = useState('');
  const [loadError, setLoadError] = useState('');
  const [notice, setNotice] = useState('');
  const [saving, setSaving] = useState(false);
  const [loading, setLoading] = useState(true);
  const [speaking, setSpeaking] = useState(false);
  const [storageError, setStorageError] = useState('');
  const editorRef = useRef(null);
  const addRef = useRef(null);
  const pageHeadingRef = useRef(null);
  const menuButtonRef = useRef(null);
  const navigationRef = useRef(null);
  const active = exercises.find(e => e.id === activeId);
  const currentSubject = view === 'home' ? '' : view === 'exercise' && active ? subjectOf(active) : subject;
  const session = sessions[currentSubject];
  const counts = countResults(session?.results);
  const exerciseSession = active && sessions[subjectOf(active)];
  const inSession = exerciseSession?.active === true;
  const saved = inSession ? exerciseSession.progress[activeId] : progress[activeId];
  const answers = saved?.answers && typeof saved.answers === 'object' ? saved.answers : {};
  const checked = saved?.checked === true;
  const subjects = [...new Set(exercises.map(subjectOf))].sort((a, b) => a.localeCompare(b, 'pt'));
  const subjectExercises = exercises.filter(e => !subject || subjectOf(e) === subject);
  const topics = ['Todos os temas', ...new Set(subjectExercises.map(e => e.topic))];
  const totalTopics = new Set(exercises.map(e => e.topic)).size;
  const filtered = subjectExercises.filter(e => (topic === 'Todos os temas' || e.topic === topic) && `${e.title} ${e.topic}`.toLocaleLowerCase('pt').includes(query.toLocaleLowerCase('pt')));
  const choices = active?.questions.filter(q => q.type === 'multiple-choice') || [];
  const score = choices.filter(q => answers[q.id] === q.correctAnswer).length;

  async function load() {
    setLoading(true); setLoadError('');
    try {
      const res = await fetch('/api/exercises');
      if (!res.ok) throw new Error('Não foi possível carregar os exercícios. Confirma que o servidor está ligado.');
      const list = await res.json();
      list.forEach(validateExercise);
      setExercises(list); setActiveId(current => list.some(e => e.id === current) ? current : list[0]?.id || '');
    } catch (e) { setLoadError(e.message); }
    finally { setLoading(false); }
  }
  useEffect(() => { load(); }, []);
  useEffect(() => { setValidation(null); }, [view, activeId]);
  useEffect(() => {
    if (validation) validationResultRef.current?.scrollIntoView({
      behavior: window.matchMedia('(prefers-reduced-motion: reduce)').matches ? 'instant' : 'smooth', block: 'center'
    });
  }, [validation]);
  useEffect(() => {
    try { localStorage.setItem('escola-em-dia-nav-collapsed', String(navCollapsed)); }
    catch { /* A preferência visual mantém-se nesta página. */ }
  }, [navCollapsed]);
  useEffect(() => {
    pageHeadingRef.current?.focus();
  }, [view, activeId, subject]);
  useEffect(() => {
    try { localStorage.setItem(sessionStorageKey, JSON.stringify(sessions)); setSessionError(''); }
    catch { setSessionError('Não foi possível guardar as sessões neste navegador. A contagem mantém-se apenas enquanto a página estiver aberta.'); }
  }, [sessions]);
  useEffect(() => {
    try { localStorage.setItem(storageKey, JSON.stringify(progress)); setStorageError(''); }
    catch { setStorageError('O navegador não conseguiu guardar as respostas. Mantêm-se disponíveis enquanto esta página estiver aberta.'); }
  }, [progress]);
  useEffect(() => {
    window.speechSynthesis?.cancel(); setSpeaking(false);
    return () => window.speechSynthesis?.cancel();
  }, [activeId, view]);
  useEffect(() => {
    if (editor) editorRef.current?.focus();
  }, [editor]);
  useEffect(() => {
    if (navCollapsed) return;
    function closeOnEscape(event) {
      if (event.key === 'Escape' && !editor) {
        setNavCollapsed(true); menuButtonRef.current?.focus();
      }
    }
    document.addEventListener('keydown', closeOnEscape);
    return () => document.removeEventListener('keydown', closeOnEscape);
  }, [navCollapsed, editor]);
  function navigate(name = '') {
    setSubject(name); setTopic('Todos os temas'); setQuery('');
    setView(name ? 'list' : 'home'); setNotice('');
    if (window.matchMedia('(max-width: 960px)').matches) setNavCollapsed(true);
    window.scrollTo({ top: 0, behavior: 'instant' });
    requestAnimationFrame(() => pageHeadingRef.current?.focus());
  }
  function toggleNavigation() {
    setNavCollapsed(value => !value);
    if (navCollapsed) requestAnimationFrame(() => navigationRef.current?.querySelector('button')?.focus());
  }
  function writeProgress(value) {
    setValidation(null);
    if (inSession) {
      const name = subjectOf(active);
      setSessions(all => ({ ...all, [name]: { ...all[name], progress: { ...all[name].progress, [activeId]: value } } }));
    } else setProgress(p => ({ ...p, [activeId]: value }));
  }
  function update(answerId, value) {
    writeProgress({ answers: { ...answers, [answerId]: value }, checked: false });
  }
  function validate() {
    writeProgress({ answers, checked: true });
    setValidation({ ...validationFeedback(active.questions, answers, validationAttemptRef.current), attempt: validationAttemptRef.current++ });
    if (inSession) {
      const name = subjectOf(active);
      setSessions(all => ({ ...all, [name]: { ...all[name], results: { ...all[name].results, [activeId]: exerciseResult(active, answers) } } }));
    }
  }
  function openExercise(exercise) {
    setActiveId(exercise.id); setView('exercise'); setNotice('');
    window.scrollTo({ top: 0, behavior: 'instant' });
  }
  function backToList() {
    setSubject(active ? subjectOf(active) : subject); setView('list');
  }
  function startSession() {
    if (!currentSubject) return;
    setSessions(all => ({ ...all, [currentSubject]: { active: true, startedAt: new Date().toISOString(), results: {}, progress: {} } }));
    setNotice(`Sessão de ${currentSubject} iniciada. A contagem começa em zero.`);
  }
  function finishSession() {
    setSessions(all => ({ ...all, [currentSubject]: { ...all[currentSubject], active: false } }));
    if (view === 'exercise') backToList();
    setNotice(`Sessão de ${currentSubject} terminada. O resumo fica guardado até iniciares uma nova sessão desta matéria.`);
  }
  function reviewWritten(status) {
    const name = subjectOf(active);
    setSessions(all => ({ ...all, [name]: { ...all[name], results: { ...all[name].results, [activeId]: status } } }));
  }
  function speak() {
    if (!('speechSynthesis' in window)) { setNotice('Este navegador não permite leitura em voz alta. Usa a transcrição disponível abaixo.'); return; }
    window.speechSynthesis.cancel();
    if (speaking) { setSpeaking(false); return; }
    const utterance = new SpeechSynthesisUtterance(active.audioText);
    utterance.lang = 'pt-PT'; utterance.rate = 0.85;
    utterance.onend = utterance.onerror = () => setSpeaking(false);
    setSpeaking(true); window.speechSynthesis.speak(utterance);
  }
  function closeEditor() { setEditor(false); setError(''); requestAnimationFrame(() => addRef.current?.focus()); }
  async function save(event) {
    event.preventDefault(); setError(''); setSaving(true);
    try {
      const value = validateExercise(JSON.parse(json));
      const res = await fetch('/api/exercises', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(value) });
      const result = await res.json();
      if (!res.ok) throw new Error(result.error || 'Não foi possível guardar.');
      setExercises(list => [...list, result]); setSubject(subjectOf(result)); setTopic('Todos os temas'); setQuery(''); setActiveId(result.id); setView('list');
      closeEditor(); setNotice(`«${result.title}» guardado no ficheiro ${result.id}.json.`);
    } catch (e) { setError(e instanceof SyntaxError ? `JSON inválido: ${e.message}` : e.message); }
    finally { setSaving(false); }
  }
  return <>
    <header className="topbar app-header"><button ref={menuButtonRef} className="hamburger" type="button" aria-label={navCollapsed ? 'Abrir menu de navegação' : 'Fechar menu de navegação'} aria-expanded={!navCollapsed} aria-controls="app-navigation" onClick={toggleNavigation}><span aria-hidden="true">☰</span></button><a className="brand" href="#home" onClick={event => { event.preventDefault(); navigate(); }}><span className="brand-icon">✦</span> escola em dia<span className="brand-dot">.</span></a><span className="header-location">{currentSubject || 'Home'}</span><span className="local-badge"><i /> O teu cantinho de aprendizagem</span></header>
    {!navCollapsed && <button className="navigation-overlay" aria-label="Fechar menu de navegação" onClick={() => { setNavCollapsed(true); menuButtonRef.current?.focus(); }} tabIndex={-1}/>}
    <nav ref={navigationRef} id="app-navigation" className="app-navigation" aria-label="Navegação principal" hidden={navCollapsed}>
      <div className="navigation-title">O TEU ESPAÇO</div>
      <button className={`app-nav-link ${view === 'home' ? 'active' : ''}`} aria-current={view === 'home' ? 'page' : undefined} onClick={() => navigate()}><span aria-hidden="true">⌂</span>Home</button>
      <div className="navigation-title">MATÉRIAS</div>
      {subjects.map(name => <button key={name} className={`app-nav-link ${currentSubject === name ? 'active' : ''}`} aria-current={currentSubject === name ? 'page' : undefined} onClick={() => navigate(name)}><span className="app-nav-icon" aria-hidden="true">{name === 'Português' ? 'Aa' : name === 'Estudo do Meio' ? '✿' : '◇'}</span><span>{name}</span><small>{exercises.filter(e => subjectOf(e) === name).length}</small></button>)}
      {loading && <p className="navigation-note" role="status">A carregar matérias…</p>}
      <p className="navigation-note">Cada matéria tem os seus exercícios, a sua sessão e o seu relatório.</p>
    </nav>
    <div className={`app-content ${navCollapsed ? '' : 'with-navigation'}`}><main>
      {view === 'home' && <><section className="hero"><div><div className="eyebrow">PEQUENAS DESCOBERTAS, TODOS OS DIAS</div><h1 ref={pageHeadingRef} tabIndex={-1}>Aprender é uma<br /><em>grande aventura.</em></h1><p>Um pouco de leitura, palavras e mundo à tua volta.<br />Escolhe um desafio e dá o próximo passo.</p><button className="primary" ref={addRef} onClick={() => { setError(''); setEditor(true); }}>＋ Adicionar exercício</button></div><div className="hero-art" aria-hidden="true"><div className="orbit orbit-one"/><div className="orbit orbit-two"/><span className="art-star">✧</span><div className="book"><div className="book-left">Aa<span/><span/><span/></div><div className="book-right">✷<span/><span/><span/></div></div><span className="art-caption">Há sempre algo novo para descobrir.</span></div></section>
      <section className="stats home-stats" aria-label="Conteúdos disponíveis"><div><b>{exercises.length}</b><span>exercícios para explorar</span></div><div><b>{subjects.length}</b><span>matérias para descobrir</span></div><div><b>{totalTopics}</b><span>temas cheios de descobertas</span></div></section>
      <section className="home-subjects" aria-labelledby="subjects-title"><div className="section-heading"><div><span className="eyebrow">POR ONDE VAMOS COMEÇAR?</span><h2 id="subjects-title">As tuas matérias</h2></div></div><div className="subject-grid">{subjects.map(name => <button className="subject-home-card" key={name} onClick={() => navigate(name)}><span className="home-subject-icon" aria-hidden="true">{name === 'Português' ? 'Aa' : name === 'Estudo do Meio' ? '✿' : '◇'}</span><strong>{name}</strong><span>{exercises.filter(e => subjectOf(e) === name).length} exercícios · Explorar matéria →</span></button>)}</div>{!loading && !loadError && !subjects.length && <p>Ainda não há matérias. Adiciona o primeiro exercício para começar.</p>}</section></>}
      {view === 'home' && loadError && <div role="alert"><p className="error">{loadError}</p><button onClick={load}>Tentar novamente</button></div>}
      {notice && <div className="notice" role="status">{notice}<button className="text-button" onClick={() => setNotice('')} aria-label="Fechar aviso">×</button></div>}
      {storageError && <p className="error" role="alert">{storageError}</p>}
      {sessionError && <p className="error" role="alert">{sessionError}</p>}
      {view === 'exercise' && <button className="back-button" onClick={backToList}>← Voltar à lista de exercícios</button>}
      {view === 'list' && currentSubject && <>
      <div className="subject-page-heading"><div><span className="eyebrow">A TUA MATÉRIA</span><h1 ref={pageHeadingRef} tabIndex={-1}>{currentSubject}</h1><p>Explora os exercícios e acompanha a tua aprendizagem nesta matéria.</p></div><button ref={addRef} onClick={() => { setError(''); setEditor(true); }}>＋ Adicionar exercício</button></div>
      <section className="session-panel" aria-label={`Sessão de ${currentSubject}`}>
        <div className="session-description"><span className="eyebrow">{session?.active ? 'SESSÃO EM CURSO' : session ? 'ÚLTIMA SESSÃO TERMINADA' : 'PRONTO PARA COMEÇAR?'}</span><h2>A tua sessão</h2><p>{session?.active ? 'Cada exercício conta uma vez. Ao validar novamente, o resultado anterior é atualizado.' : session ? 'O relatório desta sessão fica disponível abaixo. Uma nova sessão começa do zero.' : 'Inicia uma sessão para contar os exercícios certos e errados desta matéria.'}</p></div>
        <button className={session?.active ? '' : 'primary'} disabled={loading || !!loadError} onClick={session?.active ? finishSession : startSession}>{session?.active ? 'Terminar sessão' : session ? 'Nova sessão · zerar contagem' : 'Iniciar sessão'}</button>
      </section>
      <section className="execution-report" aria-labelledby="report-title"><div className="report-heading"><div><span className="eyebrow">{currentSubject}</span><h2 id="report-title">Relatório de execução</h2></div><span className="report-state">{session?.active ? 'Em curso' : session ? 'Sessão terminada' : 'Sem sessão iniciada'}</span></div>
        <div className="session-counts" role="status"><div><b>{counts.correct}</b><span>Certos</span></div><div><b>{counts.wrong}</b><span>Errados</span></div><div><b>{counts.review}</b><span>Para rever</span></div><div><b>{counts.correct + counts.wrong + counts.review}<small> / {subjectExercises.length}</small></b><span>Exercícios validados</span></div></div>
        {session?.startedAt && <p className="report-note">Início: {new Date(session.startedAt).toLocaleString('pt-PT')}. Contagem de exercícios completos; as respostas escritas precisam de revisão.</p>}
        {session && Object.keys(session.results).length > 0 ? <div className="report-table-wrap"><table className="report-table"><thead><tr><th scope="col">Exercício</th><th scope="col">Resultado</th><th scope="col"><span className="sr-only">Abrir exercício</span></th></tr></thead><tbody>{subjectExercises.filter(exercise => session.results[exercise.id]).map(exercise => <tr key={exercise.id}><th scope="row">{exercise.title}</th><td><span className={`report-result ${session.results[exercise.id]}`}>{{ correct: 'Certo', wrong: 'Errado', review: 'Para rever' }[session.results[exercise.id]]}</span></td><td><button className="text-button" aria-label={`Abrir ${exercise.title}`} onClick={() => openExercise(exercise)}>Abrir →</button></td></tr>)}</tbody></table></div> : <p className="report-note">{session ? 'Valida o primeiro exercício para ver o resultado aqui.' : 'Inicia uma sessão desta matéria para preencher o relatório.'}</p>}
      </section></>}
      {view === 'list' && <>
      <div className="section-heading"><div><div className="eyebrow">VAMOS PRATICAR?</div><h2>Os teus exercícios</h2></div><label className="search"><span aria-hidden="true">⌕</span><input aria-label="Pesquisar exercícios" placeholder="Procurar uma descoberta…" value={query} onChange={e => setQuery(e.target.value)} /></label></div>
      <div className="workspace list-screen subject-workspace"><section className="exercise-sidebar" aria-label="Lista de exercícios"><label className="filter-label" htmlFor="topic">EXPLORAR POR TEMA</label><select id="topic" value={topic} onChange={e => setTopic(e.target.value)}>{topics.map(t => <option key={t}>{t}</option>)}</select><div className="exercise-list">
        {loading && <p role="status">A preparar os desafios…</p>}
        {loadError && <div role="alert"><p className="error">{loadError}</p><button onClick={load}>Tentar novamente</button></div>}
        {!loading && !loadError && !filtered.length && <p>Nenhum exercício encontrado. Experimenta outro tema ou adiciona um exercício.</p>}
        {filtered.map((e, index) => <button key={e.id} className="exercise-card" onClick={() => openExercise(e)}><span className="card-number">{String(index + 1).padStart(2, '0')}</span><span><small>{e.topic}</small><strong>{e.title}</strong><span className="card-meta">{e.questions.length} {e.questions.length === 1 ? 'pergunta' : 'perguntas'} {sessions[subjectOf(e)]?.active ? ({ correct: ' · ✓ Certo', wrong: ' · ✗ Errado', review: ' · Para rever' }[sessions[subjectOf(e)].results[e.id]] || ' · Por fazer') : progress[e.id]?.checked ? ' · ✓ Validado' : ''}</span></span><span className="card-arrow" aria-hidden="true">↗</span></button>)}
      </div><div className="tip">✧ <strong>Ao teu ritmo.</strong><p>Podes tentar as vezes que quiseres. Cada tentativa é uma oportunidade de aprender!</p></div></section></div></>}
      {view === 'exercise' && <section className="activity exercise-screen" aria-label="Exercício selecionado">{active ? <><div className="activity-top"><span className="topic-tag">{active.topic}</span><button className="text-button" onClick={() => download(`${active.id}.json`, active)}>↓ Exportar JSON</button></div><h2 ref={pageHeadingRef} tabIndex={-1}>{active.title}</h2><p className="instructions">{active.instructions || 'Lê com atenção e responde às perguntas.'}</p>
        {active.text && <div className="reading"><span className="eyebrow">LÊ COM ATENÇÃO</span><p>{active.text}</p></div>}
        {active.audioText && <div className="audio-box"><div><strong>Escuta e descobre</strong><p>Ouve o texto antes de responder.</p></div><button onClick={speak}>{speaking ? '■ Parar' : '▶ Ouvir texto'}</button><details><summary>Ler a transcrição</summary><p>{active.audioText}</p></details></div>}
        <form onSubmit={e => { e.preventDefault(); validate(); }}><div className="questions">{active.questions.map((q, i) => <fieldset key={`${active.id}-${q.id}`}><legend><span className="question-number">{i + 1}</span>{q.prompt}</legend>{q.type === 'multiple-choice' ? <div className="options">{q.options.map(o => <label key={o.id} className={`option ${answers[q.id] === o.id ? 'chosen' : ''}`}><input type="radio" name={q.id} value={o.id} checked={answers[q.id] === o.id} onChange={() => update(q.id, o.id)} /><span>{o.text}</span></label>)}</div> : <textarea className="written-answer" aria-label={q.prompt} placeholder="Escreve aqui a tua resposta…" value={answers[q.id] || ''} onChange={e => update(q.id, e.target.value)} rows={5}/>}
        {checked && <div className={`feedback ${q.type === 'written' ? 'review' : answers[q.id] === q.correctAnswer ? 'correct' : 'incorrect'}`} role="status">{q.type === 'written' ? <><strong>{answers[q.id]?.trim() ? 'Resposta registada — para rever com um adulto.' : 'Ainda não escreveste uma resposta.'}</strong><p>{q.explanation || 'Conversa sobre a tua resposta com o professor ou a família.'}</p></> : <><strong>{answers[q.id] === q.correctAnswer ? '✓ Muito bem!' : answers[q.id] ? 'Vamos aprender com esta tentativa.' : 'Ainda não escolheste uma opção.'}</strong>{answers[q.id] !== q.correctAnswer && <p>Resposta correta: {q.options.find(o => o.id === q.correctAnswer)?.text}</p>}{q.explanation && <p>{q.explanation}</p>}</>}</div>}
        </fieldset>)}</div><div className="action-bar"><span>Sem pressa. Tu consegues!</span><button type="submit" className="primary">Validar respostas ✓</button></div></form>
        {checked && validation && <div ref={validationResultRef}><ValidationAnimation key={validation.attempt} feedback={validation}/></div>}
        {checked && <div className="result" role="status"><strong>{choices.length ? `${score} de ${choices.length} respostas de escolha múltipla corretas` : 'Exercício pronto para revisão'}</strong><p>{active.questions.some(q => q.type === 'written') ? 'As respostas escritas precisam da revisão de um adulto.' : 'Podes alterar as respostas e voltar a validar.'}</p><button className="text-button" onClick={() => writeProgress({ answers: {}, checked: false })}>Recomeçar este exercício</button>{inSession && <><p className="session-result-label">Resultado na sessão : <strong>{{ correct: 'exercício certo', wrong: 'exercício errado', review: 'para rever com um adulto' }[exerciseSession.results[activeId]] || 'por validar'}</strong>. A contagem mantém a última validação.</p></>}</div>}
        {checked && inSession && active.questions.some(q => q.type === 'written') && <div className="adult-review"><strong>Revisão de um adulto</strong><p>Depois de rever todas as respostas escritas, classifica o exercício completo.</p><button disabled={choices.some(q => answers[q.id] !== q.correctAnswer)} onClick={() => reviewWritten('correct')}>Marcar como certo</button><button onClick={() => reviewWritten('wrong')}>Marcar como errado</button></div>}
        <div className="exercise-navigation"><button onClick={backToList}>← Lista de exercícios</button>{(() => { const sameSubject = exercises.filter(e => subjectOf(e) === subjectOf(active)); const next = sameSubject[sameSubject.findIndex(e => e.id === activeId) + 1]; return next && <button className="primary" onClick={() => openExercise(next)}>Próximo exercício →</button>; })()}</div>
      </> : <div className="empty"><span>✷</span><h2>Uma descoberta à tua espera</h2><p>{query || topic !== 'Todos os temas' ? 'Nenhum exercício corresponde aos filtros. Experimenta outro tema ou outra pesquisa.' : 'Escolhe um exercício na lista ou cria o teu primeiro desafio.'}</p></div>}</section>}
      <footer><span>escola em dia. <span className="footer-note">Feito para mentes curiosas.</span></span><span>Exercícios em ficheiros locais · Respostas neste navegador</span></footer>
    </main></div>
    {editor && <div className="modal-backdrop" onKeyDown={e => {
      if (e.key === 'Escape' && !saving) closeEditor();
      if (e.key === 'Tab') {
        const items = [...e.currentTarget.querySelectorAll('button:not(:disabled), textarea, a[href]')];
        const first = items[0], last = items.at(-1);
        if (e.shiftKey && document.activeElement === first) { e.preventDefault(); last.focus(); }
        if (!e.shiftKey && document.activeElement === last) { e.preventDefault(); first.focus(); }
      }
    }}><section className="modal" role="dialog" aria-modal="true" aria-labelledby="editor-title"><div className="modal-header"><div><span className="eyebrow">ESPAÇO DO EDUCADOR</span><h2 id="editor-title">Uma nova descoberta</h2></div><button disabled={saving} aria-label="Fechar editor" onClick={closeEditor}>×</button></div><p>Cola ou edita o JSON. O servidor guarda um novo ficheiro em <code>data/exercises/</code>. Usa um <code>id</code> diferente para cada exercício.</p><details><summary>Como escrever um exercício</summary><p>Preenche <code>id</code>, <code>title</code>, <code>topic</code> e <code>questions</code>. Perguntas <code>multiple-choice</code> incluem <code>options</code> e <code>correctAnswer</code> (o id da opção correta). Para resposta escrita, usa <code>written</code>. Os campos <code>text</code>, <code>audioText</code> e <code>explanation</code> são opcionais.</p></details><form onSubmit={save}><label htmlFor="json-editor" className="editor-label">JSON do exercício</label><textarea ref={editorRef} id="json-editor" className="json-editor" value={json} spellCheck="false" onChange={e => setJson(e.target.value)} rows={17}/>{error && <p className="error" role="alert">{error}</p>}<div className="editor-actions"><button type="button" disabled={saving} onClick={() => { setJson(JSON.stringify(example, null, 2)); setError(''); }}>Carregar exemplo</button><button type="submit" disabled={saving} className="primary">{saving ? 'A guardar…' : 'Guardar exercício'}</button></div></form></section></div>}
  </>;
}
createRoot(document.getElementById('root')).render(<App />);
