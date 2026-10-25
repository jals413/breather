// Breather website: the desktop demo, scroll reveals and copy buttons. No tracking, no dependencies.

(() => {
  const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  // Reveal sections as they scroll into view.
  const observer = new IntersectionObserver((entries) => {
    entries.forEach((e) => {
      if (e.isIntersecting) {
        e.target.classList.add("in");
        observer.unobserve(e.target);
      }
    });
  }, { threshold: 0.15 });
  document.querySelectorAll(".reveal").forEach((el) => observer.observe(el));

  // Copy buttons.
  document.querySelectorAll(".copy").forEach((button) => {
    button.addEventListener("click", async () => {
      const code = button.parentElement.querySelector("code").textContent;
      try {
        await navigator.clipboard.writeText(code);
        button.textContent = "Copied";
      } catch {
        button.textContent = "Select to copy";
      }
      setTimeout(() => (button.textContent = "Copy"), 1600);
    });
  });

  // The desktop demo is drawn at 1000×625 and scaled to the screen it sits in.
  const screen = document.getElementById("screen");
  const canvas = document.getElementById("canvas");
  if (!screen || !canvas) return;
  const fit = () => { canvas.style.transform = `scale(${screen.clientWidth / 1000})`; };
  fit();
  new ResizeObserver(fit).observe(screen);

  const island = document.getElementById("island");
  const breakEl = document.getElementById("break");
  const caption = document.getElementById("caption");
  const typed = document.getElementById("typed");
  const ears = document.getElementById("ears-time");
  const cd = document.getElementById("cd-time");
  const hu = document.getElementById("hu-time");
  const bTime = document.getElementById("break-time");
  const bProg = document.getElementById("break-prog");
  const breathe = document.getElementById("breathe");

  const line = "      .shadow(radius: 22)";
  let timers = [];
  const after = (ms, fn) => timers.push(setTimeout(fn, ms));
  const every = (ms, fn) => { const t = setInterval(fn, ms); timers.push(t); return t; };
  const say = (text) => {
    caption.style.opacity = 0;
    setTimeout(() => { caption.textContent = text; caption.style.opacity = 1; }, 250);
  };

  if (reduce) {
    island.dataset.state = "headsup";
    say("A minute before each break, Breather grows out of the notch.");
    return;
  }

  function run() {
    timers.forEach(clearTimeout);
    timers = [];
    island.dataset.state = "resting";
    breakEl.classList.remove("on");
    typed.textContent = "";
    say("You're in the flow.");

    // Typing away.
    let i = 0;
    const typer = every(110, () => {
      typed.textContent = line.slice(0, ++i);
      if (i >= line.length) { i = 0; }
    });

    after(2200, () => {
      island.dataset.state = "peek";
      ears.textContent = "1:00";
      say("A gentle countdown appears beside the notch.");
    });
    after(4200, () => {
      island.dataset.state = "headsup";
      let s = 58;
      hu.textContent = "0:58";
      const t = every(1000, () => { s -= 1; hu.textContent = `0:${String(Math.max(s, 0)).padStart(2, "0")}`; });
      after(4300, () => clearInterval(t));
      say("A heads-up a minute before. Start now, snooze, or skip.");
    });
    after(8800, () => {
      island.dataset.state = "peek";
      ears.textContent = "0:04";
      say("Still typing? Your break waits for a pause.");
    });
    after(11000, () => {
      clearInterval(typer);
      island.dataset.state = "countdown";
      let n = 3;
      cd.textContent = n;
      const t = every(700, () => { n -= 1; if (n > 0) cd.textContent = n; else clearInterval(t); });
      say("Then, gently, look away.");
    });
    after(13200, () => {
      island.dataset.state = "resting";
      breakEl.classList.add("on");
      say("Your whole screen becomes the break. Every display.");
      // A 20-second break, shown at 3× speed.
      let left = 20;
      bTime.textContent = "0:20";
      bProg.style.strokeDashoffset = 0;
      breathe.textContent = "Breathe in";
      const t = every(333, () => {
        left -= 1;
        bTime.textContent = `0:${String(Math.max(left, 0)).padStart(2, "0")}`;
        bProg.style.strokeDashoffset = 326.7 * (1 - left / 20);
        if (left % 4 === 0) breathe.textContent = breathe.textContent === "Breathe in" ? "Breathe out" : "Breathe in";
        if (left <= 0) clearInterval(t);
      });
    });
    after(20600, () => {
      breakEl.classList.remove("on");
      say("Back to work, refreshed. Next break in 20 minutes.");
    });
    after(24500, run);
  }

  // Start when the demo is on screen; pause when it isn't.
  let running = false;
  new IntersectionObserver(([entry]) => {
    if (entry.isIntersecting && !running) { running = true; run(); }
    if (!entry.isIntersecting && running) { running = false; timers.forEach(clearTimeout); }
  }, { threshold: 0.3 }).observe(screen);
})();
