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

