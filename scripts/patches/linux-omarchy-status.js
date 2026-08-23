#!/usr/bin/env node

"use strict";

const fs = require("fs");
const path = require("path");

const appRoot = process.argv[2];

if (!appRoot) {
  console.error("usage: linux-omarchy-status.js EXTRACTED_APP_DIR");
  process.exit(2);
}

const mainFile = path.join(appRoot, ".webpack/main/index.js");
const rendererFile = path.join(
  appRoot,
  ".webpack/renderer/status/index.js",
);
const marker = "__wisprFlowOmarchyV15";

for (const file of [mainFile, rendererFile]) {
  if (!fs.existsSync(file)) {
    throw new Error(`Wispr Flow 1.6.7 bundle file missing: ${file}`);
  }
}

const replaceExact = (source, needle, replacement, label) => {
  const first = source.indexOf(needle);
  const last = source.lastIndexOf(needle);

  if (first < 0 || first !== last) {
    throw new Error(`${label} anchor count is not exactly one`);
  }

  return source.slice(0, first) + replacement + source.slice(first + needle.length);
};

let main = fs.readFileSync(mainFile, "utf8");
let renderer = fs.readFileSync(rendererFile, "utf8");

if (main.includes(marker)) {
  if (
    !renderer.includes("__wisprFlowSetStatusMode") ||
    !renderer.includes("WISPR_FLOW_OMARCHY_BAR_DRAG") ||
    !main.includes("WISPR_FLOW_OMARCHY_BAR_VISIBILITY")
  ) {
    throw new Error("partial Wispr Flow Omarchy V15 patch found");
  }

  console.log("Wispr Flow Omarchy V15 patch already present");
  process.exit(0);
}

const flowBarNeedle =
  'else if(e.startsWith("wispr-flow://stop-hands-free"))j();' +
  'else if(e.startsWith("wispr-flow://switch-mic"))$(e);';
const flowBarPatch =
  'else if(e.startsWith("wispr-flow://stop-hands-free"))j();' +
  'else if(e.startsWith("wispr-flow://flow-bar/")){' +
  'const t=new URL(e).pathname.slice(1);' +
  '["show","hide"].includes(t)' +
  '?(process.__wisprFlowSetStatusEnabled("show"===t),' +
  'n().info(`[Status] ${t} Flow bar via Omarchy`))' +
  ':n().warn(`[Status] Invalid Flow bar action: ${t}`)' +
  '/*WISPR_FLOW_OMARCHY_BAR_VISIBILITY*/}' +
  'else if(e.startsWith("wispr-flow://switch-mic"))$(e);';

const horizontalRenderer = (source) => {
  source = replaceExact(
    source,
    '"data-bar-position":g,',
    '"data-bar-position":"bottom",',
    "horizontal compact Flow bar",
  );

  return replaceExact(
    source,
    "Ht=g||s!==I,",
    "Ht=!0/*WISPR_FLOW_OMARCHY_BAR_DRAG*/,",
    "compact Flow bar drag",
  );
};

if (/__wisprFlow(?:KeybindingLaunchMode|OmarchyV)/.test(main)) {
  throw new Error(
    "superseded app patch found; restore the packaged app.asar before patching",
  );
}

const entryNeedle =
  'var __webpack_exports__={};(()=>{"use strict";var e=__webpack_require__(84157),t=__webpack_require__(69493),';
const entryPatch =
  'var __webpack_exports__={};(()=>{"use strict";var e=__webpack_require__(84157);' +
  'const __wisprFlowOmarchyV15=!0;' +
  'if(e.shell&&!e.shell.__wisprFlowOmarchyV15){e.shell.__wisprFlowOmarchyV15=!0;' +
  'const __wfOpenExternal=e.shell.openExternal,__wfBlockedOpenExternal=async()=>void 0;' +
  'e.shell.openExternal=__wfBlockedOpenExternal;' +
  'setTimeout(()=>{e.shell.openExternal===__wfBlockedOpenExternal&&(e.shell.openExternal=__wfOpenExternal)},1e4)}' +
  'var t=__webpack_require__(69493),';
