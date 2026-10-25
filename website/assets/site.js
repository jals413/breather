// Breather website: the desktop demo, scroll reveals, copy buttons and GoatCounter click events.

(() => {
  const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  // Count a click or moment in GoatCounter (no cookies, no personal data). Links use data-goatcounter-click.
  const track = (name) => {
    try { window.goatcounter?.count?.({ path: name, title: name, event: true }); } catch {}
  };

  // The floating nav gets a little more solid once you scroll.
  const nav = document.querySelector("nav.top");
  const onScroll = () => nav?.classList.toggle("scrolled", window.scrollY > 24);
  onScroll();
  window.addEventListener("scroll", onScroll, { passive: true });

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
      if (button.dataset.event) track(button.dataset.event);
      try {
        await navigator.clipboard.writeText(code);
        button.textContent = "Copied";
      } catch {
        button.textContent = "Select to copy";
      }
      setTimeout(() => (button.textContent = "Copy"), 1600);
    });
  });

  // FAQ opens.
  document.querySelectorAll(".faq details").forEach((d) => {
    d.addEventListener("toggle", () => { if (d.open) track(`faq-${d.querySelector("summary").textContent.trim().slice(0, 40)}`); });
  });

  // The desktop demo is drawn at 1000×625 and scaled to the screen it sits in.
  const screen = document.getElementById("screen");
  const canvas = document.getElementById("canvas");
  if (!screen || !canvas) return;
  const fit = () => { canvas.style.transform = `scale(${screen.clientWidth / 1000})`; };
  fit();
  new ResizeObserver(fit).observe(screen);

  const demo = document.querySelector(".demo-wrap");
  const island = document.getElementById("island");
  const breakEl = document.getElementById("break");
  const caption = document.getElementById("caption");
  const typed = document.getElementById("typed");
  const ears = document.getElementById("ears-time");
  const cd = document.getElementById("cd-time");
  const hu = document.getElementById("hu-time");
  const bTime = document.getElementById("break-time");
  const bEnd = document.getElementById("break-end");
  const breathe = document.getElementById("breathe");
  const progress = document.getElementById("demo-progress");
  const bar = document.getElementById("demo-bar");
  const skip = document.getElementById("skip-demo");

  const line = "      .shadow(radius: 22)";
  const BREAK_ENDS = 20600;    // when the full-screen break fades out
  const PASS_ENDS = 21800;     // the first pass is "seen" once the caption after the break shows
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

  // While the demo plays the first time, scrolling down waits until it's done. Up still works, and Skip ends it.
  let seen = false;
  let locked = false;
  let lockStart = 0;
  let touchY = 0;
  const downKeys = new Set(["ArrowDown", "PageDown", "End", " ", "Spacebar"]);
  const onWheel = (e) => { if (e.deltaY > 0) e.preventDefault(); };
  const onTouchStart = (e) => { touchY = e.touches[0].clientY; };
  const onTouchMove = (e) => {
    const y = e.touches[0].clientY;
    if (y < touchY) e.preventDefault();
    touchY = y;
  };
  const onKey = (e) => {
    if (downKeys.has(e.key) && !e.target.closest?.("input, textarea, button, summary")) e.preventDefault();
  };
  const tickBar = () => {
    if (!locked) return;
    bar.style.width = `${Math.min(100, ((performance.now() - lockStart) / PASS_ENDS) * 100)}%`;
    requestAnimationFrame(tickBar);
  };
  function lock() {
    if (locked || seen) return;
    locked = true;
    lockStart = performance.now();
    window.addEventListener("wheel", onWheel, { passive: false });
    window.addEventListener("touchstart", onTouchStart, { passive: true });
    window.addEventListener("touchmove", onTouchMove, { passive: false });
    window.addEventListener("keydown", onKey);
    // Centre the demo in the space below the floating nav.
    const r = demo.getBoundingClientRect();
    const navBottom = 76;
    const centre = navBottom + (window.innerHeight - navBottom) / 2;
    window.scrollTo({ top: window.scrollY + r.top + r.height / 2 - centre, behavior: "smooth" });
    progress.hidden = false;
    requestAnimationFrame(tickBar);
  }
  function unlock() {
    if (!locked) return;
    locked = false;
    window.removeEventListener("wheel", onWheel);
    window.removeEventListener("touchstart", onTouchStart);
    window.removeEventListener("touchmove", onTouchMove);
    window.removeEventListener("keydown", onKey);
    progress.hidden = true;
  }
  skip.addEventListener("click", () => { seen = true; unlock(); track("demo-skipped"); });

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
      bEnd.textContent = "Skip";
      bEnd.classList.remove("ready");
      breathe.textContent = "Breathe in";
      const t = every(333, () => {
        left -= 1;
        bTime.textContent = `0:${String(Math.max(left, 0)).padStart(2, "0")}`;
        if (left === 10) { bEnd.textContent = "End break"; bEnd.classList.add("ready"); }
        if (left % 4 === 0) breathe.textContent = breathe.textContent === "Breathe in" ? "Breathe out" : "Breathe in";
        if (left <= 0) clearInterval(t);
      });
    });
    after(BREAK_ENDS, () => {
      breakEl.classList.remove("on");
      say("Back to work, refreshed. Next break in 20 minutes.");
    });
    after(PASS_ENDS, () => {
      if (locked) { seen = true; unlock(); track("demo-watched"); }
    });
    after(24500, run);
  }

  // Start when most of the demo is on screen; pause when it leaves.
  let running = false;
  new IntersectionObserver(([entry]) => {
    const visible = entry.intersectionRect.height;
    const enough = entry.intersectionRatio >= 0.6 || visible >= window.innerHeight * 0.6;
    if (enough && !running) {
      running = true;
      run();
      lock();
    }
    if (!entry.isIntersecting && running) {
      running = false;
      timers.forEach(clearTimeout);
      unlock();
    }
  }, { threshold: [0, 0.3, 0.6, 0.8, 1] }).observe(screen);
})();
