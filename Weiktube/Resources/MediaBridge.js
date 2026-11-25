/* SPDX-License-Identifier: GPL-3.0-only
 * App-owned, isolated WKContentWorld. Public HTMLMediaElement APIs only.
 * No cookies, tokens, response bodies, exposed stream URLs or private YouTube player APIs.
 */
(() => {
  'use strict';
  if (window.top !== window || window.WeiktubeMedia) return;
  const allowed = new Set(['youtube.com', 'www.youtube.com', 'm.youtube.com', 'music.youtube.com']);
  if (location.protocol !== 'https:' || (location.port && location.port !== '443') || location.username || location.password || !allowed.has(location.hostname)) return;
  let context = null, active = null, currentKey = '', activeRouteID = '', frame = 0, serial = 0;
  let userMuted = false, autoplayBlocked = false, attempted = '', savedRate = null;
  let zoom = 1, zoomX = 0.5, zoomY = 0.5, restore = [], suspended = true, resumeAfterSuspend = false, zoomState = null;
  const identities = new WeakMap();
  let dislikeEstimate = null;
  let mediaEvent = 'initial';
  const cleanID = value => /^[A-Za-z0-9_-]{11}$/.test(value || '') ? value : '';
  const idFromURL = raw => {
    try {
      const u = new URL(raw, location.href);
      if (u.protocol !== 'https:' || (u.port && u.port !== '443') || !allowed.has(u.hostname) || u.username || u.password) return '';
      return cleanID(u.pathname === '/watch' ? u.searchParams.get('v') : u.pathname.match(/^\/(?:shorts|live|embed)\/([^/]+)\/?$/)?.[1]);
    } catch (_) { return ''; }
  };
  const documentID = typeof crypto.randomUUID === 'function' ? crypto.randomUUID() : String(Date.now()) + Math.random();
  function send(kind, fields = {}) {
    try { window.webkit.messageHandlers.weiktube.postMessage(Object.assign({kind, documentID,
      token: context?.token || '', generation: context?.generation ?? -1}, fields)); } catch (_) { }
  }
  function visible(video) {
    if (!video.isConnected || video.closest('[hidden],[inert],[aria-hidden="true"]')) return 0;
    const s = getComputedStyle(video), r = video.getBoundingClientRect();
    if (s.display === 'none' || s.visibility === 'hidden' || Number(s.opacity) === 0) return 0;
    return Math.max(0, Math.min(innerWidth, r.right) - Math.max(0, r.left)) *
      Math.max(0, Math.min(innerHeight, r.bottom) - Math.max(0, r.top));
  }
  function selectedVideo() {
    let best = null, score = 0;
    for (const video of document.querySelectorAll('video')) {
      const area = visible(video);
      if (area > score) { best = video; score = area; }
    }
    return best;
  }
  function identity(video) {
    if (!video) return '';
    // Compare the source only inside this isolated closure. The opaque serial is sent,
    // never a blob/CDN/media URL. Reused DOM nodes still retire outstanding commands.
    const source = video.currentSrc || video.getAttribute('src') || '';
    let entry = identities.get(video);
    if (!entry || entry.source !== source) {
      entry = {serial: ++serial, source}; identities.set(video, entry);
    }
    return documentID + ':' + entry.serial + ':' + idFromURL(location.href);
  }
  function ranges(video) {
    const result = [];
    if (!video || !Number.isFinite(video.duration) || video.duration <= 0) return result;
    try { for (let i = 0; i < Math.min(video.seekable.length, 64); i++) {
      const start = Math.max(0, video.seekable.start(i)), end = Math.min(video.duration, video.seekable.end(i));
      if (Number.isFinite(start) && Number.isFinite(end) && end > start) result.push([start, end]);
    }} catch (_) { return []; }
    return result;
  }
  function advertisement(video) { return !!video?.closest('.ad-showing,.ad-interrupting'); }
  function pauseOtherVideos(video) {
    for (const v of document.querySelectorAll('video')) if ((v !== video || suspended) && !v.paused) v.pause();
  }
  function tryPlay(video, explicit = false) {
    if (!video || suspended || advertisement(video)) return false;
    // A selected source can wait at HAVE_METADATA until play() starts loading frames.
    if (!explicit && video.readyState < 2 && !video.currentSrc && !video.getAttribute('src')) return false;
    const key = identity(video);
    const playToken = context?.token, playGeneration = context?.generation;
    if (!explicit && attempted === key) return false;
    attempted = key;
    if (context?.role === 'shorts') video.muted = userMuted;
    try {
      const promise = video.play();
      if (promise?.catch) promise.catch(() => { if (context?.token === playToken && context?.generation === playGeneration && currentKey === key && identity(video) === key) { autoplayBlocked = true; schedule(); } });
      autoplayBlocked = false;
      return true;
    } catch (_) { autoplayBlocked = true; schedule(); return false; }
  }
  function restoreLayout() {
    // A node can be styled more than once while isolating its ancestor chain.
    // Undo in reverse order so its original style is the final value restored.
    for (const [node, previous] of [...restore].reverse()) if (node.isConnected) {
      if (previous === null) node.removeAttribute('style'); else node.setAttribute('style', previous);
    }
    restore = [];
  }
  function style(node, value) {
    if (!node) return;
    restore.push([node, node.getAttribute('style')]);
    node.style.cssText += ';' + value;
  }
  function isolate(video) {
    restoreZoom();
    restoreLayout();
    if (!context || context.role !== 'player' || context.originalControls || !video) {
      if (video === active) applyZoom();
      return;
    }
    // Retain the page's own media controls; only the containing player is fitted.
    const player = video.closest('.html5-video-player') || video.parentElement;
    if (!player) return;
    style(document.documentElement, 'overflow:hidden!important;background:#000!important;');
    style(document.body, 'overflow:hidden!important;background:#000!important;');
    let node = player;
    while (node && node !== document.body) {
      if (node.parentElement) for (const sibling of node.parentElement.children) {
        if (sibling !== node && !['SCRIPT','STYLE','LINK'].includes(sibling.tagName)) style(sibling, 'visibility:hidden!important;pointer-events:none!important;');
      }
      style(node, 'position:static!important;transform:none!important;max-height:none!important;max-width:none!important;');
      node = node.parentElement;
    }
    style(player, 'position:fixed!important;inset:0!important;width:100vw!important;height:100vh!important;z-index:2147480000!important;background:#000!important;visibility:visible!important;');
    style(video, 'position:absolute!important;inset:0!important;width:100%!important;height:100%!important;object-fit:contain!important;');
    applyZoom();
  }
  function applyZoom() {
    if (!active) return;
    if (zoom === 1) { restoreZoom(); return; }
    if (zoomState && zoomState.video !== active) restoreZoom();
    if (!zoomState) {
      zoomState = {video: active, parent: active.parentElement,
        transform: active.style.getPropertyValue('transform'), transformPriority: active.style.getPropertyPriority('transform'),
        origin: active.style.getPropertyValue('transform-origin'), originPriority: active.style.getPropertyPriority('transform-origin'),
        overflow: active.parentElement?.style.getPropertyValue('overflow') || '', overflowPriority: active.parentElement?.style.getPropertyPriority('overflow') || ''};
    }
    // Never scale a WKWebView, webpage or controls.
    const base = zoomState.transform === 'none' ? '' : zoomState.transform;
    active.style.setProperty('transform', `${base} scale(${zoom})`.trim(), 'important');
    active.style.setProperty('transform-origin', `${zoomX*100}% ${zoomY*100}%`, 'important');
    if (active.parentElement) active.parentElement.style.setProperty('overflow', 'hidden', 'important');
  }
  function restoreZoom() {
    if (!zoomState) return;
    const old = zoomState; zoomState = null;
    function put(node, property, value, priority) {
      if (!node) return;
      if (value) node.style.setProperty(property, value, priority); else node.style.removeProperty(property);
    }
    put(old.video, 'transform', old.transform, old.transformPriority);
    put(old.video, 'transform-origin', old.origin, old.originPriority);
    put(old.parent, 'overflow', old.overflow, old.overflowPriority);
  }
  function update() {
    frame = 0;
    if (!context) return;
    updateDislike();
    const video = selectedVideo(), key = identity(video), videoID = idFromURL(location.href);
    if (key !== currentKey) {
      // An adaptive source change on the same video must not pause, reload, or
      // restart a paused element. A different route/element gets a new attempt.
      const keepAttempt = active === video && videoID === activeRouteID && !!attempted;
      if (active) { if (active !== video) active.pause(); restoreZoom(); if (savedRate !== null) active.playbackRate = savedRate; }
      active = video; currentKey = key; activeRouteID = videoID; savedRate = null; autoplayBlocked = false;
      attempted = keepAttempt ? key : ''; zoom = 1;
      if (video) isolate(video);
    }
    pauseOtherVideos(video);
    if (video && context.role === 'shorts' && !suspended && !document.hidden && !attempted) tryPlay(video);
    let pipAvailable = false;
    try { pipAvailable = !!video && typeof video.webkitSupportsPresentationMode === 'function' && video.webkitSupportsPresentationMode('picture-in-picture'); } catch (_) { }
    const rect = video?.getBoundingClientRect();
    const liveBadge = video?.closest('.html5-video-player')?.querySelector('.ytp-live-badge');
    const liveBadgeStyle = liveBadge ? getComputedStyle(liveBadge) : null;
    const liveBadgeRect = liveBadge?.getBoundingClientRect();
    const live = !!video && (video.duration === Infinity || !!(liveBadge && liveBadgeStyle.display !== 'none' && liveBadgeStyle.visibility !== 'hidden' && liveBadgeRect.width > 0 && liveBadgeRect.height > 0));
    const controlHost=video?.closest('.html5-video-player')||video?.parentElement;
    const controls=controlHost ? Array.from(controlHost.querySelectorAll?.('button,[role="button"],[role="slider"],input,select,a,.ytp-popup,.ytp-menuitem')||[]):[];
    const controlRects=controls.slice(0,64).filter(control=>visible(control)>0).map(control=>{
      const r=control.getBoundingClientRect();return {x:r.x/innerWidth,y:r.y/innerHeight,width:r.width/innerWidth,height:r.height/innerHeight};
    });
    send('media', {videoID, elementID:key, title:document.title.replace(/\s*-\s*YouTube$/, '').slice(0,200),
      controlRects,
      event:mediaEvent,readyState:video?.readyState||0,networkState:video?.networkState||0,errorCode:video?.error?.code||0,
      rect:rect ? {x:rect.x/innerWidth,y:rect.y/innerHeight,width:rect.width/innerWidth,height:rect.height/innerHeight} : {x:0,y:0,width:0,height:0}, live,
      position:video && Number.isFinite(video.currentTime) ? video.currentTime : 0,
      duration:video && Number.isFinite(video.duration) ? video.duration : 0,
      playing:!!video && !video.paused && !video.ended, muted:!!video?.muted, seeking:!!video?.seeking, ended:!!video?.ended,
      width:video?.videoWidth || 0,height:video?.videoHeight || 0,rate:video?.playbackRate || 1,
      ready:!!video && video.readyState >= 2,seekable:ranges(video).length > 0,pipAvailable,
      pip:video?.webkitPresentationMode === 'picture-in-picture',autoplayBlocked,advertisement:advertisement(video)});
  }
  function schedule() { if (!frame && context) frame = requestAnimationFrame(update); }
  function verified(expected) { return !!active && active.isConnected && !suspended && !advertisement(active) &&
    (!expected || expected === currentKey) && identity(active) === currentKey && selectedVideo() === active; }
  function setSuspended(value) {
    const next = !!value;
    if (next && !suspended) resumeAfterSuspend = !!active && !active.paused && !active.ended;
    if (!next && suspended && resumeAfterSuspend && context?.role === 'shorts') attempted = '';
    suspended = next;
    if (suspended) { pauseOtherVideos(null); release(); }
    else resumeAfterSuspend = false;
    schedule();
  }
  function command(name, args = {}) {
    if (!context || args.token !== context.token || args.generation !== context.generation) return {ok:false};
    if (name === 'suspend') { setSuspended(args.value); return {ok:true}; }
    if (name === 'originalControls') { context.originalControls = !!args.value; isolate(active); schedule(); return {ok:true}; }
    if (name === 'mute') { userMuted = !!args.value; if (active) active.muted = userMuted; schedule(); return {ok:true}; }
    // Releasing a held speed must also work after the selected element becomes offscreen.
    if (name === 'release') { release(); schedule(); return {ok:true}; }
    if (name === 'dislike') {
      if (!cleanID(args.videoID) || args.videoID !== idFromURL(location.href)) return {ok:false};
      dislikeEstimate = typeof args.label === 'string' && args.label.length > 0 && args.label.length <= 64 ? {videoID:args.videoID,label:args.label}:null;
      updateDislike(); return {ok:true};
    }
    if (!verified(args.elementID)) return {ok:false};
    if (name === 'play') return {ok:tryPlay(active,true)};
    if (name === 'pause') { attempted = currentKey; active.pause(); schedule(); return {ok:true}; }
    if (name === 'seek') {
      const rs = ranges(active), wanted = Number(args.seconds);
      if (!rs.length || !Number.isFinite(wanted)) return {ok:false};
      let target = wanted;
      if (!rs.some(([a,b]) => target >= a && target <= b)) target = rs.flat().reduce((a,b) => Math.abs(b-wanted)<Math.abs(a-wanted)?b:a);
      target = Math.max(0,Math.min(active.duration, target));
      const selectedRange = rs.find(([a,b]) => target >= a && target <= b);
      if (!selectedRange) return {ok:false};
      // Seeking exactly to an end can end a Short or cross a nonseekable gap.
      const [rangeStart, rangeEnd] = selectedRange;
      target = Math.max(rangeStart, Math.min(target, rangeEnd - Math.min(0.05, (rangeEnd-rangeStart)/2)));
      const seekingVideo=active, seekingKey=currentKey, seekingToken=context.token, seekingGeneration=context.generation;
      return new Promise(resolve => {
        let finished=false, timeout;
        const finish=success=>{
          if(finished)return;finished=true;clearTimeout(timeout);
          seekingVideo.removeEventListener('seeked',settled);
          const valid=success&&context?.token===seekingToken&&context?.generation===seekingGeneration&&verified(seekingKey)&&Math.abs(seekingVideo.currentTime-target)<=0.35;
          resolve({ok:valid,position:valid?seekingVideo.currentTime:null});schedule();
        };
        const settled=()=>finish(true);
        seekingVideo.addEventListener('seeked',settled,{once:true});
        timeout=setTimeout(()=>finish(false),1900);
        try{
          if(Math.abs(seekingVideo.currentTime-target)<=0.01&&!seekingVideo.seeking){finish(true);return;}
          seekingVideo.currentTime=target;
        }catch(_){finish(false);}
      });
    }
    if (name === 'rate') { const rate = Number(args.rate); if (![0.25,0.5,0.75,1,1.25,1.5,1.75,2,2.5,3].includes(rate)) return {ok:false};
      try { active.playbackRate = rate; schedule(); return {ok:Math.abs(active.playbackRate-rate)<0.01,rate:active.playbackRate}; } catch (_) { return {ok:false}; } }
    if (name === 'hold') {
      if (active.paused || active.ended) return {ok:false};
      const previous = active.playbackRate;
      const result = command('rate', args);
      if (result.ok && savedRate === null) savedRate = previous;
      return result;
    }
    if (name === 'zoom') { zoom=Math.min(8,Math.max(1,Number(args.scale)||1));
      zoomX=Number.isFinite(args.x)?Math.min(1,Math.max(0,args.x)):0.5;
      zoomY=Number.isFinite(args.y)?Math.min(1,Math.max(0,args.y)):0.5;
      applyZoom();return {ok:true}; }
    if (name === 'pip') { try { if (!active.webkitSupportsPresentationMode?.('picture-in-picture')) return {ok:false};
      active.webkitSetPresentationMode(active.webkitPresentationMode === 'picture-in-picture'?'inline':'picture-in-picture'); return {ok:true}; } catch (_) { return {ok:false}; } }
    return {ok:false};
  }
  function release() { if (active && savedRate !== null) { active.playbackRate = savedRate; savedRate = null; } }
  function updateDislike() {
    const existing=Array.from(document.querySelectorAll('[data-weiktube-dislike]'));
    if(!dislikeEstimate || context?.role!=='player' || dislikeEstimate.videoID!==idFromURL(location.href)){
      existing.forEach(node=>node.remove());return;
    }
    const target=Array.from(document.querySelectorAll('button[aria-label],button[title]')).find(button=>{
      const label=button.getAttribute('aria-label')||button.getAttribute('title')||'';
      return /dislike|mag ich nicht|gefällt mir nicht/i.test(label)&&visible(button)>0;
    });
    if(!target)return;
    let label=existing.find(node=>node.parentElement===target);
    existing.filter(node=>node!==label).forEach(node=>node.remove());
    if(!label){label=document.createElement('span');label.setAttribute('data-weiktube-dislike','true');target.appendChild(label);}
    const text=` ${dislikeEstimate.label} · RYD`;
    if(label.textContent!==text)label.textContent=text;
    label.title='Geschätzte Dislike-Daten von Return YouTube Dislike';
    label.setAttribute('aria-label',`${dislikeEstimate.label} Dislikes, geschätzte Daten von Return YouTube Dislike`);
  }
  function activate(next) {
    if (!next || typeof next.token !== 'string' || next.token.length > 128 || !Number.isSafeInteger(next.generation)) return false;
    if (context?.token === next.token && context?.generation === next.generation) {
      const layoutChanged = context.originalControls !== next.originalControls;
      context = next; userMuted = !!next.userMuted; setSuspended(next.suspended);
      if (layoutChanged) isolate(active);
      return true;
    }
    release();
    context=next;userMuted=!!next.userMuted;suspended=!!next.suspended;currentKey='';attempted='';resumeAfterSuspend=false;schedule();return true;
  }
  function routeClick(event) {
    if (!event.isTrusted || event.defaultPrevented || event.metaKey || event.ctrlKey) return;
    const anchor=event.target?.closest?.('a[href]');if(!anchor)return;
    try {
      const u=new URL(anchor.href,location.href);
      if(u.protocol!=='https:'||(u.port&&u.port!=='443')||!allowed.has(u.hostname)||u.username||u.password)return;
      if(context?.role==='shorts'&&/^\/shorts/.test(u.pathname))return;
      if(idFromURL(u.href)){event.preventDefault();event.stopPropagation();send('route',{url:u.href});}
    }catch(_){}
  }
  document.addEventListener('click', event => {
    const fullscreenButton=event.target?.closest?.('.ytp-fullscreen-button');
    if(event.isTrusted&&fullscreenButton&&context?.role==='player'){
      event.preventDefault();event.stopPropagation();send('fullscreen');return;
    }
    routeClick(event);
    if(!event.isTrusted)return;
    const b=event.target?.closest?.('button,[role="button"]');
    const label=(b?.getAttribute('aria-label')||b?.getAttribute('title')||'').trim();
    if(/^(mute|stummschalten|ton ausschalten)(\s|$)/i.test(label)){userMuted=true;send('muteIntent',{muted:true});}
    if(/^(unmute|ton einschalten|sound on)(\s|$)/i.test(label)){userMuted=false;send('muteIntent',{muted:false});}
  },true);
  ['timeupdate','playing','pause','ended','loadedmetadata','loadeddata','canplay','durationchange','emptied','volumechange','ratechange','seeking','seeked','progress','error','webkitpresentationmodechanged'].forEach(event=>document.addEventListener(event,()=>{mediaEvent=event;schedule();},true));
  ['resize','popstate','yt-navigate-finish'].forEach(event=>window.addEventListener(event,schedule));
  document.addEventListener('visibilitychange',()=>{if(document.hidden)release();schedule();});
  const observer = new MutationObserver(schedule);
  observer.observe(document,{childList:true,subtree:true});
  window.addEventListener('pageshow', event => {
    if (event.persisted) {
      observer.observe(document,{childList:true,subtree:true});
      currentKey = ''; attempted = '';
    }
    schedule();
  });
  window.addEventListener('pagehide',()=>{release();restoreZoom();restoreLayout();observer.disconnect();if(frame)cancelAnimationFrame(frame);frame=0;});
  window.WeiktubeMedia = Object.freeze({activate,command,documentID});
  send('ready');
})();