main = replaceExact(main, entryNeedle, entryPatch, "main entry");

main = replaceExact(main, flowBarNeedle, flowBarPatch, "Flow bar route");

const hubNeedle =
  'b=()=>i.app.isPackaged?d.RA.prefs?.isUpdating?(a().info("Not showing hub window at launch: app is updating"),!1):i.app.getLoginItemSettings().wasOpenedAtLogin?(a().info("Not showing hub window at launch: app was opened at login"),!1):(a().info("Showing hub window at launch: normal app launch"),!0):(a().info("Showing hub window at launch: dev app launch"),!0),';
const hubPatch =
  'b=()=>(a().info("Not showing hub window at launch: Omarchy uses the tray control"),!1),';
main = replaceExact(main, hubNeedle, hubPatch, "hub launch");

const windowNeedle =
  'backgroundThrottling:!1},transparent:!0,hasShadow:!1,roundedCorners:!1,type:b.tD?"panel":"toolbar",title:"Flow Status Indicator"';
const windowPatch =
  'backgroundThrottling:!1},transparent:!0,backgroundColor:"#00000000",hasShadow:!1,roundedCorners:!1,type:b.tD?"panel":"toolbar",title:"Flow Status Indicator"';
main = replaceExact(main, windowNeedle, windowPatch, "status transparency");

const stateNeedle = "let P,W,F=!1,U=!1;const Q=new r.eu;";
const statePatch =
  'let P,W,F=!1,U=!1;const __wfStatusChannel="wispr-flow:status-mode",' +
  '__wfCompactTop={width:168,height:64};' +
  'let __wfStatusMode="hidden",__wfStatusEnabled=!0;' +
  'const __wfUpdateStatusWindow=()=>{const t=__wfStatusEnabled?__wfStatusMode:"hidden",n=D.RA.statusWindow;' +
  'if(!n||n.isDestroyed())return;Array.from([P,W]).forEach(e=>(0,O.iM)(e)),P=void 0,W=void 0;' +
  'if("hidden"===t)return n.setIgnoreMouseEvents(!0,{forward:!0}),n.hide(),void a().info("[Status] Hidden compact status window");' +
  'const r="compact"===t;n.setIgnoreMouseEvents(!1);P=te(),ee().then(()=>{' +
  'n.isDestroyed()||(G(n),n.setShape(r?[{x:28,y:0,width:112,height:60}]:[]),G(n),' +
  'b.H8&&n.setAlwaysOnTop(!0,"screen-saver"),n.showInactive())})' +
  '.catch(e=>a().warn(`[Status] Compact mode update failed: ${String(e)}`))},' +
  '__wfApplyStatusMode=(e,t)=>{if(e.sender!==D.RA.statusWindow?.webContents)return;' +
  'if(!["hidden","compact","full"].includes(t))return void a().warn(`[Status] Invalid compact mode: ${t}`);' +
  '__wfStatusMode=t,__wfUpdateStatusWindow()};' +
  'process.__wisprFlowSetStatusEnabled=e=>{__wfStatusEnabled=!!e,__wfUpdateStatusWindow()};const Q=new r.eu;';
main = replaceExact(main, stateNeedle, statePatch, "status state");

const showNeedle =
  "Array.from([P,W]).forEach(e=>(0,O.iM)(e)),P=te(),G(e),b.H8&&e.setAlwaysOnTop(!0,\"screen-saver\"),e.showInactive(),a().info(\"Showing status window\")";
const showPatch =
  "Array.from([P,W]).forEach(e=>(0,O.iM)(e)),b.H8&&e.setAlwaysOnTop(!0,\"screen-saver\"),a().info(\"Prepared compact status window\")";
main = replaceExact(main, showNeedle, showPatch, "status startup visibility");

