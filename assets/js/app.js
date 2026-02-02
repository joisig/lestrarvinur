// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/lestrarvinur_phoenix"
import topbar from "../vendor/topbar"

// Custom hooks for Lestrarvinur
const Hooks = {}

// Audio player hook for playing word audio
Hooks.AudioPlayer = {
  mounted() {
    this.el.addEventListener("click", (e) => {
      e.stopPropagation() // Prevent triggering the card next action
      const audioUrl = this.el.dataset.audioUrl
      if (audioUrl) {
        const audio = new Audio(audioUrl)
        audio.play().catch(err => console.error("Audio playback failed:", err))
      }
    })
  }
}

// Dragon Fling hook for the minigame
Hooks.DragonFling = {
  mounted() {
    this.activePointers = new Map()
    this.animatingWords = new Set() // Track words being animated
    this.hitCanvas = null
    this.hitCtx = null
    this.setupHitDetection()
    this.setupEventListeners()
  },

  // Create a canvas with the dragon image for pixel-based hit detection
  setupHitDetection() {
    const dragonImg = this.el.querySelector(".dragon-container img")
    if (!dragonImg) return

    // Wait for image to load if needed
    if (dragonImg.complete) {
      this.createHitCanvas(dragonImg)
    } else {
      dragonImg.onload = () => this.createHitCanvas(dragonImg)
    }
  },

  createHitCanvas(img) {
    this.hitCanvas = document.createElement("canvas")
    this.hitCanvas.width = img.naturalWidth
    this.hitCanvas.height = img.naturalHeight
    this.hitCtx = this.hitCanvas.getContext("2d", { willReadFrequently: true })
    this.hitCtx.drawImage(img, 0, 0)

    // Sample corner pixel to detect background color
    try {
      const cornerPixel = this.hitCtx.getImageData(5, 5, 1, 1).data
      this.bgColor = { r: cornerPixel[0], g: cornerPixel[1], b: cornerPixel[2] }
      console.log("Dragon background color:", this.bgColor)
    } catch (e) {
      this.bgColor = { r: 255, g: 255, b: 255 } // Fallback to white
    }
  },

  // Check if a point (in image percentage coordinates) hits a non-background pixel
  isNonBackgroundHit(hitXPercent, hitYPercent) {
    if (!this.hitCtx) return true // Fallback to always hit if canvas not ready

    const x = Math.floor((hitXPercent / 100) * this.hitCanvas.width)
    const y = Math.floor((hitYPercent / 100) * this.hitCanvas.height)

    try {
      const pixel = this.hitCtx.getImageData(x, y, 1, 1).data
      const r = pixel[0], g = pixel[1], b = pixel[2]

      // Check if pixel is close to background color (within threshold)
      const threshold = 30
      const isBackground =
        Math.abs(r - this.bgColor.r) < threshold &&
        Math.abs(g - this.bgColor.g) < threshold &&
        Math.abs(b - this.bgColor.b) < threshold

      return !isBackground
    } catch (e) {
      console.log("Hit detection error:", e)
      return true // Fallback to hit on error
    }
  },

  setupEventListeners() {
    const container = this.el

    // Mouse events
    container.addEventListener("mousedown", (e) => {
      const target = e.target.closest(".word-flingable")
      if (target) {
        e.preventDefault()
        this.handlePointerDown(e.clientX, e.clientY, target, "mouse")
      }
    })
    document.addEventListener("mousemove", (e) => this.handlePointerMove(e.clientX, e.clientY, "mouse"))
    document.addEventListener("mouseup", (e) => this.handlePointerUp("mouse"))

    // Touch events
    container.addEventListener("touchstart", (e) => {
      for (const touch of e.changedTouches) {
        const target = touch.target.closest(".word-flingable")
        if (target) {
          e.preventDefault()
          this.handlePointerDown(touch.clientX, touch.clientY, target, touch.identifier)
        }
      }
    }, { passive: false })

    document.addEventListener("touchmove", (e) => {
      let shouldPrevent = false
      for (const touch of e.changedTouches) {
        if (this.activePointers.has(touch.identifier)) {
          shouldPrevent = true
          this.handlePointerMove(touch.clientX, touch.clientY, touch.identifier)
        }
      }
      if (shouldPrevent) e.preventDefault()
    }, { passive: false })

    document.addEventListener("touchend", (e) => {
      for (const touch of e.changedTouches) {
        this.handlePointerUp(touch.identifier)
      }
    })
  },

  handlePointerDown(x, y, target, pointerId) {
    if (this.animatingWords.has(target.dataset.wordId)) return

    const rect = target.getBoundingClientRect()

    this.activePointers.set(pointerId, {
      element: target,
      wordId: target.dataset.wordId,
      startRect: rect,
      startX: x,
      startY: y,
      currentX: x,
      currentY: y,
      prevX: x,
      prevY: y,
      prevTime: performance.now(),
      vx: 0,
      vy: 0
    })

    target.style.zIndex = "100"
    target.style.transition = "none"
    target.style.cursor = "grabbing"
  },

  handlePointerMove(x, y, pointerId) {
    const p = this.activePointers.get(pointerId)
    if (!p) return

    const now = performance.now()
    const dt = now - p.prevTime

    if (dt > 0) {
      // Smooth velocity with some averaging
      const newVx = (x - p.prevX) / dt * 1000
      const newVy = (y - p.prevY) / dt * 1000
      p.vx = p.vx * 0.5 + newVx * 0.5
      p.vy = p.vy * 0.5 + newVy * 0.5
    }

    p.prevX = p.currentX
    p.prevY = p.currentY
    p.prevTime = now
    p.currentX = x
    p.currentY = y

    const dx = x - p.startX
    const dy = y - p.startY
    p.element.style.transform = `translate(${dx}px, ${dy}px) scale(1.05)`
  },

  handlePointerUp(pointerId) {
    const p = this.activePointers.get(pointerId)
    if (!p) return
    this.activePointers.delete(pointerId)

    const el = p.element
    const wordId = p.wordId
    const speed = Math.sqrt(p.vx * p.vx + p.vy * p.vy)

    // Need upward velocity and minimum speed
    if (p.vy < -200 && speed > 300) {
      const dragonContainer = this.el.querySelector(".dragon-container")
      const dragonImg = this.el.querySelector(".dragon-container img")
      if (!dragonContainer || !dragonImg) {
        console.log("No dragon container or img found")
        return this.snapBack(el)
      }

      const containerRect = dragonContainer.getBoundingClientRect()
      const imgRect = dragonImg.getBoundingClientRect()
      const elRect = el.getBoundingClientRect()

      // Normalize velocity to get direction
      const dirX = p.vx / speed
      const dirY = p.vy / speed

      // Calculate flight distance based on speed
      const flightTime = 0.4 // seconds
      const distance = Math.min(speed * flightTime, 800)

      // Start from element's current visual center
      const startX = elRect.left + elRect.width / 2
      const startY = elRect.top + elRect.height / 2

      // Where will it land?
      const endX = startX + dirX * distance
      const endY = startY + dirY * distance

      console.log("Fling:", { startX, startY, endX, endY, dirX, dirY, distance, imgRect: { left: imgRect.left, right: imgRect.right, top: imgRect.top, bottom: imgRect.bottom } })

      // Check if it hits dragon image (lenient - just needs to be in upper half of screen going toward dragon)
      const hitsDragon = endY < imgRect.bottom + 50

      if (hitsDragon) {
        // Clamp end position to dragon image bounds for the POW
        const clampedEndX = Math.max(imgRect.left + 20, Math.min(imgRect.right - 20, endX))
        const clampedEndY = Math.max(imgRect.top + 20, Math.min(imgRect.bottom - 20, endY))
        this.animatingWords.add(wordId)

        // Calculate hit position as percentage of the IMAGE (for pixel detection)
        const imgHitXPercent = ((clampedEndX - imgRect.left) / imgRect.width) * 100
        const imgHitYPercent = ((clampedEndY - imgRect.top) / imgRect.height) * 100

        // Check if we hit a non-background part of the dragon
        const isActualHit = this.isNonBackgroundHit(imgHitXPercent, imgHitYPercent)
        console.log("Hit check:", { imgHitXPercent, imgHitYPercent, isActualHit })

        // Calculate hit position as percentage of the CONTAINER (for POW display)
        const hitX = ((clampedEndX - containerRect.left) / containerRect.width) * 100
        const hitY = ((clampedEndY - containerRect.top) / containerRect.height) * 100

        // Clone element for animation (so it's outside LiveView's control)
        const clone = el.cloneNode(true)
        clone.removeAttribute("id")
        clone.removeAttribute("phx-hook")
        clone.classList.remove("word-slide-in") // Remove entrance animation
        clone.style.position = "fixed"
        // Position clone at element's current visual position
        clone.style.left = elRect.left + "px"
        clone.style.top = elRect.top + "px"
        clone.style.width = elRect.width + "px"
        clone.style.height = elRect.height + "px"
        clone.style.margin = "0"
        clone.style.transform = "none" // Reset any transform from dragging
        clone.style.zIndex = "9999"
        clone.style.pointerEvents = "none"
        // Append to the dragon game container so it's in the same stacking context
        this.el.appendChild(clone)

        // Hide original immediately
        el.style.visibility = "hidden"

        // Animate the clone flying to target (from element center to clamped end position)
        const flyDx = clampedEndX - startX
        const flyDy = clampedEndY - startY
        const rotation = dirX * 360 // Spin based on direction

        // Trigger animation on next frame
        requestAnimationFrame(() => {
          clone.style.transition = `transform ${flightTime}s ease-out, opacity ${flightTime}s ease-in`
          clone.style.transform = `translate(${flyDx}px, ${flyDy}px) scale(0.2) rotate(${rotation}deg)`
          clone.style.opacity = "0"
        })

        // Wait for animation to complete, then notify server
        setTimeout(() => {
          clone.remove()
          this.animatingWords.delete(wordId)
          this.pushEvent("word_flung", {
            word_id: wordId,
            is_hit: isActualHit,
            hit_x: Math.round(Math.max(10, Math.min(90, hitX))),
            hit_y: Math.round(Math.max(10, Math.min(90, hitY)))
          })
        }, flightTime * 1000 + 50)
      } else {
        this.snapBack(el)
      }
    } else {
      this.snapBack(el)
    }
  },

  snapBack(el) {
    el.style.transition = "transform 0.25s ease-out"
    el.style.transform = "translate(0, 0) scale(1)"
    el.style.zIndex = ""
    el.style.cursor = "grab"
  }
}

