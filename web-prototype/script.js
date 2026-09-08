const notch = document.getElementById("notch");
const notchToggle = document.getElementById("notchToggle");
const miniStatus = document.getElementById("miniStatus");
const activityTitle = document.getElementById("activityTitle");
const clockStatus = document.getElementById("clockStatus");
const batteryStatus = document.getElementById("batteryStatus");
const actionFeedback = document.getElementById("actionFeedback");
const timerValue = document.getElementById("timerValue");
const timerToggle = document.getElementById("timerToggle");
const dropZone = document.getElementById("dropZone");
const dropMessage = document.getElementById("dropMessage");

let isExpanded = false;
let timerRunning = false;
let totalSeconds = 25 * 60;
let timerInterval = null;
let isMuted = false;

function setExpanded(next) {
  isExpanded = next;
  notch.classList.toggle("expanded", next);
  notch.classList.toggle("collapsed", !next);
  notchToggle.setAttribute("aria-expanded", String(next));
}

function formatTime(value) {
  const minutes = Math.floor(value / 60)
    .toString()
    .padStart(2, "0");
  const seconds = (value % 60).toString().padStart(2, "0");
  return `${minutes}:${seconds}`;
}

function renderTimer() {
  timerValue.textContent = formatTime(totalSeconds);
  clockStatus.textContent = timerRunning ? `Focus ${formatTime(totalSeconds)}` : "Idle";
}

function tickClock() {
  const now = new Date();
  batteryStatus.textContent = `${now.toLocaleTimeString([], {
    hour: "2-digit",
    minute: "2-digit",
  })} local`;
}

function startTimer() {
  if (timerRunning) {
    return;
  }

  timerRunning = true;
  timerToggle.textContent = "Pause";
  miniStatus.textContent = "Focusing";
  activityTitle.textContent = "Focus Timer";
  renderTimer();

  timerInterval = window.setInterval(() => {
    if (totalSeconds > 0) {
      totalSeconds -= 1;
      renderTimer();
      return;
    }

    window.clearInterval(timerInterval);
    timerRunning = false;
    timerToggle.textContent = "Restart";
    miniStatus.textContent = "Completed";
    actionFeedback.textContent = "Focus sprint finished. Time for a short reset.";
    activityTitle.textContent = "Session Complete";
  }, 1000);
}

function pauseTimer() {
  timerRunning = false;
  window.clearInterval(timerInterval);
  timerToggle.textContent = "Resume";
  miniStatus.textContent = "Paused";
  renderTimer();
}

notchToggle.addEventListener("click", () => {
  setExpanded(!isExpanded);
});

notch.addEventListener("mouseenter", () => {
  setExpanded(true);
});

notch.addEventListener("mouseleave", () => {
  if (!timerRunning) {
    setExpanded(false);
  }
});

document.querySelectorAll("[data-action]").forEach((button) => {
  button.addEventListener("click", () => {
    const action = button.getAttribute("data-action");

    if (action === "focus") {
      totalSeconds = 25 * 60;
      renderTimer();
      startTimer();
      actionFeedback.textContent = "Focus mode is live. Notifications are visually minimized.";
      return;
    }

    if (action === "break") {
      totalSeconds = 5 * 60;
      pauseTimer();
      renderTimer();
      miniStatus.textContent = "Break";
      activityTitle.textContent = "Break Mode";
      actionFeedback.textContent = "Short break loaded. Stretch, breathe, then dive back in.";
      return;
    }

    if (action === "mute") {
      isMuted = !isMuted;
      miniStatus.textContent = isMuted ? "Muted" : "Sound On";
      activityTitle.textContent = isMuted ? "Silent Mode" : "Focus Timer";
      actionFeedback.textContent = isMuted
        ? "Muted for distraction-free work."
        : "Audio restored and ready.";
    }
  });
});

timerToggle.addEventListener("click", () => {
  if (totalSeconds === 0) {
    totalSeconds = 25 * 60;
    renderTimer();
    startTimer();
    return;
  }

  if (timerRunning) {
    pauseTimer();
    return;
  }

  startTimer();
});

["dragenter", "dragover"].forEach((eventName) => {
  notch.addEventListener(eventName, (event) => {
    event.preventDefault();
    setExpanded(true);
    notch.classList.add("dragging");
    dropZone.classList.add("active");
    dropMessage.textContent = "Release to pin this file to the notch.";
  });
});

["dragleave", "dragend"].forEach((eventName) => {
  notch.addEventListener(eventName, () => {
    notch.classList.remove("dragging");
    dropZone.classList.remove("active");
    dropMessage.textContent = "Drag a file here and the notch will react.";
  });
});

notch.addEventListener("drop", (event) => {
  event.preventDefault();
  notch.classList.remove("dragging");
  dropZone.classList.remove("active");

  const file = event.dataTransfer?.files?.[0];

  if (!file) {
    dropMessage.textContent = "Drop received, but no file metadata was available.";
    return;
  }

  miniStatus.textContent = "Captured";
  activityTitle.textContent = "File Received";
  dropMessage.textContent = `${file.name} added to the notch surface.`;
  actionFeedback.textContent = `Ready to attach ${file.name} (${Math.max(
    1,
    Math.round(file.size / 1024)
  )} KB) to a follow-up action.`;
});

tickClock();
renderTimer();
window.setInterval(tickClock, 1000 * 30);
