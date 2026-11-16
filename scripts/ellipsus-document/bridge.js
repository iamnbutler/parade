import './shim.js'
import * as Y from 'yjs'

// Reads an Ellipsus Reader page's document: the API's base64 Yjs updates
// in, the ProseMirror content out as plain JSON nodes.
function node(n) {
  if (n instanceof Y.XmlText) {
    return { text: n.toDelta().map(d => ({ insert: d.insert, attrs: d.attributes || {} })) }
  }
  if (n instanceof Y.XmlElement) {
    return { tag: n.nodeName, attrs: n.getAttributes(), children: n.toArray().map(node) }
  }
  return { text: [] }
}

// JavaScriptCore has no atob.
const ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
function b64(text) {
  const clean = text.replace(/[^A-Za-z0-9+/]/g, '')
  const out = new Uint8Array(Math.floor(clean.length * 3 / 4))
  let bits = 0, acc = 0, n = 0
  for (let i = 0; i < clean.length; i++) {
    acc = (acc << 6) | ALPHABET.indexOf(clean[i])
    bits += 6
    if (bits >= 8) { bits -= 8; out[n++] = (acc >> bits) & 255 }
  }
  return out.subarray(0, n)
}

globalThis.parseEllipsusDocument = function (updates) {
  const doc = new Y.Doc()
  for (const u of updates) Y.applyUpdate(doc, b64(u))
  const fragment = doc.getXmlFragment('draft-content')
  return JSON.stringify(fragment.toArray().map(node))
}
