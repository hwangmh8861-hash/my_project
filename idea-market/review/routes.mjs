import {mkdir,readFile,writeFile} from 'node:fs/promises';
const index=await readFile(new URL('../dist-review/index.html',import.meta.url));
for(const route of ['admin','s','student','board']){const directory=new URL('../dist-review/'+route+'/',import.meta.url);await mkdir(directory,{recursive:true});await writeFile(new URL('index.html',directory),index)}
await writeFile(new URL('../dist-review/mobile.html',import.meta.url),await readFile(new URL('./mobile.html',import.meta.url)));
