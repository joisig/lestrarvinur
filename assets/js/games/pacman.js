// Pac-Man twist minigame ("Orðagleypir"). A maze chomper where the special
// pellets are the words (or math problems) the kid just practiced. Eating a
// word frightens the ghosts for a few seconds, power-pellet style. Getting
// caught costs a life (5 spare lives plus the one you start with); running
// out before clearing every word is Game Over.
//
// Server contract (mirrors the centipede game):
//   - reads items from data-items JSON: [{id, text, category}]
//   - pushes "pacman_eat" {id} each time a word pellet is eaten (drives the
//     server-side counter display)
//   - pushes "pacman_cleared" {} once EVERY word pellet AND every plain dot
//     has been eaten (the dots only exist client-side, so completion is
//     client-driven), after the "Vel gert!" banner has shown
//   - pushes "pacman_game_over" {} after the Game Over screen has shown
//   - skip button is server-side (skip_pacman_game), outside the canvas
import {loadPhaser, parseItems, categoryColor, GAME_FONT} from "./shared"
import * as sfx from "./sfx"

const TILE = 96
const MAZE = [
  "###############",
  "#......#......#",
  "#.###.###.###.#",
  "#.#.........#.#",
  "#.#.##.#.##.#.#",
  "#......G......#",
  "#.#.##.#.##.#.#",
  "#.#....P....#.#",
  "#.###.###.###.#",
  "#......#......#",
  "###############"
]
const COLS = 15
const ROWS = 11
const HEADER = 96 // banner strip above the maze
const WIDTH = COLS * TILE // 1440
const HEIGHT = ROWS * TILE + HEADER // 1152

// Open tiles where word pellets get placed, spread around the maze.
const WORD_SPOTS = [
  [1, 1], [13, 1], [1, 9], [13, 9], [1, 5], [13, 5],
  [3, 3], [11, 3], [3, 7], [11, 7], [5, 9], [9, 1]
]

const DIRS = {
  up: {x: 0, y: -1},
  down: {x: 0, y: 1},
  left: {x: -1, y: 0},
  right: {x: 1, y: 0}
}
const OPPOSITE = {up: "down", down: "up", left: "right", right: "left"}

const PLAYER_SPEED = 340 // px/s
const GHOST_SPEED = 250
const GHOST_SCARED_SPEED = 160
const FRIGHT_MS = 4000
const EXTRA_LIVES = 5 // spare lives on top of the one in play

export const PacmanGame = {
  mounted() {
    this.dead = false
    // iOS only allows audio after a user gesture; unlock() is idempotent.
    this.unlockAudio = () => sfx.unlock()
    this.el.addEventListener("pointerdown", this.unlockAudio)
    window.addEventListener("keydown", this.unlockAudio)
    const items = parseItems(this.el)
    loadPhaser(this.el.dataset.phaserSrc)
      .then((Phaser) => {
        if (this.dead) return
        this.game = createGame(Phaser, this, items)
      })
      .catch((err) => console.error("Phaser load failed:", err))
  },

  destroyed() {
    this.dead = true
    this.el.removeEventListener("pointerdown", this.unlockAudio)
    window.removeEventListener("keydown", this.unlockAudio)
    if (this.game) {
      this.game.destroy(true)
      this.game = null
    }
  }
}

