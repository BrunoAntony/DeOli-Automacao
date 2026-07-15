// ============================================================
//  /api/dev-users — lista, cria e remove usuários desenvolvedores
//  (is_admin=true, empresa_id=null — acesso a todas as empresas)
// ------------------------------------------------------------
//  Só quem já é desenvolvedor (a própria linha em app_users tem
//  is_admin=true) pode gerenciar outros desenvolvedores — mesmo
//  que ele tenha trocado de empresa ativa na sessão (a claim
//  empresa_id do JWT não conta aqui, só a linha real do usuário).
//
//  GET    → lista { id, username, createdAt }
//  POST   → cria { username } — nasce com senha padrão "123",
//           is_admin=true, role='admin', empresa_id=null
//  DELETE → remove ?id=<userId> (não deixa apagar a si mesmo nem
//           o último desenvolvedor restante)
//  Header: Authorization: Bearer <access_token da sessão>
// ============================================================
const crypto = require('crypto');
const jwt = require('./_jwt');

const SUPA_URL = 'https://kvxsqbfwakfqdxzilvix.supabase.co';
const SUPA_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imt2eHNxYmZ3YWtmcWR4emlsdml4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODExNzQ0MjYsImV4cCI6MjA5Njc1MDQyNn0.PQads0GXVlNqr11K5co65XbWYoZJWu4V-4h4AR5DdpU';
const DEFAULT_PASSWORD = '123';

async function authDev(req, serviceKey, jwtSecret) {
  const authHeader = req.headers.authorization || req.headers.Authorization || '';
  const token = String(authHeader).replace(/^Bearer\s+/i, '');
  const payload = jwt.verify(token, jwtSecret);
  if (!payload || !payload.sub) return null;

  const r = await fetch(SUPA_URL + '/rest/v1/app_users?id=eq.' + encodeURIComponent(payload.sub) + '&select=id,username,is_admin', {
    headers: { apikey: SUPA_ANON_KEY, Authorization: 'Bearer ' + serviceKey },
  });
  if (!r.ok) return null;
  const rows = await r.json();
  const caller = rows && rows[0];
  if (!caller || !caller.is_admin) return null;
  return { caller };
}

module.exports = async (req, res) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, DELETE, OPTIONS');
  if (req.method === 'OPTIONS') return res.status(204).end();

  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  const jwtSecret = process.env.SUPABASE_JWT_SECRET;
  if (!serviceKey || !jwtSecret) {
    return res.status(500).json({ error: 'Não configurado no servidor (SUPABASE_SERVICE_ROLE_KEY / SUPABASE_JWT_SECRET ausentes).' });
  }

  try {
    const ctx = await authDev(req, serviceKey, jwtSecret);
    if (!ctx) return res.status(403).json({ error: 'Só desenvolvedores podem gerenciar outros desenvolvedores' });

    if (req.method === 'GET') {
      const r = await fetch(SUPA_URL + '/rest/v1/app_users?empresa_id=is.null&select=id,username,created_at&order=created_at.asc', {
        headers: { apikey: SUPA_ANON_KEY, Authorization: 'Bearer ' + serviceKey },
      });
      if (!r.ok) throw new Error('Falha ao listar desenvolvedores: ' + r.status);
      const rows = await r.json();
      const users = (rows || []).map((u) => ({ id: u.id, username: u.username, createdAt: u.created_at }));
      return res.status(200).json({ ok: true, users });
    }

    if (req.method === 'POST') {
      const body = typeof req.body === 'string' ? JSON.parse(req.body || '{}') : (req.body || {});
      const username = String(body.username || '').trim().toLowerCase();
      if (!username) return res.status(400).json({ error: 'Informe o usuário' });

      const existing = await fetch(SUPA_URL + '/rest/v1/app_users?username=eq.' + encodeURIComponent(username) + '&select=id', {
        headers: { apikey: SUPA_ANON_KEY, Authorization: 'Bearer ' + serviceKey },
      });
      const existingRows = existing.ok ? await existing.json() : [];
      if (existingRows && existingRows[0]) return res.status(409).json({ error: 'Já existe um usuário com esse nome' });

      // nasce com a senha padrão "123" — o login força a troca antes de liberar o resto do app
      const salt = crypto.randomBytes(16).toString('hex');
      const hash = crypto.scryptSync(DEFAULT_PASSWORD, salt, 64).toString('hex');
      const ins = await fetch(SUPA_URL + '/rest/v1/app_users', {
        method: 'POST',
        headers: { apikey: SUPA_ANON_KEY, Authorization: 'Bearer ' + serviceKey, 'Content-Type': 'application/json', Prefer: 'return=representation' },
        body: JSON.stringify({ username, password_hash: hash, password_salt: salt, empresa_id: null, role: 'admin', is_admin: true, must_change_password: true }),
      });
      if (!ins.ok) throw new Error('Falha ao criar desenvolvedor: ' + ins.status);
      const created = await ins.json();
      const u = created && created[0];
      return res.status(200).json({ ok: true, defaultPassword: DEFAULT_PASSWORD, user: u ? { id: u.id, username: u.username, createdAt: u.created_at } : null });
    }

    if (req.method === 'DELETE') {
      let userId = (req.query && req.query.id) || '';
      if (!userId && req.url) {
        try { userId = new URL(req.url, 'http://x').searchParams.get('id') || ''; } catch (e) {}
      }
      if (!userId) return res.status(400).json({ error: 'Informe o id do usuário' });
      if (userId === ctx.caller.id) return res.status(400).json({ error: 'Você não pode remover seu próprio usuário' });

      const rt = await fetch(SUPA_URL + '/rest/v1/app_users?id=eq.' + encodeURIComponent(userId) + '&empresa_id=is.null&select=id', {
        headers: { apikey: SUPA_ANON_KEY, Authorization: 'Bearer ' + serviceKey },
      });
      if (!rt.ok) throw new Error('Falha ao consultar usuário: ' + rt.status);
      const targetRows = await rt.json();
      if (!targetRows || !targetRows[0]) return res.status(404).json({ error: 'Desenvolvedor não encontrado' });

      const ra = await fetch(SUPA_URL + '/rest/v1/app_users?empresa_id=is.null&select=id', {
        headers: { apikey: SUPA_ANON_KEY, Authorization: 'Bearer ' + serviceKey },
      });
      const devs = ra.ok ? await ra.json() : [];
      if ((devs || []).length <= 1) return res.status(400).json({ error: 'Não é possível remover o último desenvolvedor' });

      const del = await fetch(SUPA_URL + '/rest/v1/app_users?id=eq.' + encodeURIComponent(userId), {
        method: 'DELETE',
        headers: { apikey: SUPA_ANON_KEY, Authorization: 'Bearer ' + serviceKey, Prefer: 'return=minimal' },
      });
      if (!del.ok) throw new Error('Falha ao remover desenvolvedor: ' + del.status);
      return res.status(200).json({ ok: true });
    }

    return res.status(405).json({ error: 'method not allowed' });
  } catch (e) {
    console.error('[dev-users] erro:', e);
    return res.status(500).json({ error: String((e && e.message) || e) });
  }
};
