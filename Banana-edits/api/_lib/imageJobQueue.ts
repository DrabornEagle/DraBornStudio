import { QueueClient } from '@vercel/queue';

export const IMAGE_JOB_TOPIC = 'banana-image-jobs';
export const imageJobQueue = new QueueClient({ region: 'iad1' });
export type ImageJobMessage = { id: string; userId: string };

export const publishImageJob = async (db: any, job: ImageJobMessage) => {
  await imageJobQueue.send(IMAGE_JOB_TOPIC, job, { idempotencyKey: `image-job:${job.id}`, retentionSeconds: 604800 });
  const { error } = await db.rpc('mark_image_job_published', { p_id: job.id });
  if (error) throw new Error('Queue publication confirmation is unavailable.');
};
