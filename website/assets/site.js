// Breather website: the notch demo, install tabs and copy buttons. No tracking, no dependencies.

(() => {
  // Notch demo: cycles through the island's states like the real app.
  const island = document.getElementById("island");
  const caption = document.getElementById("stage-caption");
  const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  if (island) {
    const steps = [
      { state: "resting", caption: "Quiet until a break is near.", ms: 2200 },
      { state: "peek", caption: "A countdown appears beside the notch…", ms: 2600 },
      { state: "headsup", caption: "…then a heads-up a minute before. Start now, snooze or skip.", ms: 4200 },
      { state: "peek", caption: "It waits until you stop typing.", ms: 1800 },
      { state: "countdown", caption: "Five seconds, then your break fills the screen.", ms: 3200 },
      { state: "resting", caption: "Break time. Look at something far away.", ms: 1800 },
      { state: "toast", caption: "Step away from your Mac and it counts as a break.", ms: 3600 },
    ];
    const set = (s) => {
      island.dataset.state = s.state;
      if (caption) caption.textContent = s.caption;
    };
    if (reduce) {
      set(steps[2]);
    } else {
      let i = 0;
      const tick = () => {
        set(steps[i]);
        if (steps[i].state === "countdown") countdown();
        setTimeout(tick, steps[i].ms);
        i = (i + 1) % steps.length;
      };
      tick();
    }
    function countdown() {
      const el = document.getElementById("cd-time");
      let n = 5;
      el.textContent = n;
      const t = setInterval(() => {
        n -= 1;
        if (n <= 0) return clearInterval(t);
        el.textContent = n;
      }, 600);
    }
  }

  // Install tabs.
  document.querySelectorAll(".tab").forEach((tab) => {
    tab.addEventListener("click", () => {
      document.querySelectorAll(".tab").forEach((t) => t.setAttribute("aria-selected", t === tab ? "true" : "false"));
      document.querySelectorAll(".panel").forEach((p) => p.classList.toggle("active", p.id === tab.dataset.panel));
    });
  });

  // Copy buttons.
  document.querySelectorAll(".copy").forEach((button) => {
    button.addEventListener("click", async () => {
      const code = button.parentElement.querySelector("code").textContent;
      try {
        await navigator.clipboard.writeText(code);
        button.textContent = "Copied";
      } catch {
        button.textContent = "Select & copy";
      }
      setTimeout(() => (button.textContent = "Copy"), 1600);
    });
  });
})();
