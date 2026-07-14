// ============================================================
//  /api/config — recebe a configuração do agente enviada pelo APP
// ------------------------------------------------------------
//  O editor de agente do app faz POST aqui ao salvar. A config
//  (prompt, modelo, criatividade, boas-vindas) passa a ser usada
//  pelo /api/webhook, sem precisar editar variáveis na Vercel.
//
//  Cada empresa tem sua própria config — o app manda ?canal=<webhook_key>
//  (o mesmo identificador da URL do webhook daquela empresa) pra saber de
//  qual empresa é essa configuração. Sem esse parâmetro, cai na primeira
//  empresa cadastrada (compatibilidade com configs antigas).
//
//  POST body: { prompt, model, temperature, welcome, enabled, notifyNumber, respostaDelay }
//  A chave do Gemini não vem mais do app — fica só na variável de ambiente
//  GEMINI_API_KEY da Vercel (um único lugar para todos os agentes).
//  GET  → retorna a config atual (sem expor a chave)
// ============================================================
const { readConfig, writeConfig } = require('./_configStore');
const { resolveContext } = require('./_empresa');

module.exports = async (req, res) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  res.setHeader('Access-Control-Allow-Methods', 'POST, GET, OPTIONS');
  if (req.method === 'OPTIONS') return res.status(204).end();

  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  let canalKey = (req.query && req.query.canal) || '';
  if (!canalKey && req.url) {
    try { canalKey = new URL(req.url, 'http://x').searchParams.get('canal') || ''; } catch (e) {}
  }
  const ctx = await resolveContext(canalKey, serviceKey);
  const empresaId = ctx.empresaId;

  if (req.method === 'GET') {
    if (!empresaId) return res.status(200).json({ ok: true, configured: false, config: null });
    const c = await readConfig(empresaId);
    return res.status(200).json({ ok: true, configured: !!c, config: c ? { model: c.model, temperature: c.temperature, enabled: c.enabled, hasKey: !!c.geminiKey, hasDriveKey: !!c.driveApiKey, notifyNumber: c.notifyNumber || '', respostaDelay: (c.respostaDelay != null ? c.respostaDelay : 3), promptLen: (c.prompt || '').length } : null });
  }
  if (req.method !== 'POST') return res.status(405).json({ error: 'method not allowed' });

  try {
    if (!empresaId) return res.status(400).json({ error: 'Não foi possível identificar a empresa (canal desconhecido e nenhuma empresa cadastrada).' });
    const body = typeof req.body === 'string' ? JSON.parse(req.body || '{}') : (req.body || {});
    const cfg = {
      prompt: body.prompt || '',
      geminiKey: body.geminiKey || '',
      model: body.model || 'gemini-flash-latest',
      temperature: (body.temperature != null ? Number(body.temperature) : 0.5),
      welcome: body.welcome || '',
      enabled: body.enabled !== false,
      driveApiKey: body.driveApiKey || '',
      notifyNumber: (body.notifyNumber || '').replace(/\D/g, ''),
      respostaDelay: Math.min(10, Math.max(2, Number(body.respostaDelay) || 3)),
      updatedAt: Date.now(),
    };
    const okWrite = await writeConfig(empresaId, cfg);
    return res.status(200).json({ ok: true, stored: okWrite });
  } catch (e) {
    return res.status(500).json({ error: String((e && e.message) || e) });
  }
};
