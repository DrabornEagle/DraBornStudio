import type { VercelRequest, VercelResponse } from '@vercel/node';
import { applyCors, requireUser } from './_lib/auth.js';

const YOUTUBE_API_BASE = 'https://www.googleapis.com/youtube/v3';

const ALLOWED_ENDPOINTS = new Set(['videos', 'channels', 'playlistItems', 'search']);

interface YoutubeProxyRequest {
  endpoint: string;
  params?: Record<string, string>;
}

export default async function handler(req: VercelRequest, res: VercelResponse) {
  applyCors(res);
  if (req.method === 'OPTIONS') return res.status(200).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'Method not allowed' });

  const user = await requireUser(req, res);
  if (!user) return;

  const apiKey = process.env.YOUTUBE_API_KEY;
  if (!apiKey) {
    return res.status(500).json({ error: 'YOUTUBE_API_KEY not configured on server' });
  }

  let body: YoutubeProxyRequest;
  try {
    body =
      typeof req.body === 'string'
        ? (JSON.parse(req.body) as YoutubeProxyRequest)
        : (req.body as YoutubeProxyRequest);
  } catch {
    return res.status(400).json({ error: 'Invalid JSON body' });
  }

  const { endpoint, params } = body || ({} as YoutubeProxyRequest);
  if (!endpoint || !ALLOWED_ENDPOINTS.has(endpoint)) {
    return res.status(400).json({ error: `Unsupported endpoint: ${endpoint}` });
  }

  try {
    const url = new URL(`${YOUTUBE_API_BASE}/${endpoint}`);
    url.searchParams.set('key', apiKey);
    if (params && typeof params === 'object') {
      for (const [k, v] of Object.entries(params)) {
        if (typeof v === 'string') url.searchParams.set(k, v);
      }
    }

    const response = await fetch(url.toString());
    const text = await response.text();
    let data: any;
    try {
      data = text ? JSON.parse(text) : {};
    } catch {
      return res
        .status(502)
        .json({ error: `YouTube returned non-JSON response (${response.status})` });
    }

    if (!response.ok || data?.error) {
      const message = data?.error?.message || `YouTube API error (${response.status})`;
      return res.status(response.status || 502).json({ error: message });
    }

    return res.status(200).json(data);
  } catch (error: any) {
    console.error('YouTube proxy error:', error?.message || error);
    return res.status(500).json({ error: error?.message || 'YouTube request failed' });
  }
}
