"use strict"

// DEFAULTS in TimechainModel.js is the source of truth; the manifest's
// `defaults` block and schema `defaultValue`s must mirror it (DESIGN.md §8.1).

const test = require("node:test")
const assert = require("node:assert/strict")
const path = require("node:path")
const fs = require("node:fs")
const M = require("../TimechainModel.js")

const manifest = JSON.parse(fs.readFileSync(path.join(__dirname, "..", "manifest.json"), "utf8"))
const widget = manifest.barWidget

test("manifest id matches the model", () => {
  assert.equal(manifest.id, M.PLUGIN_ID)
})

test("manifest defaults equal DEFAULTS", () => {
  assert.deepEqual(widget.defaults, M.DEFAULTS)
})

test("schema covers every DEFAULTS key with the same default", () => {
  const schema = {}
  for (const field of widget.schema) schema[field.key] = field
  assert.deepEqual(Object.keys(schema).sort(), Object.keys(M.DEFAULTS).sort())
  for (const key of Object.keys(M.DEFAULTS)) {
    assert.deepEqual(schema[key].defaultValue, M.DEFAULTS[key], key)
  }
})

test("schema ranges and options match the model's validation", () => {
  for (const field of widget.schema) {
    const range = M.INT_RANGES[field.key]
    if (range) assert.deepEqual([field.min, field.max], range, field.key)
    if (field.type === "enum") assert.deepEqual(field.options, M.ANCHORS, field.key)
  }
})
