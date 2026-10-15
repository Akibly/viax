// Run with the bundled @oai/artifact-tool runtime described in the presentation skill.
// VIA_X_RUNTIME_MODULES should point to a directory containing @oai/artifact-tool.
import fs from 'node:fs/promises';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
const root=path.resolve(import.meta.dirname,'..');
const modules=process.env.VIA_X_RUNTIME_MODULES;
if(!modules) throw new Error('Set VIA_X_RUNTIME_MODULES to the presentation runtime node_modules directory.');
const {Presentation,PresentationFile}=await import(pathToFileURL(path.join(modules,'@oai/artifact-tool/dist/artifact_tool.mjs')).href);
const media=path.join(root,'docs/media');
const work=path.join(root,'outputs/viax-deck-build');
await fs.mkdir(work,{recursive:true});
const deck=Presentation.create({slideSize:{width:1280,height:720}});
const paper='#F7F4EC', ink='#192033', blue='#3157D5', quiet='#5E6676';
function slide(bg=paper){const s=deck.slides.add();s.background.fill=bg;return s;}
function text(s,t,x,y,w,h,size=28,color=ink,bold=false){const a=s.shapes.add({geometry:'textbox',position:{left:x,top:y,width:w,height:h},fill:'none',line:{fill:'none',width:0}});a.text=t;a.text.style={typeface:'Arial',fontSize:size,color,bold};return a;}
async function pic(s,name,x,y,w,h,fit='contain'){s.images.add({blob:new Uint8Array(await fs.readFile(path.join(media,name))),contentType:'image/png',alt:name,fit,position:{left:x,top:y,width:w,height:h}});}
function notes(s,t){s.speakerNotes.text=t;}
let s=slide();
await pic(s,'study-cover.png',0,0,1280,720,'cover');
text(s,'ViaX',68,148,500,116,92,blue,true);
text(s,'Practice with\nyour own notes',72,287,505,140,48,ink,true);
text(s,'An open-source AI study companion',74,472,480,70,25,quiet);
notes(s,'ViaX product overview. Source: repository README.md and application source. The cover is AI-generated photographic artwork, not an app screenshot or real event.');
s=slide();
text(s,'Your notes become a study base',64,48,1150,80,48,ink,true);
const rows=[['Upload','Add a document under a subject.'],['Understand','Extract passages and supported concepts.'],['Practice','Try viva questions, flashcards, or quizzes.'],['Review','Return to gaps using revision and mastery.']];
rows.forEach(([h,b],i)=>{text(s,h,66,174+i*114,220,44,31,blue,true);text(s,b,66,218+i*114,525,60,24,quiet);});
await pic(s,'onboarding.png',636,167,580,390);
text(s,'Actual app onboarding, dark mode',665,575,520,40,19,quiet);
notes(s,'Sources: mobile/lib/screens/subjects/subject_detail_screen.dart, supabase/functions/ingest/index.ts, README.md. Screenshot captured from https://viax-iota.vercel.app on 16 October 2026. AI extraction requires selectable document text and a configured provider.');
s=slide();
text(s,'A dedicated AI conversation space',64,45,1150,75,48,ink,true);
text(s,'General questions or context from a selected subject',66,125,1140,50,26,quiet);
await pic(s,'chat-desktop.png',204,204,872,454);
notes(s,'Actual app capture on 15 October 2026 in light mode. Source: mobile/lib/screens/chat/chat_screen.dart and supabase/functions/chat/index.ts. Empty state shown. General chat does not provide live web search.');
s=slide();
text(s,'A conversation you can carry',64,62,720,125,48,ink,true);
text(s,'General knowledge',66,244,620,52,33,blue,true);
text(s,'Explore an idea or ask for a step-by-step explanation.',66,302,590,95,27,quiet);
text(s,'Your study notes',66,431,620,52,33,blue,true);
text(s,'Choose a subject to bring saved material into the conversation.',66,489,590,105,27,quiet);
await pic(s,'chat-mobile.png',824,45,380,620);
notes(s,'Actual mobile viewport capture on 15 October 2026. Conversation context is fixed after the first message. Retrieval uses saved source passages. Check important facts and source passages because AI answers may be wrong.');
s=slide();
text(s,'The technology behind ViaX',64,50,1150,80,48,ink,true);
const stack=[['Flutter','Responsive application for web and mobile.'],['Supabase','Authentication, private document storage, database and Edge Functions.'],['NVIDIA','Chat generation and 1024-dimension document and query embeddings.'],['Source grounding','Passages connect extracted concepts to the uploaded material.']];
stack.forEach(([a,b],i)=>{text(s,a,66,185+i*113,270,52,31,blue,true);text(s,b,368,185+i*113,830,82,27,ink);});
notes(s,'Sources: mobile/pubspec.yaml; supabase/functions/_shared/llm.ts; supabase/functions/ingest/index.ts; supabase/functions/examine/index.ts. NVIDIA embedding model: nvidia/llama-nemotron-embed-vl-1b-v2 with dimensions=1024. API keys remain in server-side secrets. The separate Python service is optional for the deployed Flutter/Supabase path.');
s=slide('#192033');
text(s,'Open source.\nReady to explore.',64,82,1100,180,68,'#FFFFFF',true);
text(s,'MIT-licensed source, database migrations,\nand setup instructions are on GitHub.',68,300,1080,110,32,'#DCE3FF');
text(s,'github.com/Akibly/viax',68,465,1100,65,39,'#AFC0FF',true);
text(s,'Try the app: viax-iota.vercel.app',68,566,1100,55,27,'#FFFFFF');
notes(s,'Source: LICENSE and README.md at https://github.com/Akibly/viax. Public deployment: https://viax-iota.vercel.app. Self-hosting needs a Supabase project and provider credentials. Third-party software and services retain their own licenses and terms.');
for(let i=0;i<deck.slides.items.length;i++){
 const blob=await deck.export({slide:deck.slides.items[i],format:'png',scale:1});
 await fs.writeFile(path.join(media,`slide-${String(i+1).padStart(2,'0')}.png`),new Uint8Array(await blob.arrayBuffer()));
}
await fs.copyFile(path.join(media,'slide-01.png'),path.join(media,'cover.png'));
await (await PresentationFile.exportPptx(deck)).save(path.join(work,'candidate.pptx'));
console.log('Rendered six slides and exported candidate.pptx.');
