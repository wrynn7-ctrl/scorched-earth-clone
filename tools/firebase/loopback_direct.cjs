'use strict';
// Preload for firebase-tools (node --require) on machines that set HTTPS_PROXY / HTTP_PROXY.
//
// firebase-tools sends EVERY request through the proxy it finds in the environment and ignores NO_PROXY, so its calls to
// the local emulators (127.0.0.1) get refused or sent into the void. This hook makes loopback requests go direct; all
// other requests still use the proxy exactly as before. It does nothing when no proxy is configured, and it is only
// loaded by tools/firebase/test.sh when one is.
const Module = require('node:module');

const LOOPBACK = new Set(['127.0.0.1', 'localhost', '::1', '[::1]']);
const realLoad = Module._load;

Module._load = function patchedLoad(request, parent, isMain) {
  const loaded = realLoad.apply(this, arguments);
  if (request !== 'undici' || loaded.__loopbackDirect) return loaded;
  const { Agent, Dispatcher, ProxyAgent: RealProxyAgent } = loaded;
  if (!Agent || !Dispatcher || !RealProxyAgent) return loaded;

  class LoopbackAwareProxyAgent extends Dispatcher {
    constructor(options) {
      super();
      this.viaProxy = new RealProxyAgent(options);
      this.direct = new Agent();
    }
    dispatch(options, handler) {
      let host = '';
      try {
        host = new URL(String(options.origin)).hostname;
      } catch {
        host = '';
      }
      return (LOOPBACK.has(host) ? this.direct : this.viaProxy).dispatch(options, handler);
    }
    async close() {
      await Promise.all([this.viaProxy.close(), this.direct.close()]);
    }
    async destroy(err) {
      await Promise.all([this.viaProxy.destroy(err), this.direct.destroy(err)]);
    }
  }
  loaded.ProxyAgent = LoopbackAwareProxyAgent;
  Object.defineProperty(loaded, '__loopbackDirect', { value: true });
  return loaded;
};
