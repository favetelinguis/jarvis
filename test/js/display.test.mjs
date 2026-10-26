// Run by test/jarvis_web/display_settings_test.exs: node --test test/js/display.test.mjs
import {test} from "node:test"
import assert from "node:assert/strict"
import {readFileSync} from "node:fs"
import vm from "node:vm"

const source = readFileSync(new URL("../../assets/js/display.js", import.meta.url), "utf8")

function browser({stored, prefers = []} = {}) {
  const attrs = {}
  const store = new Map(stored === undefined ? [] : [["jarvis:display", stored]])
  const listeners = {}
  const window = {
    document: {documentElement: {setAttribute: (k, v) => (attrs[k] = v)}},
    localStorage: {getItem: (k) => (store.has(k) ? store.get(k) : null), setItem: (k, v) => store.set(k, v)},
    matchMedia: (q) => ({matches: prefers.includes(q)}),
    addEventListener: (type, fn) => (listeners[type] = fn),
  }
  vm.runInNewContext(source, {window, globalThis: window})
  return {api: window.jarvisDisplay, attrs, store, listeners}
}

test("defaults apply on a first visit without browser preferences", () => {
  const {attrs} = browser()
  assert.deepEqual(attrs, {
    "data-theme": "light",
    "data-text-size": "100",
    "data-leading": "normal",
    "data-motion": "on",
    "data-density": "airy",
  })
})

test("a first visit starts from reduced motion and higher contrast when the browser asks", () => {
  const {attrs} = browser({prefers: ["(prefers-reduced-motion: reduce)", "(prefers-contrast: more)"]})
  assert.equal(attrs["data-motion"], "reduced")
  assert.equal(attrs["data-theme"], "contrast")
})

test("saved settings apply when the board opens again, over browser preferences", () => {
  const stored = JSON.stringify({textSize: "200", leading: "increased", theme: "dark", motion: "on", density: "compact"})
  const {attrs} = browser({stored, prefers: ["(prefers-reduced-motion: reduce)"]})
  assert.equal(attrs["data-text-size"], "200")
  assert.equal(attrs["data-leading"], "increased")
  assert.equal(attrs["data-theme"], "dark")
  assert.equal(attrs["data-motion"], "on")
  assert.equal(attrs["data-density"], "compact")
})

test("unreadable saved settings fall back to the defaults without an error", () => {
  for (const stored of ["{not json", "null", "42", JSON.stringify({textSize: "175", theme: "pink"})]) {
    const {attrs} = browser({stored, prefers: ["(prefers-contrast: more)"]})
    assert.equal(attrs["data-text-size"], "100", stored)
    assert.equal(attrs["data-theme"], "light", stored)
  }
})

test("a change applies at once and is saved; reset goes back to the defaults", () => {
  const {api, attrs, store} = browser()
  api.set({...api.current(), textSize: "150", density: "compact"})
  assert.equal(attrs["data-text-size"], "150")
  assert.equal(JSON.parse(store.get("jarvis:display")).density, "compact")

  api.reset()
  assert.equal(attrs["data-text-size"], "100")
  assert.equal(attrs["data-density"], "airy")
  assert.deepEqual(JSON.parse(store.get("jarvis:display")), {...api.DEFAULTS})
})

test("only the offered values can be chosen", () => {
  const {api} = browser()
  assert.deepEqual([...api.OPTIONS.textSize], ["100", "125", "150", "200"])
  assert.equal(api.set({...api.current(), textSize: "175"}).textSize, "100")
})
