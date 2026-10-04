// A minimal event emitter: `on` returns a function that unsubscribes.
export class Emitter {
  constructor() {
    this._listeners = new Map()
  }

  on(event, callback) {
    if (!this._listeners.has(event)) this._listeners.set(event, new Set())
    this._listeners.get(event).add(callback)
    return () => this._listeners.get(event)?.delete(callback)
  }

  emit(event, payload) {
    for (const callback of this._listeners.get(event) || []) callback(payload)
  }
}
