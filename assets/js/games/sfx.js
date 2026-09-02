// Synthesized retro sound effects for the Phaser minigames. Everything is
// generated with the Web Audio API — no audio files, so the app stays fully
// offline-capable and the 8-bit arcade character comes for free.
//
// iOS/iPad needs special care (Mac/desktop browsers need none of this):
// - Audio is only allowed after a user gesture, and WebKit is picky about
//   which events count. We therefore prefer to ride on Phaser's own
//   AudioContext (attach/1), whose unlock machinery is battle-tested on iOS,
//   and keep our own unlock() as a fallback wired to touchend/pointerup/
//   click/keydown.
// - Besides "suspended", iOS contexts can sit in a non-standard
//   "interrupted" state; anything that isn't "running" gets a resume().
// - The silent-mode switch mutes the Web Audio API (though not <audio>
//   media playback). Looping a silent <audio> element flips the audio
//   session to media-playback category so Web Audio plays regardless —
//   the "unmute" trick.
// Every play_* function is a no-op until a context is unlocked and running.

let ctx = null
let ownCtx = false // whether we created ctx (vs. adopted Phaser's)
let master = null
let unmuteAudio = null
let unlockCount = 0

// 50ms of silence as a WAV data URI, for the silent-mode bypass above.
const SILENT_WAV =
  "data:audio/wav;base64,UklGRkQDAABXQVZFZm10IBAAAAABAAEAQB8AAIA+AAACABAAZGF0YSADAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=="

export function unlock() {
  unlockCount += 1
  if (!ctx) {
    const AudioCtx = window.AudioContext || window.webkitAudioContext
    if (!AudioCtx) return
    adoptContext(new AudioCtx(), true)
  }
  resumeIfNeeded()

  // Play a one-sample silent buffer inside the gesture — the belt-and-braces
  // iOS unlock that some WebKit versions require beyond resume().
  try {
    const buffer = ctx.createBuffer(1, 1, 22050)
    const src = ctx.createBufferSource()
    src.buffer = buffer
    src.connect(ctx.destination)
    src.start(0)
  } catch (e) {
    // Context may be closed; the next attach()/unlock() rebuilds it.
  }

  if (!unmuteAudio) {
    unmuteAudio = new Audio(SILENT_WAV)
    unmuteAudio.loop = true
  }
  if (unmuteAudio.paused) unmuteAudio.play().catch(() => {})
}

// Adopt the Phaser sound manager's AudioContext (call from a scene's
// create()). Phaser's unlock handling is the most reliable on iOS, so when
// it has a Web Audio context we play through that instead of our own.
export function attach(soundManager) {
  const phaserCtx = soundManager && soundManager.context
  if (!phaserCtx || phaserCtx === ctx || phaserCtx.state === "closed") return
  adoptContext(phaserCtx, false)
}

// Not exported — switch to a context and rebuild the output chain on it.
// The compressor keeps overlapping effects (auto-fire + explosions) from
// clipping.
function adoptContext(newCtx, own) {
  if (ctx && ownCtx && ctx !== newCtx) {
    // Close abandoned own contexts: iOS caps concurrent AudioContexts.
    try {
      ctx.close()
    } catch (e) {
      // Already closed.
    }
  }
  ctx = newCtx
  ownCtx = own
  const compressor = ctx.createDynamicsCompressor()
  master = ctx.createGain()
  master.gain.value = 0.35
  master.connect(compressor)
  compressor.connect(ctx.destination)
}

// Not exported — iOS contexts can be "suspended" or (non-standard)
// "interrupted"; resume anything that is not running.
function resumeIfNeeded() {
  if (ctx && ctx.state !== "running") {
    try {
      ctx.resume().catch(() => {})
    } catch (e) {
      // Closed context; rebuilt on next attach()/unlock().
    }
  }
}

// Stop the silent-mode-bypass loop and drop the context. Call when a game
// overlay is torn down so the page doesn't hold the audio session open.
// Phaser-owned contexts are closed by the game's own destroy; ours we close.
export function suspend() {
  if (unmuteAudio && !unmuteAudio.paused) unmuteAudio.pause()
  if (ctx && ownCtx) {
    try {
      ctx.close()
    } catch (e) {
      // Already closed.
    }
  }
  ctx = null
  master = null
}

// State snapshot for the ?sfxdebug=1 overlay (see shared.js).
export function debugInfo() {
  return {
    ctx: ctx ? `${ownCtx ? "own" : "phaser"}:${ctx.state}` : "none",
    sampleRate: ctx ? ctx.sampleRate : 0,
    unlocks: unlockCount,
    unmute: unmuteAudio ? (unmuteAudio.paused ? "paused" : "looping") : "none"
  }
}

// Not exported — true when it is safe to schedule sounds.
function ready() {
  if (ctx && ctx.state !== "running") resumeIfNeeded()
  return ctx && master && ctx.state === "running"
}

