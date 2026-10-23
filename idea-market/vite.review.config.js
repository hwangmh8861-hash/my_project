import {defineConfig} from 'vite';
import {fileURLToPath} from 'node:url';
export default defineConfig({root:'review',publicDir:'../public',resolve:{alias:[{find:'@supabase/supabase-js',replacement:fileURLToPath(new URL('./review/sdk.js',import.meta.url))},{find:/^\.\/config\.js$/,replacement:fileURLToPath(new URL('./review/sdk.js',import.meta.url))}]},build:{outDir:'../dist-review',emptyOutDir:true,target:['safari15','chrome100']}});
