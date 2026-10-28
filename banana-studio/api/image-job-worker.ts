import { createServiceRoleClient } from './_lib/auth.js';
import { imageJobQueue, type ImageJobMessage } from './_lib/imageJobQueue.js';
import { runImageJob, ImageJobWait } from './_lib/imageJobRunner.js';

export const config={maxDuration:300};
// The queue/v2beta trigger makes this function private to Vercel Queues.
export default imageJobQueue.handleNodeCallback<ImageJobMessage>(async message=>{
  const db=createServiceRoleClient(); if(!db) throw new Error('Image worker storage is unavailable.');
  await runImageJob(db,message);
},{visibilityTimeoutSeconds:300,retry:error=>({afterSeconds:error instanceof ImageJobWait?error.afterSeconds:60})});