// Not exported — one oscillator with a pitch sweep and exponential fade-out.
function tone({from, to, dur, type = "square", vol = 0.5, delay = 0}) {
  const t0 = ctx.currentTime + delay
  const osc = ctx.createOscillator()
  const gain = ctx.createGain()
  osc.type = type
  osc.frequency.setValueAtTime(from, t0)
  osc.frequency.exponentialRampToValueAtTime(Math.max(1, to), t0 + dur)
  gain.gain.setValueAtTime(vol, t0)
  gain.gain.exponentialRampToValueAtTime(0.001, t0 + dur)
  osc.connect(gain)
  gain.connect(master)
  osc.start(t0)
  osc.stop(t0 + dur + 0.02)
}

// Not exported — filtered noise burst for explosions.
function boom({dur = 0.4, vol = 0.6, freq = 900, delay = 0}) {
  const t0 = ctx.currentTime + delay
  const length = Math.ceil(ctx.sampleRate * dur)
  const buffer = ctx.createBuffer(1, length, ctx.sampleRate)
  const data = buffer.getChannelData(0)
  for (let i = 0; i < length; i++) {
    data[i] = (Math.random() * 2 - 1) * (1 - i / length)
  }
  const src = ctx.createBufferSource()
  src.buffer = buffer
  const filter = ctx.createBiquadFilter()
  filter.type = "lowpass"
  filter.frequency.setValueAtTime(freq, t0)
  filter.frequency.exponentialRampToValueAtTime(80, t0 + dur)
  const gain = ctx.createGain()
  gain.gain.setValueAtTime(vol, t0)
  gain.gain.exponentialRampToValueAtTime(0.001, t0 + dur)
  src.connect(filter)
  filter.connect(gain)
  gain.connect(master)
  src.start(t0)
}

// --- Pac-Man ---

let wakaHigh = false

// Alternating two-tone "waka" for the little dots.
export function chomp() {
  if (!ready()) return
  wakaHigh = !wakaHigh
  tone(wakaHigh ? {from: 240, to: 420, dur: 0.07, vol: 0.25} : {from: 420, to: 240, dur: 0.07, vol: 0.25})
}

// Rising arpeggio when a word pellet is eaten (power-pellet moment).
export function powerUp() {
  if (!ready()) return
  ;[330, 440, 550, 660, 880].forEach((f, i) => {
    tone({from: f, to: f, dur: 0.09, type: "square", vol: 0.3, delay: i * 0.055})
  })
}

// Quick ascending zip when a frightened ghost is gobbled.
export function ghostEaten() {
  if (!ready()) return
  tone({from: 200, to: 1200, dur: 0.25, type: "sawtooth", vol: 0.35})
}

// Descending slide when the player is caught.
export function death() {
  if (!ready()) return
  tone({from: 700, to: 90, dur: 0.5, type: "sawtooth", vol: 0.4})
  boom({dur: 0.3, vol: 0.25, freq: 500, delay: 0.1})
}

// --- Space Invaders ---

export function shoot() {
  if (!ready()) return
  tone({from: 950, to: 180, dur: 0.09, type: "sawtooth", vol: 0.12})
}

export function pop() {
  if (!ready()) return
  boom({dur: 0.28, vol: 0.4, freq: 1400})
  tone({from: 500, to: 900, dur: 0.12, type: "triangle", vol: 0.2})
}

export function bombDrop() {
  if (!ready()) return
  tone({from: 500, to: 320, dur: 0.1, type: "triangle", vol: 0.12})
}

// Small crackle when a bullet intercepts a falling bomb.
export function bombShot() {
  if (!ready()) return
  boom({dur: 0.18, vol: 0.3, freq: 1800})
}

// Siren-ish wobble announcing a swoop dive.
export function swoop() {
  if (!ready()) return
  ;[0, 1, 2].forEach((i) => {
    tone({from: 600, to: 900, dur: 0.12, type: "triangle", vol: 0.22, delay: i * 0.13})
  })
}

export function shipHit() {
  if (!ready()) return
  boom({dur: 0.5, vol: 0.55, freq: 700})
  tone({from: 400, to: 60, dur: 0.45, type: "sawtooth", vol: 0.3})
}

// --- Math flashcards ---

// Bright ascending arpeggio when the kid picks the right answer.
export function mathCorrect() {
  if (!ready()) return
  ;[523, 659, 784].forEach((f, i) => {
    tone({from: f, to: f, dur: 0.12, type: "triangle", vol: 0.35, delay: i * 0.06})
  })
}

// Gentle descending two-tone when the answer is wrong — clear "no" without
// being harsh on a young player.
export function mathWrong() {
  if (!ready()) return
  ;[349, 262].forEach((f, i) => {
    tone({from: f, to: f * 0.9, dur: 0.22, type: "triangle", vol: 0.3, delay: i * 0.16})
  })
}

// --- Shared endings ---

export function win() {
  if (!ready()) return
  ;[523, 659, 784, 1047].forEach((f, i) => {
    tone({from: f, to: f, dur: 0.16, type: "triangle", vol: 0.35, delay: i * 0.14})
  })
}

export function gameOver() {
  if (!ready()) return
  ;[392, 330, 262, 196].forEach((f, i) => {
    tone({from: f, to: f * 0.94, dur: 0.28, type: "square", vol: 0.3, delay: i * 0.22})
  })
}
