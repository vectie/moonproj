import {readFileSync} from 'node:fs';
import vm from 'node:vm';
const root = new URL('../../',import.meta.url);
export const read = p => readFileSync(new URL(p,root),'utf8');
const extern = read('frontend/opc/project_plan_review.mbt');
const body = extern.split('\n').filter(s=>s.startsWith('  #| ')).map(s=>s.slice(5)).join('\n');
const render = vm.runInNewContext('('+body+')');
export const source = read('docs/examples/delivery-plan-template.json');
export class Element {
  constructor(tag){this.tag=tag;this.children=[];this.events={};this.value='';this.textContent='';}
  appendChild(n){this.children.push(n);return n;}
  replaceChildren(...items){this.children=[...items];}
  addEventListener(k,f){(this.events[k] ||= []).push(f);}
  async fire(k,event={}){for(const f of this.events[k] || []) await f({target:this,...event});}
  click(){this.clicked=true;}
}
export function open(input=source) { return openHTML(render(input)); }
export function openHTML(html) {
  const ids=Object.fromEntries([...html.matchAll(/\bid="([^"]+)"/g)].map(m=>[m[1],new Element(m[1])]));
  ids['inbox-filter'].value='all';
  const created=[], downloads=[], window=new Element('window'); window.confirm=()=>true;
  const document={getElementById:id=>ids[id],createElement:tag=>{const e=new Element(tag);created.push(e);return e;}};
  const revoked=[];
  const sandbox={document,window,Blob,URL:{createObjectURL:blob=>{downloads.push(blob);return 'blob:review';},revokeObjectURL:u=>revoked.push(u)},setTimeout:f=>f()};
  vm.runInNewContext(html.match(/<script>([\s\S]*)<\/script>/)[1],sandbox);
  const walk=e=>[e,...e.children.flatMap(walk)];
  return {html,ids,created,downloads,window,revoked,
    async save(){await ids.save.fire('click');return JSON.parse(await downloads.at(-1).text());},
    async load(packet){ids.load.files=[new Blob([typeof packet==='string'?packet:JSON.stringify(packet)])]; await ids.load.fire('change');},
    async importReviews(...packets){ids['inbox-import'].files=packets.map((packet,i)=>Object.assign(new Blob([typeof packet==='string'?packet:JSON.stringify(packet)]),{name:'review-'+(i+1)+'.json'}));await ids['inbox-import'].fire('change');},
    async saveInbox(){const count=downloads.length;await ids['inbox-save'].fire('click');return count===downloads.length ? undefined : JSON.parse(await downloads.at(-1).text());},
    async loadInbox(packet){ids['inbox-load'].files=[new Blob([typeof packet==='string'?packet:JSON.stringify(packet)])];await ids['inbox-load'].fire('change');},
    async filter(value){ids['inbox-filter'].value=value;await ids['inbox-filter'].fire('change');},
    inboxElements:()=>walk(ids.inbox),
    control:id=>walk(ids.inbox).find(e=>e.id===id),
    states:created.filter(e=>e.tag==='select'),notes:created.filter(e=>e.tag==='textarea')};
}
export async function returnedReview(label,changes={}) {
  const app=open();app.ids.reviewer.value=label;
  for(const [index,value] of Object.entries(changes)){app.states[index].value=value.state;app.notes[index].value=value.note;}
  return app.save();
}
