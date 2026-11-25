/* SPDX-License-Identifier: GPL-3.0-only
 * Deterministic behavior fixtures for the actual bundled bridge. This is not a WebKit/device test.
 */
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const source = fs.readFileSync(path.join(__dirname, '../Weiktube/Resources/MediaBridge.js'), 'utf8');

function fixture(options = {}) {
  const events = [], frames = new Map(), timers = new Map(), observers = [];
  let clock = 0, sequence = 0, document;
  class Target {
    constructor() { this.listeners = new Map(); }
    addEventListener(name, callback, config) {
      const items = this.listeners.get(name) || [];
      items.push({ callback, once: !!config?.once }); this.listeners.set(name, items);
    }
    removeEventListener(name, callback) { this.listeners.set(name, (this.listeners.get(name) || []).filter(x => x.callback !== callback)); }
    dispatchEvent(event) {
      if (!event.target) event.target = this;
      for (const item of [...(this.listeners.get(event.type) || [])]) {
        item.callback(event);
        if (item.once) this.removeEventListener(event.type, item.callback);
      }
      if (this !== document && this instanceof Element) document.dispatchEvent(event);
      return true;
    }
  }
  class Style {
    constructor() { this.values = new Map(); }
    get cssText() { return [...this.values].map(([k, v]) => `${k}:${v}`).join(';'); }
    set cssText(value) {
      this.values.clear();
      for (const part of value.split(';')) { const split = part.indexOf(':'); if (split > 0) this.values.set(part.slice(0, split).trim(), part.slice(split + 1).trim()); }
    }
    setProperty(name, value) { this.values.set(name, value); }
    removeProperty(name) { this.values.delete(name); }
    getPropertyValue(name) { return this.values.get(name) || ''; }
    getPropertyPriority() { return ''; }
  }
  class Element extends Target {
    constructor(tag, rect = {x: 0, y: 0, width: 360, height: 200}) {
      super(); this.tagName = tag.toUpperCase(); this.children = []; this.parentElement = null;
      this.attributes = new Map(); this.style = new Style(); this.rect = rect;
      this.classes = new Set();
      this.classList = {contains: x => this.classes.has(x), add: x => this.classes.add(x), remove: x => this.classes.delete(x)};
    }
    get isConnected() { return this === document?.documentElement || !!this.parentElement?.isConnected; }
    appendChild(child) { child.parentElement = this; this.children.push(child); return child; }
    remove() { if (this.parentElement) this.parentElement.children = this.parentElement.children.filter(x => x !== this); this.parentElement = null; }
    getAttribute(name) { return name === 'style' ? (this.style.cssText || null) : this.attributes.get(name) ?? null; }
    setAttribute(name, value) { if (name === 'style') this.style.cssText = value; else this.attributes.set(name, value); }
    removeAttribute(name) { if (name === 'style') this.style.cssText = ''; else this.attributes.delete(name); }
    getBoundingClientRect() { const r = this.rect; return {...r, left: r.x, top: r.y, right: r.x + r.width, bottom: r.y + r.height}; }
    matches(selector) {
      return selector.split(',').some(selector => {
        const part = selector.trim();
        const match = part.match(/^([^[]*)(?:\[([^=\]]+)(?:="([^"]*)")?\])?$/);
        if (!match) return false;
        const [, main, attribute, value] = match;
        const base = !main || (main.startsWith('.') ? this.classes.has(main.slice(1)) : this.tagName.toLowerCase() === main.toLowerCase());
        return base && (!attribute || (this.attributes.has(attribute) && (value === undefined || this.attributes.get(attribute) === value)));
      });
    }
    closest(selector) { return this.matches(selector) ? this : this.parentElement?.closest(selector) ?? null; }
    querySelectorAll(selector) {
      const found = [];
      const walk = element => { for (const child of element.children) { if (child.matches(selector)) found.push(child); walk(child); } };
      walk(this); return found;
    }
    querySelector(selector) { return this.querySelectorAll(selector)[0] || null; }
  }
  class Video extends Element {
    constructor(rect) {
      super('video', rect); this.duration = 100; this._time = 0; this.paused = true; this.ended = false;
      this.muted = false; this.playbackRate = 1; this.readyState = 4; this.seeking = false;
      this.videoWidth = 1920; this.videoHeight = 1080; this.playCalls = 0; this.pauseCalls = 0;
      this.seekable = {length: 1, start: () => 0, end: () => this.duration}; this.webkitPresentationMode = 'inline';
    }
    get currentTime() { return this._time; }
    set currentTime(value) { this._time = value; this.seeking = true; this.dispatchEvent({type: 'seeking'}); }
    play() {
      this.playCalls++;
      if (this.rejectAutoplay) return Promise.reject(new Error('NotAllowedError'));
      this.paused = false; this.dispatchEvent({type: 'playing'}); return Promise.resolve();
    }
    pause() { if (this.paused) return; this.pauseCalls++; this.paused = true; this.dispatchEvent({type: 'pause'}); }
    settle(time = this._time) { this._time = time; this.seeking = false; this.dispatchEvent({type: 'seeked'}); }
    webkitSupportsPresentationMode(mode) { return mode === 'picture-in-picture'; }
    webkitSetPresentationMode(mode) { this.webkitPresentationMode = mode; this.dispatchEvent({type: 'webkitpresentationmodechanged'}); }
  }
  document = new Target();
  document.documentElement = new Element('html'); document.body = document.documentElement.appendChild(new Element('body'));
  document.hidden = !!options.hidden; document.title = 'Fixture video - YouTube';
  document.querySelectorAll = selector => document.documentElement.querySelectorAll(selector);
  document.createElement = name => new Element(name);
  const windowEvents = new Target();
  const location = new URL(options.url || 'https://m.youtube.com/watch?v=abcdefghijk');
  const context = vm.createContext({
    document, location, URL, innerWidth: 390, innerHeight: 800,
    crypto: {randomUUID: () => 'fixture-document'}, console,
    getComputedStyle: element => ({display: element.style.display || 'block', visibility: element.style.visibility || 'visible', opacity: element.style.opacity || '1'}),
    requestAnimationFrame: callback => { const id = ++sequence; frames.set(id, callback); return id; },
    cancelAnimationFrame: id => frames.delete(id),
    setTimeout: (callback, delay) => { const id = ++sequence; timers.set(id, {callback, at: clock + delay}); return id; },
    clearTimeout: id => timers.delete(id),
    MutationObserver: class {
      constructor(callback) { this.callback = callback; this.active = false; observers.push(this); }
      observe() { this.active = true; }
      disconnect() { this.active = false; }
    },
    addEventListener: windowEvents.addEventListener.bind(windowEvents),
    webkit: {messageHandlers: {weiktube: {postMessage: value => events.push(JSON.parse(JSON.stringify(value)))}}}
  });
  context.window = context; context.top = options.frame ? {} : context;
  vm.runInContext(source, context);
  let config = {role: options.role || 'player', token: 'token-a', generation: 1, userMuted: false, suspended: false, originalControls: true};
  const flush = () => {
    let steps = 0;
    while (frames.size) {
      if (++steps > 20) throw new Error('Unbounded animation-frame loop');
      const callbacks = [...frames.values()]; frames.clear(); callbacks.forEach(x => x());
    }
  };
  const tick = milliseconds => {
    clock += milliseconds;
    for (const [id, entry] of [...timers]) if (entry.at <= clock) { timers.delete(id); entry.callback(); }
    flush();
  };
  function video(rect) {
    const container = document.body.appendChild(new Element('div', rect)); container.classList.add('html5-video-player');
    return container.appendChild(new Video(rect));
  }
  function activate(values = {}) { config = {...config, ...values}; context.WeiktubeMedia.activate(config); flush(); }
  function command(name, args = {}) { return context.WeiktubeMedia.command(name, {...args, token: config.token, generation: config.generation}); }
  function sample() { return events.findLast(x => x.kind === 'media'); }
  function notify() { observers.filter(x => x.active).forEach(x => x.callback([])); flush(); }
  return {context, document, video, Element, events, observers, frames, timers, location,
    activate, command, sample, flush, tick, notify,
    windowEvent: (name, values = {}) => { windowEvents.dispatchEvent({type: name, ...values}); flush(); },
    click: (element, trusted = true) => { const event = {type: 'click', target: element, isTrusted: trusted, defaultPrevented: false,
      preventDefault() { this.defaultPrevented = true; }, stopPropagation() { this.stopped = true; }};
      element.dispatchEvent(event); flush(); return event; }
  };
}

async function run() {
  let assertions = 0;
  const check = (condition, label) => { assert.ok(condition, label); assertions++; };
  {
    const f = fixture({role: 'shorts', url: 'https://m.youtube.com/shorts/abcdefghijk'});
    const a = f.video({x: 0, y: 0, width: 390, height: 600});
    const b = f.video({x: 0, y: 900, width: 390, height: 600}); b.paused = false;
    f.activate();
    check(a.playCalls === 1 && b.paused, 'Only visible active Shorts can own audio');
    f.notify(); f.notify(); check(a.playCalls === 1, 'DOM updates do not repeatedly force playback');
    f.command('mute', {value: true}); f.flush();
    a.rect.y = -700; b.rect.y = 0; f.location.pathname = '/shorts/lmnopqrstuv'; f.notify();
    check(a.paused && b.playCalls === 1 && b.muted, 'New Short inherits explicit user mute and old element pauses');
    f.command('suspend', {value: true}); f.flush(); check(b.paused, 'Native suspension pauses active media');
    b.paused = false; b.dispatchEvent({type: 'playing'}); f.flush();
    check(b.paused && b.playCalls === 1, 'Inactive page scripts cannot reacquire audio');
    f.command('suspend', {value: false}); f.flush();
    check(!b.paused && b.playCalls === 2 && b.muted, 'Previously playing Short resumes once after ownership grant');
    f.command('pause', {elementID: f.sample().elementID}); f.flush();
    f.command('suspend', {value: true}); f.command('suspend', {value: false}); f.flush();
    check(b.paused && b.playCalls === 2, 'An explicitly paused Short stays paused on tab return');
  }
  {
    const f = fixture(); const video = f.video(); f.activate();
    const oldKey = f.sample().elementID;
    f.location.search = '?v=lmnopqrstuv';
    check(f.command('seek', {seconds: 30, elementID: oldKey}).ok === false, 'SPA identity changes reject cached old-element commands before next rAF');
    f.notify(); const newKey = f.sample().elementID;
    video.remove(); f.video();
    check(f.command('seek', {seconds: 30, elementID: newKey}).ok === false, 'Detached video element cannot be sought');
  }
  {
    const f = fixture({role: 'shorts', url: 'https://m.youtube.com/shorts/abcdefghijk'});
    const v = f.video(); v.currentSrc = 'https://media.example/source-a?private=secret'; f.activate();
    const oldKey = f.sample().elementID;
    const seek = f.command('seek', {seconds: 20, elementID: oldKey});
    v.currentSrc = 'blob:https://m.youtube.com/changed-source';
    check(f.command('seek', {seconds: 30, elementID: oldKey}).ok === false, 'Same DOM node with a changed source rejects old cached seek before next frame');
    v.settle(20); f.flush();
    check((await seek).ok === false, 'Source replacement aborts an already in-flight seek acknowledgment');
    check(v.playCalls === 1 && v.pauseCalls === 0 && !f.sample().elementID.includes('media.example') && !f.sample().elementID.includes('secret'), 'Adaptive source change emits opaque identity without pausing/restarting or exposing source URLs');
    f.command('pause', {elementID: f.sample().elementID}); f.flush();
    v.currentSrc = 'blob:https://m.youtube.com/another-adaptive-source'; f.notify();
    check(v.paused && v.playCalls === 1, 'A paused Short stays paused when the same video changes adaptive source');
  }
  {
    const f = fixture(); const v = f.video(); f.activate();
    let completed = false;
    const pending = f.command('seek', {seconds: 30, elementID: f.sample().elementID}); pending.then(() => { completed = true; });
    await Promise.resolve(); check(!completed, 'Assigning currentTime alone is not a successful seek');
    v.settle(30.2); f.flush(); const result = await pending;
    check(result.ok && result.position === 30.2, 'seeked within tolerance confirms seek');
    check(f.timers.size === 0, 'Seek confirmation removes its timeout');
    const mismatch = f.command('seek', {seconds: 60, elementID: f.sample().elementID}); v.settle(61); f.flush();
    check((await mismatch).ok === false, 'Wrong landing position is rejected');
    const timeout = f.command('seek', {seconds: 75, elementID: f.sample().elementID}); f.tick(1900);
    check((await timeout).ok === false, 'Missing seeked times out without fabricated success');
    v.seeking = false; f.notify();
    const oldContext = f.command('seek', {seconds: 80, elementID: f.sample().elementID});
    f.activate({token: 'token-b', generation: 2}); v.settle(80); f.flush();
    check((await oldContext).ok === false, 'Old context acknowledgment cannot affect new playback');
    check(f.context.WeiktubeMedia.command('pause', {token: 'wrong', generation: 2}).ok === false, 'Wrong bridge token rejects commands');
    const oldGeneration = f.command('seek', {seconds: 50, elementID: f.sample().elementID});
    f.activate({generation: 3}); v.settle(50); f.flush();
    check((await oldGeneration).ok === false, 'Changing generation rejects an old seek even when a token is accidentally reused');
  }
  {
    const f = fixture(); const video = f.video(); const controls = video.parentElement.appendChild(new f.Element('button'));
    f.activate(); f.command('zoom', {scale: 2, elementID: f.sample().elementID});
    check(video.style.getPropertyValue('transform') === 'scale(2)', 'Pinch scales the video element');
    check(!controls.style.getPropertyValue('transform') && !f.document.body.style.getPropertyValue('transform') && !video.parentElement.style.getPropertyValue('transform'), 'Zoom leaves controls and webpage unscaled');
    f.command('zoom', {scale: 1, elementID: f.sample().elementID});
    check(!video.style.getPropertyValue('transform') && !video.parentElement.style.getPropertyValue('overflow'), 'Reset removes only bridge-owned zoom and clipping');
    video.playbackRate = 1.25;
    check(!f.command('hold', {rate: 2}).ok && video.playbackRate === 1.25 && video.paused,
      'Holding a paused video leaves both its speed and transport unchanged');
    await video.play(); f.command('hold', {rate: 2, elementID: f.sample().elementID});
    check(video.playbackRate === 2, 'Hold applies requested supported playback speed');
    f.activate(); // Duplicate ready/didFinish activation must not erase restoration state.
    video.rect.y = 1000;
    f.command('release'); check(video.playbackRate === 1.25, 'Release restores speed even after offscreen/duplicate activation');
    video.rect.y = 0; f.notify(); f.command('hold', {rate: 2, elementID: f.sample().elementID});
    f.activate({token: 'new-context', generation: 2});
    check(video.playbackRate === 1.25, 'Context replacement restores the former held rate');
  }
  {
    const f = fixture(); const v = f.video();
    v.seekable = {length: 2, start: i => i === 0 ? 0 : 40, end: i => i === 0 ? 20 : 100}; f.activate();
    const gap = f.command('seek', {seconds: 25, elementID: f.sample().elementID});
    check(v.currentTime >= 0 && v.currentTime < 20, 'A requested seek into a range gap clamps inside the nearest real playable range');
    v.settle(); f.flush(); await gap;
    const end = f.command('seek', {seconds: 1000, elementID: f.sample().elementID});
    check(v.currentTime < v.duration && v.currentTime >= 40, 'A seek beyond duration never targets the exact final boundary');
    v.settle(); f.flush(); await end;
    v.duration = Infinity; f.notify();
    check(f.command('seek', {seconds: 10, elementID: f.sample().elementID}).ok === false, 'Unknown/infinite duration cannot accept a fabricated seek range');
  }
  {
    const f = fixture(); const v = f.video();
    v.style.cssText = 'transform:rotate(1deg);transform-origin:10% 20%'; f.activate();
    f.command('zoom', {scale: 3, x: 0.25, y: 0.75, elementID: f.sample().elementID});
    check(v.style.getPropertyValue('transform') === 'rotate(1deg) scale(3)' && v.style.getPropertyValue('transform-origin') === '25% 75%', 'Focal zoom composes with original transform at the requested video anchor');
    f.command('zoom', {scale: 50, x: -20, y: 20, elementID: f.sample().elementID});
    check(v.style.getPropertyValue('transform').endsWith('scale(8)') && v.style.getPropertyValue('transform-origin') === '0% 100%', 'Zoom and malicious out-of-range anchors clamp to supported media bounds');
    f.command('zoom', {scale: 2, x: NaN, y: Infinity, elementID: f.sample().elementID});
    check(v.style.getPropertyValue('transform-origin') === '50% 50%', 'Non-finite focal coordinates fall back to the video center');
    await v.play(); v.playbackRate = 1.5; f.command('hold', {rate: 2});
    f.location.search = '?v=lmnopqrstuv'; f.notify();
    check(v.playbackRate === 1.5 && v.style.getPropertyValue('transform') === 'rotate(1deg)' && v.style.getPropertyValue('transform-origin') === '10% 20%', 'Same-element route replacement restores held rate and original media styles');
  }
  {
    const f = fixture(); const v = f.video();
    const visible = v.parentElement.appendChild(new f.Element('button', {x: 39, y: 80, width: 78, height: 40}));
    const hidden = v.parentElement.appendChild(new f.Element('button')); hidden.setAttribute('hidden', '');
    const slider = v.parentElement.appendChild(new f.Element('div', {x: 0, y: 160, width: 390, height: 32})); slider.setAttribute('role', 'slider');
    f.activate();
    check(f.sample().controlRects.length === 2 && f.sample().controlRects[0].x === 0.1 && f.sample().controlRects[0].width === 0.2, 'Native gesture exclusion receives actual normalized visible control bounds');
    for (let i=0;i<100;i++) v.parentElement.appendChild(new f.Element('button'));
    f.notify(); check(f.sample().controlRects.length <= 64, 'DOM control reporting is bounded even on hostile pages');
    v.networkState = 2; v.error = {code: 3, message: 'sensitive raw response body'}; v.dispatchEvent({type: 'error'}); f.flush();
    check(f.sample().event === 'error' && f.sample().errorCode === 3 && f.sample().networkState === 2 && !JSON.stringify(f.sample()).includes('sensitive raw response'), 'Media diagnostics report fixed event/state/code without raw error bodies');
  }
  {
    const f = fixture(); const v = f.video();
    const button = v.parentElement.appendChild(new f.Element('button')); button.setAttribute('aria-label', 'Mag ich nicht');
    const original = button.appendChild(new f.Element('span')); original.textContent = 'Original control';
    let originalClicks = 0; button.addEventListener('click', () => originalClicks++);
    f.activate();
    check(f.command('dislike', {videoID: 'abcdefghijk', label: '1.234'}).ok, 'Dislike estimate accepts only a matching selected video');
    f.command('dislike', {videoID: 'abcdefghijk', label: '1.234'}); f.notify();
    let labels = f.document.querySelectorAll('[data-weiktube-dislike]');
    check(labels.length === 1 && labels[0].parentElement === button && labels[0].textContent === ' 1.234 · RYD' && labels[0].getAttribute('aria-label').includes('geschätzte'), 'Estimated count appends one attributable accessible text label without replacing the original control');
    f.click(button); check(originalClicks === 1 && button.children.includes(original), 'Dislike decoration preserves original click handler and existing children');
    check(f.command('dislike', {videoID: 'lmnopqrstuv', label: '9'}).ok === false && labels[0].textContent === ' 1.234 · RYD', 'Stale-video estimate cannot overwrite the active video count');
    f.command('dislike', {videoID: 'abcdefghijk', label: '<img onerror=secret>'});
    check(labels[0].textContent === ' <img onerror=secret> · RYD' && labels[0].children.length === 0, 'Estimate labels are inert text, never injected markup');
    f.command('dislike', {videoID: 'abcdefghijk', label: null});
    check(f.document.querySelectorAll('[data-weiktube-dislike]').length === 0 && button.children.includes(original), 'Opt-out removes only bridge-owned estimate labels');
    f.command('dislike', {videoID: 'abcdefghijk', label: '123'}); f.location.search = '?v=lmnopqrstuv'; f.notify();
    check(f.document.querySelectorAll('[data-weiktube-dislike]').length === 0, 'SPA video transition removes the previous video estimate');
    f.command('dislike', {videoID: 'lmnopqrstuv', label: 'x'.repeat(65)});
    check(f.document.querySelectorAll('[data-weiktube-dislike]').length === 0, 'Oversized estimates cannot create unbounded page labels');
  }
  {
    const f = fixture(); const video = f.video();
    video.parentElement.style.cssText = 'position:relative;color:red';
    video.style.cssText = 'width:320px'; f.document.body.style.cssText = 'background:white';
    const original = [video.parentElement, video, f.document.body].map(x => x.style.cssText);
    f.activate();
    for (let i = 0; i < 10; i++) {
      f.command('originalControls', {value: false});
      f.command('originalControls', {value: true});
    }
    check(JSON.stringify([video.parentElement, video, f.document.body].map(x => x.style.cssText)) === JSON.stringify(original), 'Ten fullscreen layout cycles restore original styles including multiply-styled ancestors');
  }
  {
    const f = fixture(); const video = f.video(); f.activate();
    const button = video.parentElement.appendChild(new f.Element('button')); button.classList.add('ytp-fullscreen-button');
    f.click(button, false); check(!f.events.some(x => x.kind === 'fullscreen'), 'Synthetic page clicks cannot request native fullscreen');
    const click = f.click(button, true);
    check(click.defaultPrevented && f.events.filter(x => x.kind === 'fullscreen').length === 1, 'Trusted fullscreen control routes to native state owner');
    f.windowEvent('pagehide'); check(!f.observers[0].active, 'Hidden retired page disconnects DOM observer');
    f.windowEvent('pageshow', {persisted: true}); check(f.observers[0].active, 'bfcache restore reinstalls the observer');
  }
  {
    const f = fixture({role: 'shorts'}); const v = f.video();
    v.readyState = 1; v.currentSrc = 'https://media.example.org/local.mp4';
    f.activate(); f.notify(); f.notify();
    check(v.playCalls === 1 && !v.paused, 'iPhone metadata-only preload starts a sourced Short once');
  }
  {
    const hidden = fixture({role: 'shorts', url: 'https://m.youtube.com/shorts/abcdefghijk', hidden: true});
    const video = hidden.video(); hidden.activate(); check(video.playCalls === 0, 'Hidden Short is never auto-started');
    const blocked = fixture({role: 'shorts', url: 'https://m.youtube.com/shorts/abcdefghijk'});
    const rejected = blocked.video(); rejected.rejectAutoplay = true; blocked.activate();
    await Promise.resolve(); blocked.flush();
    check(blocked.sample().autoplayBlocked && rejected.playCalls === 1, 'Autoplay rejection surfaces a real tap-to-play state');
    blocked.notify(); check(rejected.playCalls === 1, 'Autoplay rejection does not retry aggressively');
    const ad = fixture(); const advertisement = ad.video(); advertisement.parentElement.classList.add('ad-showing'); ad.activate();
    check(ad.command('seek', {seconds: 10, elementID: ad.sample().elementID}).ok === false, 'Advertisements reject seeks');
  }
  {
    const f = fixture({role: 'shorts', url: 'https://m.youtube.com/shorts/abcdefghijk'});
    const v = f.video(); v.readyState = 0; f.activate();
    check(v.playCalls === 0, 'Shorts does not consume its one start attempt before media readiness');
    v.readyState = 3; v.dispatchEvent({type: 'loadeddata'}); f.flush();
    check(v.playCalls === 1 && !v.paused, 'The first ready state receives one legitimate Shorts start attempt');
  }
  {
    const f = fixture({role: 'shorts', url: 'https://m.youtube.com/shorts/abcdefghijk'});
    const v = f.video(); let rejectOld;
    v.currentSrc = 'blob:https://m.youtube.com/old-source';
    v.play = function() { this.playCalls++; this.paused = false; return new Promise((_, reject) => { rejectOld = reject; }); };
    f.activate(); v.currentSrc = 'blob:https://m.youtube.com/new-source'; f.notify();
    rejectOld(new Error('old rejected playback request')); await Promise.resolve(); f.flush();
    check(!f.sample().autoplayBlocked, 'Old play-promise rejection cannot mark a replacement media source as autoplay-blocked');
  }
  {
    const f = fixture(); f.video(); f.activate();
    for (const href of ['https://m.youtube.com:8443/watch?v=lmnopqrstuv', 'https://credentials@m.youtube.com/watch?v=lmnopqrstuv',
      'https://youtube.com.evil.example/watch?v=lmnopqrstuv', 'http://m.youtube.com/watch?v=lmnopqrstuv', 'javascript:alert(1)']) {
      const anchor = f.document.body.appendChild(new f.Element('a')); anchor.setAttribute('href', href); anchor.href = href;
      const before = f.events.filter(x => x.kind === 'route').length, event = f.click(anchor);
      check(!event.defaultPrevented && f.events.filter(x => x.kind === 'route').length === before, 'Unapproved anchor origin/scheme/port is never forwarded as an internal route');
    }
    const anchor = f.document.body.appendChild(new f.Element('a')); anchor.href = 'https://m.youtube.com/watch?v=lmnopqrstuv'; anchor.setAttribute('href', anchor.href);
    const event = f.click(anchor); check(event.defaultPrevented && f.events.findLast(x => x.kind === 'route').url === anchor.href, 'A trusted allowed video anchor still hands off to the native route');
  }
  for (const options of [{url: 'https://youtube.com.evil.example/watch?v=abcdefghijk'}, {url: 'http://m.youtube.com/'},
    {url: 'https://m.youtube.com:8443/'}, {url: 'https://credentials@m.youtube.com/'}, {frame: true}]) {
    const f = fixture(options); check(f.context.WeiktubeMedia === undefined && f.events.length === 0, 'Unapproved origin/subframe has no native media bridge');
  }
  console.log(`PASS MediaBridge: ${assertions} behavioral assertions. Real bundled JavaScript exercised in Node DOM/media fixtures; no live YouTube, WebKit, simulator or device claim.`);
}

module.exports = {fixture};
if (require.main === module) run().catch(error => { console.error(error); process.exitCode = 1; });
