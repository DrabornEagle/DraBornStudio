import assert from 'node:assert/strict';
import test from 'node:test';
import { build } from 'esbuild';
import { fileURLToPath } from 'node:url';

const f = { renderer: null, listeners: new Map(), blocked: false };
globalThis.__imageZoomFixture = f;
const bundle = await build({ entryPoints: ['src/components/GalleryDetailImage.tsx'], absWorkingDir: fileURLToPath(new URL('..', import.meta.url)),
  bundle: true, write: false, format: 'esm', platform: 'node', plugins: [{ name: 'image-zoom', setup(b) {
    b.onResolve({ filter: /^(react|react\/jsx-runtime|lucide-react)$|\/useGalleryImageSource$/ }, args => ({ path: args.path.split('/').at(-1), namespace: 'fixture' }));
    b.onLoad({ filter: /.*/, namespace: 'fixture' }, args => ({ contents: ({
      react: `const r=()=>globalThis.__imageZoomFixture.renderer;
        export const useState=value=>r().useState(value),useRef=value=>r().useRef(value),useEffect=(fn,deps)=>r().useEffect(fn,deps),useCallback=(fn,deps)=>r().useCallback(fn,deps);
        export default {createElement:(type,props,...children)=>({type,props:{...props,children}})};`,
      'jsx-runtime': `export const jsx=(type,props)=>({type,props}),jsxs=jsx;`,
      'lucide-react': `export const Loader2='Loader2',Minus='Minus',Plus='Plus';`,
      useGalleryImageSource: `export const useGalleryImageSource=src=>({url:src,loading:false,failed:false,onLoad(){},onError(){},retry(){}});`,
    })[args.path] }));
  } }],
});
const { DetailImage } = await import(`data:text/javascript;base64,${Buffer.from(bundle.outputFiles[0].text).toString('base64')}`);
function mount() {
  const slots=[]; let cursor=0;
  f.listeners.clear(); f.blocked=false;
  globalThis.window={addEventListener:(key,fn)=>f.listeners.set(key,fn),removeEventListener:(key,fn)=>{if(f.listeners.get(key)===fn)f.listeners.delete(key);}};
  globalThis.document={querySelector:()=>f.blocked ? {} : null};
  globalThis.ResizeObserver=class {observe(){} disconnect(){}};
  const image={naturalWidth:1600,offsetWidth:800,offsetHeight:600,complete:false};
  const stage={clientWidth:800,clientHeight:600,getBoundingClientRect:()=>({left:0,top:0,width:800,height:600}),addEventListener(){},removeEventListener(){}};
  const app={effects:[],
    useState(value){const i=cursor++;if(!(i in slots))slots[i]=typeof value==='function'?value():value;return[slots[i],value=>{slots[i]=typeof value==='function'?value(slots[i]):value;}];},
    useRef(value){const i=cursor++;return slots[i]||=( {current:value});},
    useCallback(fn,deps){const i=cursor++;const old=slots[i];if(!old||deps.some((d,j)=>d!==old.deps[j]))slots[i]={fn,deps};return slots[i].fn;},
    useEffect(fn,deps){const i=cursor++;const old=slots[i];if(!old||deps.some((d,j)=>d!==old.deps[j])){old?.cleanup?.();slots[i]={deps};app.effects.push(()=>{slots[i].cleanup=fn();});}},
    nodes(){const result=[];const visit=n=>{if(!n||typeof n!=='object')return;if(Array.isArray(n))return n.forEach(visit);result.push(n);visit(n.props?.children);};visit(app.tree);return result;},
    render(){cursor=0;f.renderer=app;app.tree=DetailImage({src:'synthetic.png',alt:'Synthetic test',className:'object-contain'});
      for(const n of app.nodes())if(n.props?.ref)n.props.ref.current=n.type==='img'?image:stage;
      for(const fn of app.effects.splice(0))fn();return app;},
    key(key,overrides={}){const event={key,target:{closest:()=>null},preventDefault(){this.prevented=true;},stopPropagation(){},...overrides};f.listeners.get('keydown')?.(event);app.render();return event;},
    button(label){return app.nodes().find(n=>n.type==='button'&&n.props['aria-label']===label);},
    zoom(){return app.tree.props['data-gallery-image-zoom'];},
    close(){for(const slot of slots)slot?.cleanup?.();}, image,
  };return app.render();
}

test('real viewer keys and buttons zoom between fit and 8×, reset pan, and remove listeners on close',()=>{
  const app=mount();
  assert.equal(app.zoom(),1); assert.equal(app.button('Zoom image out').props.disabled,true);
  assert.equal(app.key('+').prevented,true); assert.equal(app.zoom(),1.25);
  app.button('Zoom image in').props.onClick();app.render();assert.equal(app.zoom(),1.5625);
  app.key('-');assert.equal(app.zoom(),1.25);
  for(let i=0;i<30;i++)app.key('=');
  assert.equal(app.zoom(),8);assert.equal(app.button('Zoom image in').props.disabled,true);
  app.key('0');assert.equal(app.zoom(),1);
  app.button('Reset image zoom').props.onClick();app.render();
  assert.match(app.nodes().find(n=>n.type==='img').props.style.transform,/translate\(0px, 0px\) scale\(1\)/);
  app.close();assert.equal(f.listeners.has('keydown'),false);
});

test('zoom shortcuts leave typing, composition, browser zoom, masks, menus and navigation untouched',()=>{
  const app=mount();
  for(const flag of ['ctrlKey','metaKey','altKey','isComposing','repeat','defaultPrevented'])assert.equal(app.key('+',{[flag]:true}).prevented,undefined,flag);
  assert.equal(app.key('+',{target:{closest:()=>({})}}).prevented,undefined,'text and slider controls retain their keys');
  f.blocked=true;assert.equal(app.key('+').prevented,undefined,'nested dialogs and menus retain their keys');f.blocked=false;
  for(const key of ['ArrowLeft','ArrowRight','Escape','b','Delete'])assert.equal(app.key(key).prevented,undefined,key);
  app.image.naturalWidth=0;assert.equal(app.key('+').prevented,undefined,'never claim a zoom when no image has decoded');
  assert.equal(app.zoom(),1);app.close();
});
