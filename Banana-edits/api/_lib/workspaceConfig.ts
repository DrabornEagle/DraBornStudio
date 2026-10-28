import { validateCloudPublicConfig } from '../../src/lib/config/publicConfig.js';
export const getCloudWorkspaceConfig = (env = process.env) => validateCloudPublicConfig({
  mode: 'cloud', supabaseUrl: env.BANANA_SUPABASE_URL,
  supabasePublishableKey: env.BANANA_SUPABASE_PUBLISHABLE_KEY,
});
