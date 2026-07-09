// Armazenamento da configuração do agente, compartilhado entre as funções serverless.
// Cada arquivo em api/ roda como uma função isolada na Vercel — /tmp NÃO é
// compartilhado entre elas. Por isso a config é persistida no Supabase (mesmo
// projeto que o APP usa), na tabela app_config, linha id='webhook_agent'.
const SUPA_URL = 'https://kvxsqbfwakfqdxzilvix.supabase.co';
const SUPA_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imt2eHNxYmZ3YWtmcWR4emlsdml4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODExNzQ0MjYsImV4cCI6MjA5Njc1MDQyNn0.PQads0GXVlNqr11K5co65XbWYoZJWu4V-4h4AR5DdpU';
const ROW_ID = 'webhook_agent';

function headers(extra) {
  return Object.assign({ apikey: SUPA_KEY, Authorization: 'Bearer ' + SUPA_KEY, 'Content-Type': 'application/json' }, extra || {});
}

async function readConfig() {
  try {
    const r = await fetch(SUPA_URL + '/rest/v1/app_config?id=eq.' + ROW_ID + '&select=data', { headers: headers() });
    if (!r.ok) return null;
    const rows = await r.json();
    return (rows && rows[0] && rows[0].data) || null;
  } catch (e) { return null; }
}

async function writeConfig(cfg) {
  const payload = { id: ROW_ID, data: cfg, updated_at: new Date().toISOString() };
  try {
    const r = await fetch(SUPA_URL + '/rest/v1/app_config', {
      method: 'POST',
      headers: headers({ Prefer: 'return=minimal' }),
      body: JSON.stringify(payload),
    });
    if (r.ok) return true;
    // já existe a linha (PK duplicada) — atualiza em vez de inserir
    const r2 = await fetch(SUPA_URL + '/rest/v1/app_config?id=eq.' + ROW_ID, {
      method: 'PATCH',
      headers: headers({ Prefer: 'return=minimal' }),
      body: JSON.stringify({ data: cfg, updated_at: payload.updated_at }),
    });
    return r2.ok;
  } catch (e) { return false; }
}

module.exports = { readConfig, writeConfig };
