// ============================================================
//  /api/gemini — proxy para a API do Gemini
// ------------------------------------------------------------
//  O app (navegador) nunca guarda nem envia a chave do Gemini —
//  ela fica só aqui no servidor (variável de ambiente
//  GEMINI_API_KEY na Vercel). O app chama este endpoint para
//  testar o agente e classificar conversas (funil/agendamento);
//  as respostas automáticas 24/7 continuam vindo do /api/webhook.
//
//  POST body: { system, userMsg, model, temperature }
// ============================================================
module.exports = async (req, res) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'method not allowed' });

  const key = process.env.GEMINI_API_KEY;
  if (!key) return res.status(500).json({ error: 'GEMINI_API_KEY não configurada no servidor (defina na Vercel).' });

  try {
    const body = typeof req.body === 'string' ? JSON.parse(req.body || '{}') : (req.body || {});
    const system = String(body.system || '');
    const userMsg = String(body.userMsg || '');
    const model = body.model || 'gemini-flash-latest';
    const temperature = (body.temperature != null ? Number(body.temperature) : 0.5);

    const url = 'https://generativelanguage.googleapis.com/v1beta/models/' + encodeURIComponent(model) + ':generateContent?key=' + encodeURIComponent(key);
    const payload = {
      systemInstruction: { parts: [{ text: system }] },
      contents: [{ role: 'user', parts: [{ text: userMsg }] }],
      generationConfig: { temperature },
    };
    const r = await fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload) });
    const data = await r.json().catch(() => ({}));
    if (!r.ok) {
      const msg = (data.error && data.error.message) || ('Gemini ' + r.status);
      return res.status(r.status).json({ error: msg });
    }
    const parts = data.candidates && data.candidates[0] && data.candidates[0].content && data.candidates[0].content.parts || [];
    const text = parts.map((p) => p.text || '').join('').trim();
    return res.status(200).json({ text });
  } catch (e) {
    return res.status(500).json({ error: String((e && e.message) || e) });
  }
};