const boundsNeedle =
  'Z=e=>{const t=(0,I.mn)().flowBarNotifs;return((e,t,n,r,i,s=320,a=u)=>{const{x:o,y:c,width:l,height:d}=h(e,t,r,i);if("left"===n||"right"===n){let i;if(r){const{bounds:r}=e,{left:s,right:o}=p(e,t.isVisible);i="left"===n?r.x+s:r.x+r.width-a.width-o}else i="left"===n?o:o+l-a.width;const s=Math.min(a.height,d);return{x:i,y:c+(d-s)/2,width:a.width,height:s}}return{x:o+(l-440)/2,y:c+d-s,width:440,height:s}})(e,D.RA.dockInfo,D.RA.prefs?.user.statusDockEdge??y.We,b.tD,b.H8,t?573:void 0,t?d:void 0)},X=';
const boundsPatch =
  'Z=e=>{const t=(0,I.mn)().flowBarNotifs,n=((e,t,n,r,i,s=320,a=u)=>{const{x:o,y:c,width:l,height:d}=h(e,t,r,i);if("left"===n||"right"===n){let i;if(r){const{bounds:r}=e,{left:s,right:o}=p(e,t.isVisible);i="left"===n?r.x+s:r.x+r.width-a.width-o}else i="left"===n?o:o+l-a.width;const s=Math.min(a.height,d);return{x:i,y:c+(d-s)/2,width:a.width,height:s}}return{x:o+(l-440)/2,y:c+d-s,width:440,height:s}})(e,D.RA.dockInfo,D.RA.prefs?.user.statusDockEdge??y.We,b.tD,b.H8,t?573:void 0,t?d:void 0);' +
  'if("full"===__wfStatusMode)return n;' +
  'const r=__wfCompactTop,i=D.RA.prefs?.user.statusDockEdge??y.We,{bounds:s}=e;' +
  'if("left"===i)return{x:s.x+26,y:Math.round(s.y+.5*(s.height-r.height)),width:r.width,height:r.height};' +
  'if("right"===i)return{x:s.x+s.width-r.width-26,y:Math.round(s.y+.5*(s.height-r.height)),width:r.width,height:r.height};' +
  'return{x:Math.round(s.x+.5*s.width-r.width/2),y:s.y+s.height-r.height-26,width:r.width,height:r.height}},X=';
main = replaceExact(main, boundsNeedle, boundsPatch, "compact bounds");

const monitorNeedle = 'ee=async()=>{if("active"!==D.RA.systemState)return;';
const monitorPatch =
  'ee=async()=>{if("hidden"===__wfStatusMode)return;if("active"!==D.RA.systemState)return;';
main = replaceExact(main, monitorNeedle, monitorPatch, "hidden monitor loop");

const ipcNeedle =
  'se=()=>{i.app.prependOnceListener("before-quit",async()=>{Array.from([P,W]).forEach(e=>(0,O.iM)(e)),i.globalShortcut.isRegistered("Escape")&&i.globalShortcut.unregister("Escape")})';
const ipcPatch =
  'se=()=>{i.ipcMain.on(__wfStatusChannel,__wfApplyStatusMode),' +
  'i.app.prependOnceListener("before-quit",async()=>{i.ipcMain.removeListener(__wfStatusChannel,__wfApplyStatusMode),' +
  'Array.from([P,W]).forEach(e=>(0,O.iM)(e)),i.globalShortcut.isRegistered("Escape")&&i.globalShortcut.unregister("Escape")})';
main = replaceExact(main, ipcNeedle, ipcPatch, "status mode IPC");

