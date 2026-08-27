// Shared helpers for the Phaser-based minigames (Pac-Man and Space Invaders
// twists). Phaser itself is NOT bundled into app.js — it is served as its own
// digested static file (/vendor/phaser.min.js) so the ~1.2 MB engine caches
// immutably across app deploys and is only fetched on pages that need it.

let phaserPromise = null

// Lazily load the Phaser script. `src` is the digested URL passed from the
// server via a data attribute (so cache busting follows phx.digest).
export function loadPhaser(src) {
  if (window.Phaser) return Promise.resolve(window.Phaser)
  if (!phaserPromise) {
    phaserPromise = new Promise((resolve, reject) => {
      const script = document.createElement("script")
      script.src = src
      script.async = true
      script.onload = () => resolve(window.Phaser)
      script.onerror = (err) => {
        phaserPromise = null
        script.remove()
        reject(err)
      }
      document.head.appendChild(script)
    })
  }
  return phaserPromise
}

// Parse the game items (words or math problems) from the hook element's
// data-items JSON attribute. Each item: {id, text, category}.
export function parseItems(el) {
  try {
    return JSON.parse(el.dataset.items || "[]")
  } catch (e) {
    console.error("Failed to parse game items:", e)
    return []
  }
}

// Category palette matching the Tailwind classes used by the DOM-based games
// (see CentipedeOverlay.seg_class/1). `bg`/`ring` are Phaser hex ints,
// `text` is a CSS color string for Phaser text objects.
export const CATEGORY_COLORS = {
  yellow: {bg: 0xfef08a, ring: 0xfacc15, text: "#713f12"},
  blue: {bg: 0xbfdbfe, ring: 0x60a5fa, text: "#1e3a8a"},
  red: {bg: 0xfecaca, ring: 0xf87171, text: "#7f1d1d"},
  green: {bg: 0xa7f3d0, ring: 0x34d399, text: "#064e3b"},
  purple: {bg: 0xe9d5ff, ring: 0xc084fc, text: "#581c87"},
  orange: {bg: 0xfed7aa, ring: 0xfb923c, text: "#7c2d12"},
  pink: {bg: 0xfbcfe8, ring: 0xf472b6, text: "#831843"},
  lime: {bg: 0xd9f99d, ring: 0xa3e635, text: "#365314"},
  cyan: {bg: 0xa5f3fc, ring: 0x22d3ee, text: "#164e63"}
}

export function categoryColor(category) {
  return CATEGORY_COLORS[category] || CATEGORY_COLORS.yellow
}

export const GAME_FONT = "'Nunito', ui-rounded, 'Arial Rounded MT Bold', system-ui, sans-serif"

// Audio troubleshooting overlay: add ?sfxdebug=1 to a game URL to see the
// live AudioContext state on screen (for debugging sound on the iPad, where
// there is no console). Returns a cleanup function, or null when inactive.
import * as sfx from "./sfx"

export function installSfxDebug(_el) {
  if (!window.location.search.includes("sfxdebug")) return null
  const div = document.createElement("div")
  div.id = "sfx-debug"
  div.style.cssText =
    "position:fixed;top:76px;left:8px;z-index:9999;background:rgba(0,0,0,.75);" +
    "color:#4ade80;font:13px ui-monospace,monospace;padding:8px 10px;" +
    "border-radius:8px;pointer-events:none;white-space:pre"
  // On document.body, NOT inside the hook element — LiveView patches would
  // remove an unknown child from the overlay on the next render.
  document.body.appendChild(div)
  const timer = setInterval(() => {
    const info = sfx.debugInfo()
    div.textContent = Object.entries(info)
      .map(([k, v]) => `${k}: ${v}`)
      .join("\n")
  }, 400)
  return () => {
    clearInterval(timer)
    div.remove()
  }
}

// Preload hook: warms the browser cache with the Phaser script while the kid
// is doing flashcards, so the first milestone minigame starts instantly.
export const PhaserPreload = {
  mounted() {
    const src = this.el.dataset.phaserSrc
    const idle = window.requestIdleCallback || ((fn) => setTimeout(fn, 2000))
    idle(() => loadPhaser(src).catch(() => {}))
  }
}