// Audio recorder hook for recording from browser
Hooks.AudioRecorder = {
  mounted() {
    this.mediaRecorder = null
    this.chunks = []
    this.recordedBlob = null

    // Get supported MIME type
    const getSupportedMimeType = () => {
      const types = [
        'audio/webm;codecs=opus',
        'audio/webm',
        'audio/ogg',
        'audio/mp4',
        'audio/mpeg'
      ]
      for (const type of types) {
        if (MediaRecorder.isTypeSupported(type)) {
          return type
        }
      }
      return 'audio/webm' // fallback
    }

    // Start recording
    this.handleEvent("start-recording", () => {
      navigator.mediaDevices.getUserMedia({ audio: true })
        .then(stream => {
          const mimeType = getSupportedMimeType()
          this.mediaRecorder = new MediaRecorder(stream, { mimeType })
          this.chunks = []

          this.mediaRecorder.ondataavailable = (e) => {
            if (e.data.size > 0) {
              this.chunks.push(e.data)
            }
          }

          this.mediaRecorder.onstop = () => {
            const finalMimeType = this.mediaRecorder.mimeType || mimeType
            this.recordedBlob = new Blob(this.chunks, { type: finalMimeType })

            // Stop all tracks
            stream.getTracks().forEach(track => track.stop())

            // Send recording to server
            const reader = new FileReader()
            reader.onloadend = () => {
              const base64data = reader.result.split(',')[1]
              const extension = finalMimeType.includes('webm') ? 'webm' :
                               finalMimeType.includes('ogg') ? 'ogg' :
                               finalMimeType.includes('mp4') ? 'm4a' : 'webm'

              this.pushEvent("save-recording", {
                audio_data: base64data,
                mime_type: finalMimeType,
                extension: extension
              })
            }
            reader.readAsDataURL(this.recordedBlob)
          }

          this.mediaRecorder.start()
          this.pushEvent("recording-started", {})
        })
        .catch(err => {
          console.error("Error accessing microphone:", err)
          this.pushEvent("recording-error", { error: err.message })
        })
    })

    // Stop recording
    this.handleEvent("stop-recording", () => {
      if (this.mediaRecorder && this.mediaRecorder.state !== 'inactive') {
        this.mediaRecorder.stop()
      }
    })

    // Play preview
    this.handleEvent("play-preview", () => {
      if (this.recordedBlob) {
        const audio = new Audio(URL.createObjectURL(this.recordedBlob))
        audio.play().catch(err => console.error("Playback error:", err))
      }
    })

    // Play saved audio automatically after 200ms
    this.handleEvent("play-saved-audio", ({url}) => {
      setTimeout(() => {
        if (url) {
          const audio = new Audio(url)
          audio.play().catch(err => console.error("Saved audio playback failed:", err))
        }
      }, 200)
    })
  }
}

// Listen for play-audio events (dispatched from LiveView via JS.dispatch)
window.addEventListener("play-audio", (e) => {
  const url = e.detail.url
  if (url) {
    const audio = new Audio(url)
    audio.play().catch(err => console.error("Audio playback failed:", err))
  }
})

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, ...Hooks},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

