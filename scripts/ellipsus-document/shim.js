// JavaScriptCore has no Web Crypto; Yjs only needs random client ids.
if (typeof globalThis.crypto === 'undefined') {
  globalThis.crypto = {
    subtle: {},
    getRandomValues(array) {
      for (let i = 0; i < array.length; i++) array[i] = Math.floor(Math.random() * 4294967296)
      return array
    },
  }
}
