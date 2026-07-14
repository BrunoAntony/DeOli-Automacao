// ============================================================
//  /api/users — lista e cria usuários (funcionários) da empresa
// ------------------------------------------------------------
//  Só quem é admin (da própria empresa) ou admin cross-empresa
//  (is_admin) pode listar/criar. A empresa considerada é a que
//  está ativa na sessão (claim empresa_id do JWT, se houver —
//  cobre o caso do admin cross-empresa vendo/criando pra uma
//  empresa que não é a "dona" da conta dele).
//
//  GET  → lista { id, username, role, createdAt }
//  POST → cria { username, password, role } (role: 'admin' | 'funcionario')
//  Header: Authorization: Bearer <access_token da sessão>
// ============================================================
const crypto = require('crypto');
const jwt = require('./_jwt');

const SUPA_URL = 'https://kvxsqbfwakfqdxzilvix.supabase.co';
const SUPA_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imt2eHNxYmZ3YWtmcWR4emlsdml4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODExNzQ0MjYsImV4cCI6MjA5Njc1MDQyNn0.PQads0GXVlNqr11K5co65XbWYoZJWu4V-4h4AR5DdpU';
const DEFAULT_PASSWORD = '123';

async function auth(req, serviceKey, jwtSecret) {
  const authHeader = req.headers.authorization || req.headers.Authorization || '';
  const token = String(authHeader).replace(/^Bearer\s+/i, '');
  const payload = jwt.verify(token, jwtSecret);
  if (!payload || !payload.sub) return null;

  const r = await fetch(SUPA_URL + '/rest/v1/app_users?id=eq.' + encodeURIComponent(payload.sub) + '&select=id,username,role,is_admin,empresa_id', {
    headers: { apikey: SUPA_ANON_KEY, Authorization: 'Bearer ' + serviceKey },
  });
  if (!r.ok) return null;
  const rows = await r.json();
  const caller = rows && rows[0];
  if (!caller) return null;

  // empresa ativa: a claim do JWT (troca de empresa) tem prioridade sobre a
  // empresa "dona" da conta — cobre o admin cross-empresa vendo outra empresa
  const empresaId = payload.empresa_id || caller.empresa_id;
  const isAuthorized = !!caller.is_admin || (caller.role === 'admin' && caller.empresa_id === empresaId);
  return { caller, empresaId, isAuthorized };
}

module.exports = async (req, res) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  if (req.method === 'OPTIONS') return res.status(204).end();

  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  const jwtSecret = process.env.SUPABASE_JWT_SECRET;
  if (!serviceKey || !jwtSecret) {
    return res.status(500).json({ error: 'Não configurado no servidor (SUPABASE_SERVICE_ROLE_KEY / SUPABASE_JWT_SECRET ausentes).' });
  }

  try {
    const ctx = await auth(req, serviceKey, jwtSecret);
    if (!ctx) return res.status(401).json({ error: 'Sessão inválida ou expirada' });
    if (!ctx.isAuthorized) return res.status(403).json({ error: 'Só administradores podem gerenciar usuários' });

    if (req.method === 'GET') {
      const r = await fetch(SUPA_URL + '/rest/v1/app_users?empresa_id=eq.' + encodeURIComponent(ctx.empresaId) + '&select=id,username,role,created_at&order=created_at.asc', {
        headers: { apikey: SUPA_ANON_KEY, Authorization: 'Bearer ' + serviceKey },
      });
      if (!r.ok) throw new Error('Falha ao listar usuários: ' + r.status);
      const rows = await r.json();
      const users = (rows || []).map((u) => ({ id: u.id, username: u.username, role: u.role || 'admin', createdAt: u.created_at }));
      return res.status(200).json({ ok: true, users });
    }

    if (req.method === 'POST') {
      const body = typeof req.body === 'string' ? JSON.parse(req.body || '{}') : (req.body || {});
      const username = String(body.username || '').trim().toLowerCase();
      const role = body.role === 'admin' ? 'admin' : 'funcionario';
      if (!username) return res.status(400).json({ error: 'Informe o usuário' });

      const existing = await fetch(SUPA_URL + '/rest/v1/app_users?username=eq.' + encodeURIComponent(username) + '&select=id', {
        headers: { apikey: SUPA_ANON_KEY, Authorization: 'Bearer ' + serviceKey },
      });
      const existingRows = existing.ok ? await existing.json() : [];
      if (existingRows && existingRows[0]) return res.status(409).json({ error: 'Já existe um usuário com esse nome' });

      // todo usuário novo nasce com a senha padrão "123" — o login força a
      // troca antes de liberar o resto do app (must_change_password)
      const salt = crypto.randomBytes(16).toString('hex');
      const hash = crypto.scryptSync(DEFAULT_PASSWORD, salt, 64).toString('hex');
      const ins = await fetch(SUPA_URL + '/rest/v1/app_users', {
        method: 'POST',
        headers: { apikey: SUPA_ANON_KEY, Authorization: 'Bearer ' + serviceKey, 'Content-Type': 'application/json', Prefer: 'return=representation' },
        body: JSON.stringify({ username, password_hash: hash, password_salt: salt, empresa_id: ctx.empresaId, role, is_admin: false, must_change_password: true }),
      });
      if (!ins.ok) throw new Error('Falha ao criar usuário: ' + ins.status);
      const created = await ins.json();
      const u = created && created[0];
      return res.status(200).json({ ok: true, defaultPassword: DEFAULT_PASSWORD, user: u ? { id: u.id, username: u.username, role: u.role, createdAt: u.created_at } : null });
    }

    return res.status(405).json({ error: 'method not allowed' });
  } catch (e) {
    console.error('[users] erro:', e);
    return res.status(500).json({ error: String((e && e.message) || e) });
  }
};
