import { createClient } from 'npm:@supabase/supabase-js@2.118.0';
import { createHandler } from './edge-handler.js';
const db=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,{auth:{persistSession:false}});
Deno.serve(createHandler((args: Record<string, unknown>)=>db.rpc('idea_market_rpc',args)));
