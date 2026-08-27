// Space Invaders twist minigame ("Geimorð"). The invaders are cute little
// word-capsule monsters carrying the words (or math problems) the kid just
// practiced. Drag anywhere to steer the rocket — it auto-fires. The fleet
// marches down toward you, the three longest words drop bombs, and every so
// often one alien breaks formation for a spiraling swoop. Touching an alien
// or a bomb costs a life (3 spares plus the one you start with); Game Over
// when the lives run out or any word reaches the bottom.
//
// Server contract (mirrors the centipede game):
//   - reads items from data-items JSON: [{id, text, category}]
//   - pushes "invaders_hit" {id} each time an invader is shot
//   - the server counts and closes the overlay once all are down
//   - pushes "invaders_game_over" {} after the Game Over screen has shown
//   - skip button is server-side (skip_invaders_game), outside the canvas
import {loadPhaser, parseItems, categoryColor, GAME_FONT} from "./shared"
import * as sfx from "./sfx"

const WIDTH = 1440
const HEIGHT = 960
const SHIP_Y = 880
const FIRE_INTERVAL_MS = 420
const BULLET_SPEED = 950 // px/s
const MARCH_SPEED = 140 // px/s base; scales up as invaders are popped
const BOMB_SPEED = 240 // px/s, fairly slow so it's dodgeable
const BOMB_INTERVAL_MS = 3000 // per bomber
const BOMBER_COUNT = 3 // the longest words bomb — never more, even on ties
const SWOOP_INTERVAL_MS = 7000
const SWOOP_DURATION_MS = 3200
const EXTRA_LIVES = 3 // spare lives on top of the one in play

