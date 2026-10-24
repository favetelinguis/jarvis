// Browser-side behavior of widgets. Everything the human can click is sent to
// LiveView; these hooks only draw (Mermaid) and move (pan and zoom).

let mermaidReady

function loadMermaid() {
  mermaidReady ||= new Promise((resolve, reject) => {
    const script = document.createElement("script")
    script.src = "/vendor/mermaid.min.js"
    script.onload = () => resolve(window.mermaid)
    script.onerror = () => reject(new Error("could not load Mermaid"))
    document.head.appendChild(script)
  })
  return mermaidReady
}

const css = (name, fallback) =>
  getComputedStyle(document.documentElement).getPropertyValue(name).trim() || fallback

function mermaidTheme() {
  const dark = document.documentElement.getAttribute("data-theme") === "dark"
  return {
    startOnLoad: false,
    securityLevel: "strict",
    theme: "base",
    themeVariables: {
      darkMode: dark,
      background: "transparent",
      primaryColor: css("--color-primary", "#4f5bd5"),
      primaryTextColor: css("--color-primary-content", "#ffffff"),
      primaryBorderColor: css("--color-primary", "#4f5bd5"),
      secondaryColor: css("--color-secondary", "#5b6b82"),
      secondaryTextColor: css("--color-secondary-content", "#ffffff"),
      tertiaryColor: dark ? "#2a3340" : "#f1f2f6",
      lineColor: css("--color-secondary", "#5b6b82"),
      textColor: dark ? "#e8ecf3" : "#222",
      edgeLabelBackground: dark ? "#2a3340" : "#f4f5f8",
      noteBkgColor: css("--color-accent", "#d9822b"),
      noteTextColor: css("--color-accent-content", "#000"),
    },
  }
}

// Which part of the diagram an element is: "node:A", "edge:A->B", "participant:Bob", "message:hello".
function partOf(target) {
  const node = target.closest(".node, .nodeLabel, .cluster, g[id^='state-'], g[id^='classId-'], g[id^='entity-']")
  if (node) {
    const id = node.id || node.closest("[id]")?.id || ""
    const m = id.match(/^(?:flowchart|state|classId|entity)-(.+?)-\d+$/)
    if (m) return `node:${m[1]}`
    const label = node.textContent.trim()
    if (label) return `node:${label}`
  }
  const edge = target.closest("path.flowchart-link, .edgePath, .edgeLabel, path[id^='L_'], g.edgeLabel")
  if (edge) {
    const id = edge.id || edge.getAttribute("data-id") || ""
    const m = id.match(/^L[_-](.+)[_-](.+?)[_-]\d+$/)
    if (m) return `edge:${m[1]}->${m[2]}`
    const label = edge.textContent.trim()
    return label ? `edge:${label}` : "edge:unlabelled"
  }
  const actor = target.closest("rect.actor, text.actor, .actor-man")
  if (actor) {
    const name = actor.getAttribute("name") || actor.closest("[name]")?.getAttribute("name") || actor.textContent
    return `participant:${name.trim()}`
  }
  const message = target.closest(".messageText, .messageLine0, .messageLine1")
  if (message) return `message:${(message.textContent || "message").trim().slice(0, 40)}`
  return null
}

export const Mermaid = {
  mounted() {
    this.draw()
    this.el.addEventListener("click", (e) => {
      const part = partOf(e.target)
      if (part) this.pushEvent("widget:compose", {widget: this.el.dataset.widget, part})
    })
  },
  async draw() {
    const {widget, source, hadError} = this.el.dataset
    try {
      const mermaid = await loadMermaid()
      mermaid.initialize(mermaidTheme())
      const {svg} = await mermaid.render(`mmd-${widget}-${Date.now()}`, source)
      this.el.innerHTML = svg
      if (hadError === "true") this.pushEvent("widget:rendered", {widget})
    } catch (error) {
      document.querySelectorAll("[id^='dmmd-'], [id^='mmd-']").forEach((n) => n.id.startsWith("dmmd") && n.remove())
      this.el.innerHTML = ""
      this.pushEvent("widget:render_error", {widget, message: String(error.message || error).split("\n")[0]})
    }
  },
}

// Pan with the mouse, zoom with the wheel or the buttons, fit to see everything.
export const PanZoom = {
  mounted() {
    this.state = {x: 0, y: 0, k: 1}
    this.fitted = false
    this.stage = () => this.el.querySelector("[data-pz-stage]")
    this.viewport = () => this.el.querySelector("[data-pz-viewport]")

    const vp = this.viewport()
    vp.addEventListener("wheel", (e) => {
      e.preventDefault()
      this.zoomAt(e.deltaY < 0 ? 1.12 : 1 / 1.12, e.offsetX, e.offsetY)
    }, {passive: false})
    vp.addEventListener("pointerdown", (e) => {
      if (e.target.closest("[data-pz-no-pan]")) return
      this.drag = {x: e.clientX - this.state.x, y: e.clientY - this.state.y}
      vp.setPointerCapture(e.pointerId)
    })
    vp.addEventListener("pointermove", (e) => {
      if (!this.drag) return
      this.state.x = e.clientX - this.drag.x
      this.state.y = e.clientY - this.drag.y
      this.apply()
    })
    const stop = () => (this.drag = null)
    vp.addEventListener("pointerup", stop)
    vp.addEventListener("pointercancel", stop)
    this.el.addEventListener("click", (e) => {
      const button = e.target.closest("[data-pz]")
      if (!button) return
      const {width, height} = vp.getBoundingClientRect()
      if (button.dataset.pz === "fit") this.fit()
      else this.zoomAt(button.dataset.pz === "in" ? 1.25 : 0.8, width / 2, height / 2)
    })
    this.fit()
  },
  updated() {
    this.apply()
  },
  fit() {
    const vp = this.viewport()
    const stage = this.stage()
    const w = parseFloat(stage.dataset.w), h = parseFloat(stage.dataset.h)
    const box = vp.getBoundingClientRect()
    const k = Math.min(1, (box.width - 24) / w, (box.height - 24) / h)
    this.state = {k, x: (box.width - w * k) / 2, y: (box.height - h * k) / 2}
    this.apply()
  },
  zoomAt(factor, px, py) {
    const k = Math.min(2.5, Math.max(0.25, this.state.k * factor))
    const ratio = k / this.state.k
    this.state = {k, x: px - (px - this.state.x) * ratio, y: py - (py - this.state.y) * ratio}
    this.apply()
  },
  apply() {
    const {x, y, k} = this.state
    this.stage().style.transform = `translate(${x}px, ${y}px) scale(${k})`
  },
}

export default {Mermaid, PanZoom}
