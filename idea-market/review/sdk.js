// Review build only. No remote SDK, WebSocket or production credentials.
export const SUPABASE_URL='https://review.invalid';
export const SUPABASE_KEY='review-only';
const callbacks=new Set();
export function notify(){for(const fn of callbacks)fn()}
export function createClient(){return {channel:()=>({on(_kind,_filter,fn){callbacks.add(fn);return this},subscribe(fn){queueMicrotask(()=>fn('SUBSCRIBED'));return this}})}}
