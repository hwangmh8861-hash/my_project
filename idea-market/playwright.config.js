import {defineConfig} from '@playwright/test';
export default defineConfig({
 testDir:'./tests/e2e',timeout:90000,workers:1,fullyParallel:false,
 use:{baseURL:'http://127.0.0.1:4173',headless:true,launchOptions:process.env.IDEA_TEST_CHROMIUM_PATH?{executablePath:process.env.IDEA_TEST_CHROMIUM_PATH,args:['--no-sandbox','--disable-dev-shm-usage','--disable-gpu']}:{}},
 webServer:{command:'npm run dev -- --host 127.0.0.1 --port 4173',url:'http://127.0.0.1:4173',reuseExistingServer:false},
 reporter:[['list'],['json',{outputFile:'test-results/e2e-results.json'}]]
});
