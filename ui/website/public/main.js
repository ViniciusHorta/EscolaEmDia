(() => {
  document.documentElement.classList.remove('no-js');
  const reduced = matchMedia('(prefers-reduced-motion: reduce)').matches;
  const $ = (s) => document.querySelector(s);

  const year = $('#year');
  if (year) year.textContent = new Date().getFullYear();

  /* Header state + scroll progress */
  const header = $('.header');
  const progress = $('.scroll-progress');
  const onScroll = () => {
    const y = scrollY;
    header.classList.toggle('is-scrolled', y > 12);
    const max = document.documentElement.scrollHeight - innerHeight;
    progress.style.setProperty('--p', max > 0 ? (y / max).toFixed(4) : 0);
  };
  addEventListener('scroll', onScroll, { passive: true });
  onScroll();

  /* Reveal on scroll */
  const io = new IntersectionObserver((entries) => {
    entries.forEach((e) => {
      if (e.isIntersecting) { e.target.classList.add('is-visible'); io.unobserve(e.target); }
    });
  }, { threshold: 0.15, rootMargin: '0px 0px -40px 0px' });
  document.querySelectorAll('.reveal').forEach((el) => io.observe(el));

  /* Active nav link */
  const links = [...document.querySelectorAll('.nav a')];
  const navIO = new IntersectionObserver((entries) => {
    entries.forEach((e) => {
      if (!e.isIntersecting) return;
      links.forEach((a) => a.classList.toggle('is-active', a.getAttribute('href') === '#' + e.target.id));
    });
  }, { rootMargin: '-45% 0px -50% 0px' });
  links.forEach((a) => { const s = $(a.getAttribute('href')); if (s) navIO.observe(s); });

  /* Subtle tilt on the hero device */
  const device = $('[data-tilt]');
  if (device && !reduced && matchMedia('(hover: hover)').matches) {
    const area = device.parentElement;
    area.addEventListener('pointermove', (e) => {
      const r = area.getBoundingClientRect();
      const x = (e.clientX - r.left) / r.width - 0.5;
      const y = (e.clientY - r.top) / r.height - 0.5;
      device.style.setProperty('--ry', `${(-8 + x * 14).toFixed(2)}deg`);
      device.style.setProperty('--rx', `${(4 - y * 10).toFixed(2)}deg`);
    });
    area.addEventListener('pointerleave', () => {
      device.style.removeProperty('--ry');
      device.style.removeProperty('--rx');
    });
  }

  /* Hero demo: a child solving a short worksheet, on loop */
  const demo = {
    card: $('#demo-card'), q: $('#demo-q'), opts: $('#demo-opts'),
    write: $('#demo-write'), typed: $('#demo-typed'), done: $('#demo-done'),
    toast: $('#demo-toast'), bar: $('#demo-bar'), count: $('#demo-count'),
    subject: $('#demo-subject'), confetti: $('#demo-confetti'),
  };
  if (!demo.card) return;

  const questions = [
    { subject: 'Matemática', q: 'Quanto é 3 × 4?', opts: ['7', '12', '14'], right: 1 },
    { subject: 'Português', q: 'Verdadeiro ou falso? «Mar» tem três letras.', opts: ['Verdadeiro', 'Falso'], right: 0 },
    { subject: 'Português', q: 'Escreve uma frase com a palavra «sol».', write: 'O sol aquece a praia.' },
  ];

  let visible = true;
  new IntersectionObserver(([e]) => { visible = e.isIntersecting; }).observe(demo.card);
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const waitVisible = async () => { while (!visible || document.hidden) await sleep(300); };

  const setProgress = (i) => {
    demo.bar.style.width = `${(i / questions.length) * 100}%`;
    demo.count.textContent = i < questions.length ? `Pergunta ${i + 1} de ${questions.length}` : 'Concluída';
  };

  const render = (item) => {
    demo.subject.textContent = item.subject;
    demo.subject.classList.toggle('is-pt', item.subject === 'Português');
    demo.q.textContent = item.q;
    demo.opts.innerHTML = '';
    demo.write.hidden = !item.write;
    demo.typed.textContent = '';
    (item.opts || []).forEach((o) => {
      const el = document.createElement('div');
      el.className = 'opt';
      el.textContent = o;
      demo.opts.appendChild(el);
    });
  };

  const toast = async (text) => {
    demo.toast.textContent = text;
    demo.toast.classList.add('is-on');
    await sleep(1100);
    demo.toast.classList.remove('is-on');
  };

  const burst = () => {
    const colors = ['#FBBF24', '#58CC02', '#1CB0F6', '#FF7A59', '#7C6BF0'];
    demo.confetti.innerHTML = '';
    for (let i = 0; i < 40; i++) {
      const c = document.createElement('i');
      c.style.left = `${Math.random() * 100}%`;
      c.style.background = colors[i % colors.length];
      c.style.setProperty('--x', `${(Math.random() - 0.5) * 120}px`);
      c.style.setProperty('--r', `${Math.random() * 720 - 360}deg`);
      c.style.animationDelay = `${Math.random() * 0.4}s`;
      demo.confetti.appendChild(c);
    }
  };

  const slideTo = async (item) => {
    demo.card.classList.add('is-out');
    await sleep(350);
    render(item);
    demo.card.classList.remove('is-out');
    demo.card.classList.add('is-in');
    void demo.card.offsetWidth; // restart transition
    demo.card.classList.remove('is-in');
  };

  const run = async () => {
    render(questions[0]);
    setProgress(0);
    if (reduced) return;
    for (;;) {
      for (let i = 0; i < questions.length; i++) {
        const item = questions[i];
        if (i > 0) await slideTo(item);
        setProgress(i);
        await sleep(1300); await waitVisible();
        if (item.write) {
          for (const ch of item.write) { demo.typed.textContent += ch; await sleep(55 + Math.random() * 60); }
          await sleep(500);
          await toast('Enviada para revisão ✍️');
        } else {
          const el = demo.opts.children[item.right];
          el.classList.add('is-press');
          await sleep(160);
          el.classList.remove('is-press');
          el.classList.add('is-right');
          await toast(i === 0 ? 'Muito bem! 🎉' : 'Certo! ⭐');
        }
        await sleep(350);
      }
      setProgress(questions.length);
      demo.done.hidden = false;
      burst();
      await sleep(3200); await waitVisible();
      demo.done.hidden = true;
      await slideTo(questions[0]);
      setProgress(0);
    }
  };
  run();
})();