const tooltipMatch = renderer.match(/statusTooltip:"([^"]+)"/);
const layoutMatch = renderer.match(
  /rootContainer:"([^"]+)",islandStage:"([^"]+)",islandStageHidden:"[^"]+",notificationLayer:"([^"]+)",indicatorLayer:"([^"]+)",reminderLayer:"([^"]+)"/,
);
if (!tooltipMatch || !layoutMatch) {
  throw new Error("status renderer class map not found");
}

const [, rootClass, islandClass, notificationClass, indicatorClass, reminderClass] =
  layoutMatch;
const rendererPrefix =
  `;(()=>{document.documentElement.dataset.wisprCompactStatus="1";` +
  `const e=document.createElement("style");` +
  `e.textContent='html[data-wispr-compact-status="1"],html[data-wispr-compact-status="1"] body,html[data-wispr-compact-status="1"] #root{background:transparent!important}' +` +
  `'html[data-wispr-status-mode="compact"] .${tooltipMatch[1]}{display:none!important}' +` +
  `'html[data-wispr-compact-status="1"] .${rootClass}[data-bar-position="bottom"]{justify-content:flex-start!important}' +` +
  `'html[data-wispr-compact-status="1"] .${rootClass}[data-bar-position="bottom"] .${islandClass}{align-items:flex-start!important}' +` +
  `'html[data-wispr-compact-status="1"] .${rootClass}[data-bar-position="bottom"] .${notificationClass}{top:32px!important;bottom:auto!important}' +` +
  `'html[data-wispr-compact-status="1"] .${rootClass}[data-bar-position="bottom"] .${indicatorClass}{top:0!important;bottom:auto!important}' +` +
  `'html[data-wispr-compact-status="1"] .${rootClass}[data-bar-position="bottom"] .${reminderClass}{inset:14px auto auto 50%!important;transform:translateX(-50%)!important}';` +
  `document.head.appendChild(e);let t="hidden",n="";const r=new Set,o=()=>{` +
  `const e=r.size?"full":t;if(e===n)return;n=e;` +
  `document.documentElement.dataset.wisprStatusMode=e;` +
  `window.electron.ipc.send("wispr-flow:status-mode",e)};` +
  `window.__wisprFlowSetStatusMode=e=>{` +
  `if(!["hidden","compact","full"].includes(e))throw new Error("invalid Wispr status mode");` +
  `t=e,o()};window.__wisprFlowSetExpanded=(e,t)=>{` +
  `if("string"!=typeof e||!e)throw new Error("invalid Wispr expanded surface");` +
  `t?r.add(e):r.delete(e),o()}})();`;
renderer = rendererPrefix + renderer;

const placementNeedle =
  'function Un(e,t="top"){return"left"===e?"right":"right"===e?"left":t}';
const placementPatch =
  'function Un(e,t="top"){return"bottom"}';
renderer = replaceExact(
  renderer,
  placementNeedle,
  placementPatch,
  "top status tooltip placement",
);

const modeExpression =
  '[lt.HIDDEN,lt.RESTING].includes($)?"hidden":' +
  '[lt.ACTIVE_PTT,lt.ACTIVE_POPO,lt.PROCESSING,lt.INITIALIZING,lt.ERROR].includes($)' +
  '?"compact":"full"';
const effectNeedle = "),(0,b.useEffect)(()=>{we&&S(lt.RESTING)},[we]),";
const effectPatch =
  `),(0,b.useEffect)(()=>{window.__wisprFlowSetStatusMode?.(${modeExpression})},[$]),` +
  "(0,b.useEffect)(()=>{we&&S(lt.RESTING)},[we]),";
renderer = replaceExact(renderer, effectNeedle, effectPatch, "status mode effect");

const surfaceNeedle =
  'j="returning"===k;return(0,b.useEffect)(()=>{t&&';
const surfacePatch =
  'j="returning"===k;return(0,b.useEffect)(()=>{' +
  'window.__wisprFlowSetExpanded?.("surface",i||r||d||p||y)' +
  '},[i,r,d,p,y]),(0,b.useEffect)(()=>{t&&';
renderer = replaceExact(
  renderer,
  surfaceNeedle,
  surfacePatch,
  "expanded status surfaces",
);

renderer = horizontalRenderer(renderer);

fs.writeFileSync(mainFile, main);
fs.writeFileSync(rendererFile, renderer);
console.log("Patched Wispr Flow 1.6.7 for Omarchy compact status mode V15");
