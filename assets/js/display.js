// Reader-controlled display settings: the Floe layer of .agents/skills/jarvis-design.
// A classic script, not a module: root.html.heex inlines it into <head> so the
// settings apply before the first paint. It exposes window.jarvisDisplay.
;(function (global) {
  const KEY = "jarvis:display"

  const OPTIONS = {
    textSize: ["100", "125", "150", "200"],
    leading: ["normal", "increased"],
    theme: ["light", "dark", "contrast"],
    motion: ["on", "reduced"],
    density: ["airy", "compact"],
  }

  const DEFAULTS = {textSize: "100", leading: "normal", theme: "light", motion: "on", density: "airy"}

  // First visit: start from what the browser asks for.
  function fromBrowser(media) {
    const matches = (query) => {
      try {
        return media(query)
      } catch {
        return false
      }
    }
    return {
      ...DEFAULTS,
      theme: matches("(prefers-contrast: more)") ? "contrast" : matches("(prefers-color-scheme: dark)") ? "dark" : "light",
      motion: matches("(prefers-reduced-motion: reduce)") ? "reduced" : "on",
    }
  }

  // Unknown or broken values fall back to the defaults, silently.
  function parse(raw) {
    let value
    try {
      value = JSON.parse(raw)
    } catch {
      return {...DEFAULTS}
    }
    if (!value || typeof value !== "object") return {...DEFAULTS}
    const settings = {}
    for (const key in OPTIONS) settings[key] = OPTIONS[key].includes(value[key]) ? value[key] : DEFAULTS[key]
    return settings
  }

  function load(storage, media) {
    let raw
    try {
      raw = storage.getItem(KEY)
    } catch {
      return {...DEFAULTS}
    }
    return raw == null ? fromBrowser(media) : parse(raw)
  }

  function apply(root, settings) {
    root.setAttribute("data-theme", settings.theme)
    root.setAttribute("data-text-size", settings.textSize)
    root.setAttribute("data-leading", settings.leading)
    root.setAttribute("data-motion", settings.motion)
    root.setAttribute("data-density", settings.density)
  }

  function save(storage, settings) {
    try {
      storage.setItem(KEY, JSON.stringify(settings))
    } catch {
      // Storage may be full or blocked; the settings still apply to this page.
    }
  }

  const api = {KEY, OPTIONS, DEFAULTS, parse, load, fromBrowser}

  if (global.document) {
    const root = global.document.documentElement
    const media = (query) => global.matchMedia(query).matches
    let current = load(global.localStorage, media)
    apply(root, current)

    api.current = () => ({...current})
    api.set = (settings) => {
      current = parse(JSON.stringify(settings))
      save(global.localStorage, current)
      apply(root, current)
      return api.current()
    }
    api.reset = () => api.set(DEFAULTS)

    // Another tab changed them: follow.
    global.addEventListener("storage", (e) => {
      if (e.key !== KEY) return
      current = load(global.localStorage, media)
      apply(root, current)
    })
  }

  global.jarvisDisplay = api
})(typeof window !== "undefined" ? window : globalThis)