export const InvadersGame = {
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

  let scene = null
  let ship = null
  let shipTargetX = WIDTH / 2
  let flame = null
  const invaders = [] // {id, container, baseX, baseY, alive, halfW, halfH, ...}
  const bullets = []
  const bombs = [] // {sprite}
  let fleetX = 0
  let fleetY = 0
  let fleetDir = 1
  let lastFireAt = 0
  let finished = false
  let livesLeft = EXTRA_LIVES
  let livesGfx = null
  let shipInvulnUntil = 0
  let swoop = null // {inv, t, startX, startY}
  let nextSwoopAt = 0

  function create() {
    scene = this
    drawStars(scene)
    spawnInvaders(scene)
    pickBombers(scene)
    spawnShip(scene)
    setupInput(scene)
    makeTextures(scene)
    livesGfx = scene.add.graphics()
    livesGfx.setDepth(20)
    drawLives()
    nextSwoopAt = scene.time.now + SWOOP_INTERVAL_MS
  }

  function makeTextures(s) {
    if (!s.textures.exists("bullet")) {
      const g = s.make.graphics({add: false})
      g.fillStyle(0xfde047, 1)
      g.fillRoundedRect(0, 0, 10, 26, 5)
      g.generateTexture("bullet", 10, 26)
      g.destroy()
    }
    if (!s.textures.exists("bomb")) {
      const g = s.make.graphics({add: false})
      g.fillStyle(0xef4444, 1)
      g.fillCircle(11, 11, 10)
      g.fillStyle(0xfca5a5, 1)
      g.fillCircle(8, 8, 3.5)
      g.generateTexture("bomb", 22, 22)
      g.destroy()
    }
  }

  function drawStars(s) {
    for (let i = 0; i < 70; i++) {
      const star = s.add.circle(
        Math.random() * WIDTH,
        Math.random() * HEIGHT,
        Math.random() * 2.5 + 1,
        0xe2e8f0,
        Math.random() * 0.6 + 0.2
      )
      s.tweens.add({
        targets: star,
        alpha: 0.1,
        duration: 900 + Math.random() * 1600,
        yoyo: true,
        repeat: -1,
        delay: Math.random() * 2000
      })
    }
  }

  function spawnInvaders(s) {
    const perRow = 6
    const dy = 112
    const y0 = 120

    items.forEach((item, i) => {
      const row = Math.floor(i / perRow)
      const col = i % perRow
      const inThisRow = Math.min(perRow, items.length - row * perRow)
      const spacing = WIDTH / (inThisRow + 1)
      const baseX = spacing * (col + 1)
      const baseY = y0 + row * dy
      const colors = categoryColor(item.category)

      const text = s.add
        .text(0, 6, item.text, {
          fontFamily: GAME_FONT,
          fontSize: "30px",
          fontStyle: "bold",
          color: colors.text
        })
        .setOrigin(0.5)
      const padX = 16
      const w = Math.max(text.width + padX * 2, 76)
      const h = text.height + 22
      const body = s.add.graphics()
      body.fillStyle(colors.bg, 1)
      body.fillRoundedRect(-w / 2, -h / 2, w, h, h / 2)
      body.lineStyle(5, colors.ring, 1)
      body.strokeRoundedRect(-w / 2, -h / 2, w, h, h / 2)
      // Antennae + eyes make the capsule a little monster
      body.lineStyle(5, colors.ring, 1)
      body.lineBetween(-14, -h / 2, -20, -h / 2 - 14)
      body.lineBetween(14, -h / 2, 20, -h / 2 - 14)
      body.fillStyle(colors.ring, 1)
      body.fillCircle(-20, -h / 2 - 17, 6)
      body.fillCircle(20, -h / 2 - 17, 6)
      const eyeY = -h / 2 + 2
      body.fillStyle(0xffffff, 1)
      body.fillCircle(-11, eyeY, 8)
      body.fillCircle(11, eyeY, 8)
      body.fillStyle(0x1e293b, 1)
      body.fillCircle(-11, eyeY + 2, 4)
      body.fillCircle(11, eyeY + 2, 4)

      const container = s.add.container(baseX, baseY, [body, text])
      container.setDepth(5)
      invaders.push({
        id: item.id,
        text: item.text,
        container,
        baseX,
        baseY,
        alive: true,
        halfW: w / 2,
        halfH: h / 2,
        bobPhase: Math.random() * Math.PI * 2,
        bomber: false,
        nextBombAt: 0
      })
    })
  }

  // The three longest words become bombers (never more than three, ties
  // broken by position). Their drops are staggered so they don't volley.
  function pickBombers(s) {
    invaders
      .map((inv, i) => ({inv, i, len: inv.text.length}))
      .sort((a, b) => b.len - a.len || a.i - b.i)
      .slice(0, BOMBER_COUNT)
      .forEach(({inv}, k) => {
        inv.bomber = true
        inv.nextBombAt = s.time.now + 2500 + k * 1000
      })
  }

  function spawnShip(s) {
    const g = s.add.graphics()
    g.fillStyle(0xe2e8f0, 1)
    g.fillTriangle(0, -46, -30, 26, 30, 26)
    g.fillStyle(0x38bdf8, 1)
    g.fillTriangle(0, -30, -18, 20, 18, 20)
    g.fillStyle(0xe2e8f0, 1)
    g.fillCircle(0, -2, 10)
    // Fins
    g.fillStyle(0xf87171, 1)
    g.fillTriangle(-30, 26, -44, 40, -22, 40)
    g.fillTriangle(30, 26, 44, 40, 22, 40)
    flame = s.add.graphics()
    ship = s.add.container(WIDTH / 2, SHIP_Y, [flame, g])
    ship.setDepth(10)
  }

  // Spare lives shown as mini rockets at the top center (the corners are
  // covered by the DOM counter pill and skip button).
  function drawLives() {
    livesGfx.clear()
    const startX = WIDTH / 2 - ((livesLeft - 1) * 52) / 2
    for (let i = 0; i < livesLeft; i++) {
      const x = startX + i * 52
      const y = 46
      livesGfx.fillStyle(0xe2e8f0, 1)
      livesGfx.fillTriangle(x, y - 16, x - 11, y + 12, x + 11, y + 12)
      livesGfx.fillStyle(0xf87171, 1)
      livesGfx.fillTriangle(x - 11, y + 12, x - 16, y + 18, x - 8, y + 18)
      livesGfx.fillTriangle(x + 11, y + 12, x + 16, y + 18, x + 8, y + 18)
    }
  }

  function setupInput(s) {
    const steer = (p) => {
      shipTargetX = p.x
    }
    s.input.on("pointerdown", steer)
    s.input.on("pointermove", (p) => {
      if (p.isDown) steer(p)
    })
    s.cursors = s.input.keyboard ? s.input.keyboard.createCursorKeys() : null
  }

  function fire(time) {
    lastFireAt = time
    sfx.shoot()
    const bullet = scene.add.image(ship.x, SHIP_Y - 56, "bullet")
    bullet.setDepth(8)
    bullets.push(bullet)
  }

  function update(time, delta) {
    const dtSec = delta / 1000

    // Flame flicker
    flame.clear()
    const flick = 20 + Math.random() * 16
    flame.fillStyle(0xfb923c, 0.9)
    flame.fillTriangle(-10, 40, 10, 40, 0, 40 + flick)
    flame.fillStyle(0xfde047, 0.9)
    flame.fillTriangle(-5, 40, 5, 40, 0, 40 + flick * 0.6)

    if (scene.cursors && (scene.cursors.left.isDown || scene.cursors.right.isDown)) {
      const dir = scene.cursors.left.isDown ? -1 : 1
      ship.x = Math.max(60, Math.min(WIDTH - 60, ship.x + dir * 700 * dtSec))
      shipTargetX = ship.x
    } else {
      shipTargetX = Math.max(60, Math.min(WIDTH - 60, shipTargetX))
      ship.x += (shipTargetX - ship.x) * Math.min(1, dtSec * 12)
    }

    if (finished) return

    ship.alpha = time < shipInvulnUntil ? 0.45 : 1

    const alive = invaders.filter((inv) => inv.alive)
    const formation = alive.filter((inv) => !swoop || swoop.inv !== inv)

    // Fleet march: speeds up as invaders are popped, descends at the edges.
    const speed = MARCH_SPEED * (1 + 1.4 * (1 - alive.length / Math.max(1, invaders.length)))
    fleetX += fleetDir * speed * dtSec
    let minX = Infinity
    let maxX = -Infinity
    for (const inv of formation) {
      minX = Math.min(minX, inv.baseX + fleetX - inv.halfW)
      maxX = Math.max(maxX, inv.baseX + fleetX + inv.halfW)
    }
    if (formation.length > 0 && (maxX > WIDTH - 24 || minX < 24)) {
      fleetDir *= -1
      fleetX += fleetDir * speed * dtSec * 2
      fleetY += 30
    }

    for (const inv of formation) {
      const bob = Math.sin(time / 400 + inv.bobPhase) * 6
      inv.container.setPosition(inv.baseX + fleetX, inv.baseY + fleetY + bob)
    }

    // Any word reaching the bottom (the ship's line) ends the game.
    for (const inv of formation) {
      if (inv.baseY + fleetY + inv.halfH >= SHIP_Y - 30) {
        gameOver()
        return
      }
    }

    updateSwoop(time, dtSec, alive)
    updateBombs(time, dtSec, alive)

    // Auto-fire while anything is left.
    if (alive.length > 0 && time - lastFireAt > FIRE_INTERVAL_MS) {
      fire(time)
    }

    // Bullets + collisions
    for (let i = bullets.length - 1; i >= 0; i--) {
      const bullet = bullets[i]
      bullet.y -= BULLET_SPEED * dtSec
      if (bullet.y < -40) {
        bullet.destroy()
        bullets.splice(i, 1)
        continue
      }
      // Falling bombs can be shot down
      const bombIdx = bombs.findIndex(
        (b) => Math.abs(bullet.x - b.sprite.x) < 22 && Math.abs(bullet.y - b.sprite.y) < 26
      )
      if (bombIdx >= 0) {
        sfx.bombShot()
        burstAt(bombs[bombIdx].sprite.x, bombs[bombIdx].sprite.y, {ring: 0xef4444}, 7)
        bombs[bombIdx].sprite.destroy()
        bombs.splice(bombIdx, 1)
        bullet.destroy()
        bullets.splice(i, 1)
        continue
      }
      const hit = alive.find(
        (inv) =>
          inv.alive &&
          Math.abs(bullet.x - inv.container.x) < inv.halfW + 8 &&
          Math.abs(bullet.y - inv.container.y) < inv.halfH + 14
      )
      if (hit) {
        bullet.destroy()
        bullets.splice(i, 1)
        popInvader(hit)
        if (finished) return
      }
    }

    checkShipCollisions(time, alive)
  }

  // Once every SWOOP_INTERVAL_MS one alien breaks formation and corkscrews
  // down toward the ship's line, then climbs back up to its slot.
  function updateSwoop(time, dtSec, alive) {
    if (!swoop) {
      if (time >= nextSwoopAt && alive.length > 0) {
        const inv = alive[Math.floor(Math.random() * alive.length)]
        sfx.swoop()
        swoop = {
          inv,
          t: 0,
          startX: inv.container.x,
          startY: inv.container.y,
          // One bomb at a random moment during the descent
          bombAt: 0.08 + Math.random() * 0.4,
          bombed: false
        }
        nextSwoopAt = time + SWOOP_INTERVAL_MS
      }
      return
    }

    const inv = swoop.inv
    if (!inv.alive) {
      // Shot mid-swoop
      swoop = null
      return
    }

    swoop.t += (dtSec * 1000) / SWOOP_DURATION_MS
    const t = swoop.t
    if (t >= 1) {
      swoop = null
      return
    }

    if (!swoop.bombed && t >= swoop.bombAt) {
      swoop.bombed = true
      dropBombFrom(inv)
    }

    const bottomY = SHIP_Y - 70
    if (t < 0.62) {
      // Corkscrew descent
      const p = t / 0.62
      const ease = p * p * (3 - 2 * p)
      const y = swoop.startY + (bottomY - swoop.startY) * ease
      const x = swoop.startX + Math.sin(p * Math.PI * 3) * 260
      inv.container.setPosition(Math.max(60, Math.min(WIDTH - 60, x)), y)
    } else {
      // Climb back to the (moving) formation slot
      const p = (t - 0.62) / 0.38
      const ease = p * p * (3 - 2 * p)
      const slotX = inv.baseX + fleetX
      const slotY = inv.baseY + fleetY
      const fromX = Math.max(60, Math.min(WIDTH - 60, swoop.startX))
      inv.container.setPosition(
        fromX + (slotX - fromX) * ease + Math.sin((1 - p) * Math.PI * 2) * 60 * (1 - p),
        bottomY + (slotY - bottomY) * ease
      )
    }
  }

  function dropBombFrom(inv) {
    sfx.bombDrop()
    const bomb = scene.add.image(inv.container.x, inv.container.y + inv.halfH + 12, "bomb")
    bomb.setDepth(7)
    bombs.push({sprite: bomb})
  }

  function updateBombs(time, dtSec, alive) {
    for (const inv of alive) {
      if (!inv.bomber || time < inv.nextBombAt) continue
      inv.nextBombAt = time + BOMB_INTERVAL_MS
      dropBombFrom(inv)
    }

    for (let i = bombs.length - 1; i >= 0; i--) {
      const bomb = bombs[i].sprite
      bomb.y += BOMB_SPEED * dtSec
      bomb.rotation += dtSec * 4
      if (bomb.y > HEIGHT + 30) {
        bomb.destroy()
        bombs.splice(i, 1)
      }
    }
  }

  function checkShipCollisions(time, alive) {
    if (time < shipInvulnUntil) return

    for (let i = bombs.length - 1; i >= 0; i--) {
      const bomb = bombs[i].sprite
      if (Math.abs(bomb.x - ship.x) < 36 && Math.abs(bomb.y - SHIP_Y) < 44) {
        bomb.destroy()
        bombs.splice(i, 1)
        loseLife(time)
        return
      }
    }

    for (const inv of alive) {
      if (
        Math.abs(inv.container.x - ship.x) < inv.halfW + 26 &&
        Math.abs(inv.container.y - SHIP_Y) < inv.halfH + 36
      ) {
        loseLife(time)
        return
      }
    }
  }

  function loseLife(time) {
    sfx.shipHit()
    burstAt(ship.x, SHIP_Y, {ring: 0xf87171})
    scene.cameras.main.shake(200, 0.01)

    if (livesLeft > 0) {
      livesLeft -= 1
      drawLives()
      shipInvulnUntil = time + 2000
    } else {
      gameOver()
    }
  }

  function burstAt(x, y, colors, count = 14) {
    for (let i = 0; i < count; i++) {
      const bit = scene.add.circle(x, y, 5 + Math.random() * 5, i % 2 === 0 ? colors.ring : 0xfde047)
      bit.setDepth(6)
      const angle = Math.random() * Math.PI * 2
      const dist = 60 + Math.random() * 130
      scene.tweens.add({
        targets: bit,
        x: x + Math.cos(angle) * dist,
        y: y + Math.sin(angle) * dist,
        alpha: 0,
        scale: 0.3,
        duration: 450 + Math.random() * 250,
        ease: "Cubic.easeOut",
        onComplete: () => bit.destroy()
      })
    }
  }

  function popInvader(inv) {
    inv.alive = false
    sfx.pop()
    const {x, y} = inv.container
    burstAt(x, y, categoryColor(items.find((it) => it.id === inv.id)?.category))

    scene.tweens.add({
      targets: inv.container,
      scale: 1.5,
      alpha: 0,
      duration: 300,
      ease: "Cubic.easeOut",
      onComplete: () => inv.container.destroy()
    })

    hook.pushEvent("invaders_hit", {id: inv.id})

    if (invaders.every((other) => !other.alive)) {
      finish()
    }
  }

  function clearProjectiles() {
    for (const bullet of bullets) bullet.destroy()
    bullets.length = 0
    for (const bomb of bombs) bomb.sprite.destroy()
    bombs.length = 0
  }

  function finish() {
    finished = true
    sfx.win()
    clearProjectiles()
    const text = scene.add
      .text(WIDTH / 2, HEIGHT / 2 - 60, "Vel gert!", {
        fontFamily: GAME_FONT,
        fontSize: "120px",
        fontStyle: "bold",
        color: "#fde047",
        stroke: "#1e3a8a",
        strokeThickness: 12
      })
      .setOrigin(0.5)
      .setDepth(30)
    scene.tweens.add({targets: text, scale: {from: 0.3, to: 1}, duration: 400, ease: "Back.easeOut"})
    scene.tweens.add({targets: ship, y: -120, duration: 1400, ease: "Cubic.easeIn", delay: 300})
  }

  function gameOver() {
    finished = true
    sfx.gameOver()
    clearProjectiles()
    ship.alpha = 1
    const text = scene.add
      .text(WIDTH / 2, HEIGHT / 2 - 60, "Game Over", {
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
    scene.time.delayedCall(2400, () => hook.pushEvent("invaders_game_over", {}))
  }

  return new Phaser.Game({
    type: Phaser.AUTO,
    parent,
    backgroundColor: "#020617",
    scale: {
      mode: Phaser.Scale.FIT,
      autoCenter: Phaser.Scale.CENTER_BOTH,
      width: WIDTH,
      height: HEIGHT
    },
    scene: {create, update}
  })
}