// Not exported for reuse — builds the Phaser game bound to a hook instance.
function createGame(Phaser, hook, items) {
  const parent = hook.el.querySelector("[data-game-arena]")

  function isWall(cx, cy) {
    if (cx < 0 || cy < 0 || cx >= COLS || cy >= ROWS) return true
    return MAZE[cy][cx] === "#"
  }

  function tileCenter(cx, cy) {
    return {x: cx * TILE + TILE / 2, y: HEADER + cy * TILE + TILE / 2}
  }

  // Grid walker shared by player and ghosts: entities glide from tile center
  // to tile center; direction decisions only happen when a tile is reached.
  function makeWalker(cx, cy, speed) {
    return {from: {x: cx, y: cy}, to: null, progress: 0, speed, dir: null}
  }

  function walkerPos(w) {
    if (!w.to) return tileCenter(w.from.x, w.from.y)
    const a = tileCenter(w.from.x, w.from.y)
    const b = tileCenter(w.to.x, w.to.y)
    return {x: a.x + (b.x - a.x) * w.progress, y: a.y + (b.y - a.y) * w.progress}
  }

  function stepWalker(w, dtSec, chooseDir) {
    if (!w.to) {
      const dirName = chooseDir(w)
      if (dirName) {
        const d = DIRS[dirName]
        if (!isWall(w.from.x + d.x, w.from.y + d.y)) {
          w.dir = dirName
          w.to = {x: w.from.x + d.x, y: w.from.y + d.y}
          w.progress = 0
        }
      }
      if (!w.to) return
    }
    w.progress += (w.speed * dtSec) / TILE
    while (w.progress >= 1) {
      w.progress -= 1
      w.from = w.to
      w.to = null
      const dirName = chooseDir(w)
      if (dirName) {
        const d = DIRS[dirName]
        if (!isWall(w.from.x + d.x, w.from.y + d.y)) {
          w.dir = dirName
          w.to = {x: w.from.x + d.x, y: w.from.y + d.y}
          continue
        }
      }
      w.progress = 0
      break
    }
  }

  function reverseWalker(w) {
    if (!w.to) return
    const tmp = w.from
    w.from = w.to
    w.to = tmp
    w.progress = 1 - w.progress
    w.dir = OPPOSITE[w.dir]
  }

  let scene = null
  let player = null
  let playerGfx = null
  let desiredDir = null
  let invulnerableUntil = 0
  const ghosts = []
  let frightenedUntil = 0
  const wordPellets = new Map() // "cx,cy" -> {id, container, item}
  const dots = new Map() // "cx,cy" -> Arc
  let eaten = 0
  let finished = false
  let livesLeft = EXTRA_LIVES
  let livesGfx = null
  let banner = null
  let bannerTimer = null
  const playerStart = findChar("P")
  const ghostHome = findChar("G")

  function findChar(ch) {
    for (let y = 0; y < ROWS; y++) {
      const x = MAZE[y].indexOf(ch)
      if (x >= 0) return {x, y}
    }
    return {x: 7, y: 5}
  }

  function create() {
    scene = this
    drawMaze(scene)
    placePellets(scene)
    spawnPlayer(scene)
    spawnGhosts(scene)
    setupInput(scene)
    livesGfx = scene.add.graphics()
    livesGfx.setDepth(20)
    drawLives()
  }

  // Spare lives shown as mini pac-men on the right side of the header strip
  // (the far corner is covered by the DOM skip button).
  function drawLives() {
    livesGfx.clear()
    for (let i = 0; i < livesLeft; i++) {
      const x = WIDTH - 160 - i * 52
      const y = HEADER / 2
      livesGfx.fillStyle(0xfacc15, 1)
      livesGfx.slice(x, y, 19, 0.3, -0.3, false)
      livesGfx.fillPath()
    }
  }

  function drawMaze(s) {
    const g = s.add.graphics()
    // Header strip
    g.fillStyle(0x1e293b, 1)
    g.fillRect(0, 0, WIDTH, HEADER)
    for (let y = 0; y < ROWS; y++) {
      for (let x = 0; x < COLS; x++) {
        if (MAZE[y][x] !== "#") continue
        const px = x * TILE
        const py = HEADER + y * TILE
        g.fillStyle(0x1d4ed8, 1)
        g.fillRoundedRect(px + 6, py + 6, TILE - 12, TILE - 12, 14)
        g.fillStyle(0x3b82f6, 1)
        g.fillRoundedRect(px + 12, py + 12, TILE - 24, TILE - 24, 10)
      }
    }
  }

  function placePellets(s) {
    const spots = WORD_SPOTS.slice(0, items.length)
    const wordTiles = new Set(spots.map(([x, y]) => `${x},${y}`))

    spots.forEach(([cx, cy], i) => {
      const item = items[i]
      const colors = categoryColor(item.category)
      const {x, y} = tileCenter(cx, cy)
      const text = s.add
        .text(0, 0, item.text, {
          fontFamily: GAME_FONT,
          fontSize: "30px",
          fontStyle: "bold",
          color: colors.text
        })
        .setOrigin(0.5)
      const padX = 18
      const padY = 10
      const w = text.width + padX * 2
      const h = text.height + padY * 2
      const bg = s.add.graphics()
      bg.fillStyle(colors.bg, 1)
      bg.fillRoundedRect(-w / 2, -h / 2, w, h, h / 2)
      bg.lineStyle(5, colors.ring, 1)
      bg.strokeRoundedRect(-w / 2, -h / 2, w, h, h / 2)
      const container = s.add.container(x, y, [bg, text])
      container.setDepth(5)
      s.tweens.add({
        targets: container,
        scale: {from: 1, to: 1.07},
        duration: 700,
        yoyo: true,
        repeat: -1,
        ease: "Sine.easeInOut",
        delay: i * 120
      })
      wordPellets.set(`${cx},${cy}`, {id: item.id, container, item})
    })

    // Plain crumbs on every other open tile, purely decorative.
    for (let y = 0; y < ROWS; y++) {
      for (let x = 0; x < COLS; x++) {
        const ch = MAZE[y][x]
        const key = `${x},${y}`
        if (ch === "#" || ch === "P" || ch === "G" || wordTiles.has(key)) continue
        const {x: px, y: py} = tileCenter(x, y)
        const dot = s.add.circle(px, py, 7, 0xfde68a)
        dot.setDepth(1)
        dots.set(key, dot)
      }
    }
  }

  function spawnPlayer(s) {
    player = makeWalker(playerStart.x, playerStart.y, PLAYER_SPEED)
    playerGfx = s.add.graphics()
    playerGfx.setDepth(10)
  }

  function ghostColors() {
    return [0xef4444, 0xf472b6]
  }

  function spawnGhosts(s) {
    ghostColors().forEach((color, i) => {
      const key = `ghost-${i}`
      makeGhostTexture(s, key, color)
      const home = tileCenter(ghostHome.x, ghostHome.y)
      const sprite = s.add.sprite(home.x, home.y, key)
      sprite.setDepth(9)
      sprite.setData("baseKey", key)
      const walker = makeWalker(ghostHome.x, ghostHome.y, GHOST_SPEED)
      ghosts.push({walker, sprite, releaseAt: s.time.now + 1200 + i * 2200})
    })
    makeGhostTexture(s, "ghost-scared", 0x3730a3, true)
  }

  function makeGhostTexture(s, key, color, scared = false) {
    if (s.textures.exists(key)) return
    const size = 76
    const g = s.make.graphics({add: false})
    g.fillStyle(color, 1)
    // Dome + body
    g.fillCircle(size / 2, size / 2 - 6, size / 2 - 6)
    g.fillRect(6, size / 2 - 6, size - 12, size / 2 - 8)
    // Skirt zigzag
    const feet = 4
    const fw = (size - 12) / feet
    for (let i = 0; i < feet; i++) {
      g.fillTriangle(
        6 + i * fw, size - 14,
        6 + i * fw + fw, size - 14,
        6 + i * fw + fw / 2, size - 2
      )
    }
    // Eyes
    const eyeColor = scared ? 0xfbbf24 : 0xffffff
    g.fillStyle(eyeColor, 1)
    g.fillCircle(size / 2 - 14, size / 2 - 10, 9)
    g.fillCircle(size / 2 + 14, size / 2 - 10, 9)
    if (!scared) {
      g.fillStyle(0x1e3a8a, 1)
      g.fillCircle(size / 2 - 12, size / 2 - 10, 4)
      g.fillCircle(size / 2 + 16, size / 2 - 10, 4)
    } else {
      // Wavy scared mouth
      g.fillStyle(0xfbbf24, 1)
      for (let i = 0; i < 3; i++) {
        g.fillCircle(size / 2 - 12 + i * 12, size / 2 + 12, 4)
      }
    }
    g.generateTexture(key, size, size)
    g.destroy()
  }

  function setupInput(s) {
    s.cursors = s.input.keyboard ? s.input.keyboard.createCursorKeys() : null

    // Swipe/drag steering: while the finger is down, the drag direction from
    // the press point sets the desired direction (joystick-ish, forgiving).
    let press = null
    s.input.on("pointerdown", (p) => {
      press = {x: p.x, y: p.y}
    })
    s.input.on("pointermove", (p) => {
      if (!press || !p.isDown) return
      const dx = p.x - press.x
      const dy = p.y - press.y
      if (Math.abs(dx) < 26 && Math.abs(dy) < 26) return
      desiredDir = Math.abs(dx) > Math.abs(dy) ? (dx > 0 ? "right" : "left") : (dy > 0 ? "down" : "up")
      // Re-anchor so the kid can steer continuously without lifting.
      press = {x: p.x, y: p.y}
    })
    s.input.on("pointerup", () => {
      press = null
    })
  }

  function choosePlayerDir(w) {
    if (desiredDir) {
      const d = DIRS[desiredDir]
      if (!isWall(w.from.x + d.x, w.from.y + d.y)) return desiredDir
    }
    if (w.dir) {
      const d = DIRS[w.dir]
      if (!isWall(w.from.x + d.x, w.from.y + d.y)) return w.dir
    }
    return null
  }

  function chooseGhostDir(ghost) {
    return (w) => {
      const scared = scene.time.now < frightenedUntil
      const playerTile = player.to || player.from
      const options = []
      for (const name of Object.keys(DIRS)) {
        const d = DIRS[name]
        if (isWall(w.from.x + d.x, w.from.y + d.y)) continue
        if (w.dir && name === OPPOSITE[w.dir]) continue
        options.push(name)
      }
      if (options.length === 0) return w.dir ? OPPOSITE[w.dir] : null
      const scoreOf = (name) => {
        const d = DIRS[name]
        const nx = w.from.x + d.x
        const ny = w.from.y + d.y
        return Math.abs(nx - playerTile.x) + Math.abs(ny - playerTile.y)
      }
      if (scared) {
        // Run away
        options.sort((a, b) => scoreOf(b) - scoreOf(a))
        return options[0]
      }
      if (Math.random() < 0.55) {
        options.sort((a, b) => scoreOf(a) - scoreOf(b))
        return options[0]
      }
      return options[Math.floor(Math.random() * options.length)]
    }
  }

  function update(time, delta) {
    if (!player || finished) return
    const dtSec = delta / 1000

    if (scene.cursors) {
      if (scene.cursors.left.isDown) desiredDir = "left"
      else if (scene.cursors.right.isDown) desiredDir = "right"
      else if (scene.cursors.up.isDown) desiredDir = "up"
      else if (scene.cursors.down.isDown) desiredDir = "down"
    }

    // Instant reverse feels snappy and helps escape ghosts.
    if (desiredDir && player.to && desiredDir === OPPOSITE[player.dir]) {
      reverseWalker(player)
    }
    stepWalker(player, dtSec, choosePlayerDir)

    const scared = time < frightenedUntil
    for (const ghost of ghosts) {
      if (time < ghost.releaseAt) continue
      ghost.walker.speed = scared ? GHOST_SCARED_SPEED : GHOST_SPEED
      stepWalker(ghost.walker, dtSec, chooseGhostDir(ghost))
      const pos = walkerPos(ghost.walker)
      ghost.sprite.setPosition(pos.x, pos.y)
      const wantTexture = scared ? "ghost-scared" : ghost.sprite.getData("baseKey")
      if (ghost.sprite.texture.key !== wantTexture) ghost.sprite.setTexture(wantTexture)
    }

    const ppos = walkerPos(player)
    drawPlayer(ppos, time)
    checkEating()
    checkGhostCollisions(ppos, time)
  }

  function drawPlayer(pos, time) {
    const g = playerGfx
    g.clear()
    const r = 36
    const mouth = 0.28 + 0.22 * Math.abs(Math.sin(time / 90))
    const facing = {right: 0, down: Math.PI / 2, left: Math.PI, up: -Math.PI / 2}[player.dir || "right"]
    const alpha = scene.time.now < invulnerableUntil ? 0.55 : 1
    g.fillStyle(0xfacc15, alpha)
    g.slice(pos.x, pos.y, r, facing + mouth, facing - mouth, false)
    g.fillPath()
    // Eye
    g.fillStyle(0x1c1917, alpha)
    const ex = pos.x + Math.cos(facing - Math.PI / 2.6) * r * 0.45
    const ey = pos.y + Math.sin(facing - Math.PI / 2.6) * r * 0.45
    g.fillCircle(ex, ey, 5)
  }

  function checkEating() {
    const tile = player.to && player.progress > 0.5 ? player.to : player.from
    const key = `${tile.x},${tile.y}`

    const dot = dots.get(key)
    if (dot) {
      dots.delete(key)
      sfx.chomp()
      scene.tweens.add({targets: dot, scale: 0, duration: 120, onComplete: () => dot.destroy()})
    }

    const pellet = wordPellets.get(key)
    if (pellet) {
      wordPellets.delete(key)
      eaten += 1
      sfx.powerUp()
      frightenedUntil = scene.time.now + FRIGHT_MS
      showBanner(pellet.item.text, categoryColor(pellet.item.category))
      scene.tweens.add({
        targets: pellet.container,
        scale: 1.5,
        alpha: 0,
        y: pellet.container.y - 50,
        duration: 420,
        ease: "Cubic.easeOut",
        onComplete: () => pellet.container.destroy()
      })
      hook.pushEvent("pacman_eat", {id: pellet.id})
    }

    // Clearing the maze means every word AND every plain dot.
    if (wordPellets.size === 0 && dots.size === 0) {
      finish()
    }
  }

  function checkGhostCollisions(ppos, time) {
    if (time < invulnerableUntil) return
    for (const ghost of ghosts) {
      if (time < ghost.releaseAt) continue
      const gpos = walkerPos(ghost.walker)
      const dist = Math.hypot(gpos.x - ppos.x, gpos.y - ppos.y)
      if (dist > TILE * 0.55) continue
      if (time < frightenedUntil) {
        // Kid eats the ghost: pop it and send it home.
        sfx.ghostEaten()
        scene.tweens.add({
          targets: ghost.sprite,
          scale: 1.6,
          alpha: 0,
          duration: 250,
          onComplete: () => {
            ghost.walker = makeWalker(ghostHome.x, ghostHome.y, GHOST_SPEED)
            ghost.sprite.setScale(1).setAlpha(1)
            const home = tileCenter(ghostHome.x, ghostHome.y)
            ghost.sprite.setPosition(home.x, home.y)
          }
        })
        ghost.releaseAt = time + 2500
      } else {
        // Caught: costs a life. Back to start with brief mercy
        // invulnerability, or Game Over when the spare lives are gone.
        sfx.death()
        scene.cameras.main.shake(180, 0.008)

        if (livesLeft > 0) {
          livesLeft -= 1
          drawLives()
          player = makeWalker(playerStart.x, playerStart.y, PLAYER_SPEED)
          desiredDir = null
          invulnerableUntil = time + 1800
        } else {
          gameOver()
        }
      }
      return
    }
  }

  function gameOver() {
    finished = true
    sfx.gameOver()
    const text = scene.add
      .text(WIDTH / 2, HEIGHT / 2, "Game Over", {
        fontFamily: GAME_FONT,
        fontSize: "120px",
        fontStyle: "bold",
        color: "#ef4444",
        stroke: "#450a0a",
        strokeThickness: 12
      })
      .setOrigin(0.5)
      .setDepth(30)
    scene.tweens.add({targets: text, scale: {from: 0.3, to: 1}, duration: 400, ease: "Back.easeOut"})
    scene.time.delayedCall(2400, () => hook.pushEvent("pacman_game_over", {}))
  }

  function showBanner(text, colors) {
    if (banner) banner.destroy()
    if (bannerTimer) bannerTimer.remove()
    banner = scene.add
      .text(WIDTH / 2, HEADER / 2, text, {
        fontFamily: GAME_FONT,
        fontSize: "52px",
        fontStyle: "bold",
        color: "#ffffff"
      })
      .setOrigin(0.5)
      .setDepth(20)
    scene.tweens.add({targets: banner, scale: {from: 0.6, to: 1}, duration: 220, ease: "Back.easeOut"})
    bannerTimer = scene.time.delayedCall(1600, () => {
      if (banner) banner.destroy()
      banner = null
    })
  }

  function finish() {
    finished = true
    sfx.win()
    scene.time.delayedCall(2000, () => hook.pushEvent("pacman_cleared", {}))
    const text = scene.add
      .text(WIDTH / 2, HEIGHT / 2, "Vel gert!", {
        fontFamily: GAME_FONT,
        fontSize: "120px",
        fontStyle: "bold",
        color: "#fde047",
        stroke: "#78350f",
        strokeThickness: 12
      })
      .setOrigin(0.5)
      .setDepth(30)
    scene.tweens.add({targets: text, scale: {from: 0.3, to: 1}, duration: 400, ease: "Back.easeOut"})
    for (const ghost of ghosts) {
      scene.tweens.add({targets: ghost.sprite, alpha: 0, duration: 400})
    }
  }

  return new Phaser.Game({
    type: Phaser.AUTO,
    parent,
    backgroundColor: "#0f172a",
    scale: {
      mode: Phaser.Scale.FIT,
      autoCenter: Phaser.Scale.CENTER_BOTH,
      width: WIDTH,
      height: HEIGHT
    },
    scene: {create, update}
  })
}
