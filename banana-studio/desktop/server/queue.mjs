let wake=()=>{};
export const setQueueWake = callback => { wake=callback; };
export const IMAGE_JOB_TOPIC='local-image-jobs';
export const publishImageJob = async () => { wake(); };
