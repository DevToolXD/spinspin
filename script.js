// ===== 참가자 목록 =====
let names = ["참가자 1", "참가자 2", "참가자 3", "참가자 4", "참가자 5", "참가자 6"];

// 🎯 항상 당첨되는 칸의 인덱스 (0부터 시작 → 1 = "2번째 칸")
const RIGGED_INDEX = 1;

const colors = [
  "#ff6b6b", "#ffd24c", "#4dd0a7", "#5b9dff",
  "#c98bff", "#ff9f6b", "#6be8ff", "#ff7fb6",
];

const canvas = document.getElementById("wheel");
const ctx = canvas.getContext("2d");
const spinBtn = document.getElementById("spinBtn");
const resultEl = document.getElementById("result");
const namesInput = document.getElementById("namesInput");
const applyBtn = document.getElementById("applyBtn");

const R = canvas.width / 2;
let rotation = 0;          // 현재 회전 각 (라디안)
let velocity = 0;          // 현재 각속도
let holding = false;       // 버튼을 누르고 있는 중인지
let stopping = false;      // 멈추는 애니메이션 중인지
let rafId = null;

const MAX_VELOCITY = 0.45; // 최대 각속도
const ACCEL = 0.012;       // 누르고 있을 때 가속도

// ===== 룰렛 그리기 =====
function draw() {
  const n = names.length;
  const seg = (2 * Math.PI) / n;

  ctx.clearRect(0, 0, canvas.width, canvas.height);
  ctx.save();
  ctx.translate(R, R);
  ctx.rotate(rotation);

  for (let i = 0; i < n; i++) {
    // 12시 방향(-90°)을 기준으로 시계방향 배치
    const start = -Math.PI / 2 + i * seg;
    const end = start + seg;

    ctx.beginPath();
    ctx.moveTo(0, 0);
    ctx.arc(0, 0, R - 6, start, end);
    ctx.closePath();
    ctx.fillStyle = colors[i % colors.length];
    ctx.fill();

    // 칸 텍스트
    ctx.save();
    ctx.rotate(start + seg / 2);
    ctx.textAlign = "right";
    ctx.fillStyle = "#1a1f3a";
    ctx.font = "bold 16px system-ui, sans-serif";
    ctx.fillText(names[i], R - 24, 6);
    ctx.restore();
  }

  // 가운데 허브
  ctx.beginPath();
  ctx.arc(0, 0, 26, 0, 2 * Math.PI);
  ctx.fillStyle = "#1a1f3a";
  ctx.fill();
  ctx.lineWidth = 4;
  ctx.strokeStyle = "#ffd24c";
  ctx.stroke();

  ctx.restore();
}

// 포인터(12시) 아래에 특정 인덱스를 맞추기 위한 회전 잔여각
function residueForIndex(index) {
  const seg = (2 * Math.PI) / names.length;
  let r = -(index + 0.5) * seg;
  return ((r % (2 * Math.PI)) + 2 * Math.PI) % (2 * Math.PI);
}

// ===== 누르고 있는 동안: 가속 회전 =====
function holdLoop() {
  if (!holding) return;
  velocity = Math.min(MAX_VELOCITY, velocity + ACCEL);
  rotation += velocity;
  draw();
  rafId = requestAnimationFrame(holdLoop);
}

// ===== 버튼을 떼면: 2번째 칸에 멈추도록 감속 =====
function startStopping() {
  stopping = true;

  // 속도에 비례한 추가 회전 바퀴 수
  const extraTurns = 4 + Math.round((velocity / MAX_VELOCITY) * 4);
  let target = rotation + extraTurns * 2 * Math.PI;

  // 목표 각을 2번째 칸(RIGGED_INDEX) 잔여각에 맞춤
  const targetRes = residueForIndex(RIGGED_INDEX);
  const curMod = ((target % (2 * Math.PI)) + 2 * Math.PI) % (2 * Math.PI);
  let diff = (targetRes - curMod + 2 * Math.PI) % (2 * Math.PI);
  target += diff;

  const startRot = rotation;
  const totalDelta = target - startRot;
  const duration = 2600 + velocity * 1200;
  const startTime = performance.now();

  function ease(t) { return 1 - Math.pow(1 - t, 3); } // easeOutCubic

  function decelLoop(now) {
    const t = Math.min(1, (now - startTime) / duration);
    rotation = startRot + totalDelta * ease(t);
    draw();
    if (t < 1) {
      rafId = requestAnimationFrame(decelLoop);
    } else {
      rotation = target;
      draw();
      stopping = false;
      velocity = 0;
      showResult();
    }
  }
  rafId = requestAnimationFrame(decelLoop);
}

function showResult() {
  resultEl.textContent = `🎉 당첨: ${names[RIGGED_INDEX]}`;
  resultEl.classList.add("win");
}

// ===== 버튼 누르기 / 떼기 =====
function onPressStart(e) {
  e.preventDefault();
  if (stopping) return;
  holding = true;
  velocity = velocity || 0.05;
  spinBtn.classList.add("holding");
  resultEl.textContent = "";
  resultEl.classList.remove("win");
  cancelAnimationFrame(rafId);
  holdLoop();
}

function onPressEnd(e) {
  e.preventDefault();
  if (!holding) return;
  holding = false;
  spinBtn.classList.remove("holding");
  cancelAnimationFrame(rafId);
  startStopping();
}

spinBtn.addEventListener("mousedown", onPressStart);
spinBtn.addEventListener("touchstart", onPressStart, { passive: false });
spinBtn.addEventListener("mouseup", onPressEnd);
spinBtn.addEventListener("mouseleave", onPressEnd);
spinBtn.addEventListener("touchend", onPressEnd, { passive: false });
spinBtn.addEventListener("touchcancel", onPressEnd, { passive: false });

// ===== 참가자 설정 =====
applyBtn.addEventListener("click", () => {
  const list = namesInput.value
    .split("\n")
    .map((s) => s.trim())
    .filter(Boolean);
  if (list.length >= 2) {
    names = list;
    resultEl.textContent = "";
    resultEl.classList.remove("win");
    rotation = 0;
    draw();
  } else {
    alert("최소 2명 이상 입력해주세요!");
  }
});

// 초기화
namesInput.value = names.join("\n");
draw();
